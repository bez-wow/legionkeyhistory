-- Friends' keys: when you look at a friend, your LKH asks theirs (a hidden addon whisper) whether
-- they're in a key, and theirs answers from the game: dungeon, level, timer, bosses, forces, deaths.
-- Answers go only to friends, guildmates and group members, and sharing can be turned off.
local H=LegionKeyHistory
local PREFIX='LKHS'
local FRESH=40        -- seconds a reply stays valid without a new one
local ASK_EVERY=5     -- seconds between asks for one player while hovering
local POLL_EVERY=15   -- seconds between asks for one player while the friends list is open
local ACCENT='4adbc8'
H.keyStatus=H.keyStatus or {}
if RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(PREFIX) end

local function short(name) return name and (name:match('^([^%-]+)') or name):lower() end
local function clock(s) s=math.max(0,math.floor(s+.5));return string.format('%02d:%02d',math.floor(s/60),s%60) end

-- ---------------------------------------------------------------------------------------------------------
-- Answering: what our own game says about the dungeon we're in.

local function scenario()
 local done,total,forces=0,0
 local _,_,steps=C_Scenario.GetStepInfo()
 for i=1,steps or 0 do
  local _,_,completed,cur,max,_,_,quantity,_,_,_,_,weighted=C_Scenario.GetCriteriaInfo(i)
  if weighted or (max and max>=100) then
   local raw=tonumber(quantity and quantity:match('^(%d+)'))
   forces=completed and 100 or (raw and max and max>0 and raw/max*100) or cur or 0
  else
   total=total+1;if completed then done=done+1 end
  end
 end
 return done,total,math.min(100,forces or 0)
end

function H:KeyStatusReply()
 local instanceName,kind,_,difficultyName,_,_,_,instanceID=GetInstanceInfo()
 if kind~='party' then return nil end
 local finished=self.lastFinished
 if finished and finished.instanceID==instanceID and not C_ChallengeMode.IsChallengeModeActive() then
  return string.format('F|%d|%d|%d|%d|%d',finished.mapID,finished.level,math.floor(finished.duration+.5),finished.upgrades or 0,finished.timed and 1 or 0)
 end
 local mapID=C_ChallengeMode.GetActiveChallengeMapID()
 local level,affixes=C_ChallengeMode.GetActiveKeystoneInfo()
 if C_ChallengeMode.IsChallengeModeActive() and mapID and mapID>0 and level and level>0 then
  local _,elapsed=GetWorldElapsedTime(1)
  local _,_,limit=C_ChallengeMode.GetMapInfo(mapID)
  local done,total,forces=scenario()
  local deaths=(C_ChallengeMode.GetDeathCount and C_ChallengeMode.GetDeathCount()) or (self.db.active and self.db.active.deaths) or 0
  return string.format('K|%d|%d|%d|%d|%d|%d|%d|%d|%s',mapID,level,elapsed or 0,limit or 0,done,total,math.floor(forces*10+.5),deaths,table.concat(affixes or {},'.'))
 end
 return 'D|'..(instanceName or '')..'|'..(difficultyName or '')
end

-- Only people who could see us anyway: friends, guildmates, our group.
local function allowed(sender)
 local who=short(sender)
 if not who then return false end
 if UnitInParty(who) or UnitInRaid(who) then return true end
 for i=1,GetNumFriends() do if short(GetFriendInfo(i))==who then return true end end
 if BNGetNumFriends then
  for i=1,BNGetNumFriends() do
   for j=1,BNGetNumFriendGameAccounts(i) do
    local _,name,client=BNGetFriendGameAccountInfo(i,j)
    if client=='WoW' and short(name)==who then return true end
   end
  end
 end
 if IsInGuild() then
  for i=1,GetNumGuildMembers() do if short(GetGuildRosterInfo(i))==who then return true end end
 end
 return false
end

local answered={}
local function answer(sender)
 if not H.settings.shareKeyStatus then return end
 local who=short(sender)
 if answered[who] and GetTime()-answered[who]<2 then return end
 if not allowed(sender) then return end
 local reply=H:KeyStatusReply()
 if reply then answered[who]=GetTime();SendAddonMessage(PREFIX,reply,'WHISPER',sender) end
end

-- ---------------------------------------------------------------------------------------------------------
-- Asking and reading the answers.

local asked={}
function H:AskKeyStatus(name,realm,every)
 if not name or not SendAddonMessage then return end
 local who=short(name)
 if asked[who] and GetTime()-asked[who]<(every or ASK_EVERY) then return end
 asked[who]=GetTime()
 local target=name
 if realm and realm~='' and realm~=GetRealmName() and not name:find('-') then target=name..'-'..realm:gsub('%s','') end
 SendAddonMessage(PREFIX,'?','WHISPER',target)
end

local function parse(msg)
 local f={strsplit('|',msg)}
 if f[1]=='K' then
  local affixes={};for a in (f[10] or ''):gmatch('%d+') do affixes[#affixes+1]=tonumber(a) end
  return {kind='key',mapID=tonumber(f[2]),level=tonumber(f[3]),elapsed=tonumber(f[4]) or 0,limit=tonumber(f[5]) or 0,
   done=tonumber(f[6]) or 0,total=tonumber(f[7]) or 0,forces=(tonumber(f[8]) or 0)/10,deaths=tonumber(f[9]) or 0,affixes=affixes}
 elseif f[1]=='F' then
  return {kind='finished',mapID=tonumber(f[2]),level=tonumber(f[3]),duration=tonumber(f[4]) or 0,upgrades=tonumber(f[5]) or 0,timed=f[6]=='1'}
 elseif f[1]=='D' then
  return {kind='dungeon',instance=f[2],difficulty=f[3]}
 end
end

function H:KeyStatusOf(name)
 local s=name and self.keyStatus[short(name)]
 if s and GetTime()-s.at<=FRESH then return s end
end

local function mapName(mapID)
 local name=mapID and C_ChallengeMode.GetMapInfo(mapID)
 return name or ('Dungeon '..tostring(mapID))
end

-- What replaces the zone in the friends list: "Maw of Souls +11", in the LKH colour.
function H:KeyStatusZone(name)
 local s=self:KeyStatusOf(name)
 if not s then return end
 if s.kind=='key' then return '|cff'..ACCENT..mapName(s.mapID)..' +'..s.level..'|r' end
 if s.kind=='finished' then return '|cff'..ACCENT..mapName(s.mapID)..' +'..s.level..'|r |cff9d9d9d(finished)|r' end
end

-- The block at the top of a friend's tooltip.
function H:AddKeyStatusTooltip(tooltip,name)
 local s=self:KeyStatusOf(name)
 if not s or not self.settings.friendKeyStatus then return false end
 if s.kind=='dungeon' then
  tooltip:AddLine('In '..s.instance..((s.difficulty~='' and ' ('..s.difficulty..', not a key)') or ' (not a key)'),.6,.6,.6)
  tooltip:AddLine(' ')
  return true
 end
 if s.kind=='finished' then
  local result=s.timed and ('|cff20ff20'..(s.upgrades>0 and '+'..s.upgrades or 'timed')..'|r') or '|cffff4040depleted|r'
  tooltip:AddLine('Finished '..mapName(s.mapID)..' +'..s.level..' in '..clock(s.duration)..' ('..result..')',1,1,1)
  tooltip:AddLine(' ')
  return true
 end
 -- The timer keeps running from the moment they answered.
 local elapsed=s.elapsed+(GetTime()-s.at)
 tooltip:AddDoubleLine('In a key','live',.13,1,.13,.5,.5,.5)
 local over=s.limit>0 and elapsed>s.limit
 tooltip:AddDoubleLine('|cff'..ACCENT..mapName(s.mapID)..' +'..s.level..'|r',clock(elapsed)..' / '..clock(s.limit),1,1,1,over and 1 or 1,over and .25 or 1,over and .25 or 1)
 local names={}
 for _,id in ipairs(s.affixes) do local a=C_ChallengeMode.GetAffixInfo(id);if a then names[#names+1]=a end end
 if #names>0 then tooltip:AddLine(table.concat(names,' · '),.7,.8,.9) end
 if s.limit>0 then
  local parts={}
  for i,frac in ipairs({.6,.8,1}) do
   local left=s.limit*frac-elapsed
   parts[i]=left>0 and ('+'..(4-i)..' in '..clock(left)) or ('|cffff4040+'..(4-i)..' lost|r')
  end
  tooltip:AddLine(table.concat(parts,'   '),1,1,1)
 end
 tooltip:AddLine(string.format('Bosses %d/%d · Forces %s%% · %s',s.done,s.total,(string.format('%.1f',s.forces):gsub('%.0$','')),
  s.deaths>0 and ('|cffff4040'..s.deaths..(s.deaths==1 and ' death' or ' deaths')..'|r') or '0 deaths'),1,1,1)
 tooltip:AddLine(' ')
 return true
end

-- While a friend's tooltip with a key is open: count the timer up every second, ask again every few.
local live=CreateFrame('Frame');local since=0
function H:WatchKeyStatusTooltip(owner,name,realm,redraw)
 live.owner,live.name,live.realm,live.redraw=owner,name,realm,redraw
end
live:SetScript('OnUpdate',function(_,dt)
 since=since+dt
 if since<1 then return end
 since=0
 local o=live.owner
 if not o or not GameTooltip:IsOwned(o) then live.owner=nil;return end
 H:AskKeyStatus(live.name,live.realm)
 local s=H:KeyStatusOf(live.name)
 if s and s.kind=='key' then live.redraw(o) end
end)

-- Friends list open: ask online friends now and then (one ask every 0.3 s, each friend every 15 s)
-- so their zone can read "Maw of Souls +11".
local function onlineFriends()
 local list={}
 for i=1,GetNumFriends() do
  local name,_,_,_,connected=GetFriendInfo(i)
  if name and connected then list[#list+1]={name} end
 end
 if BNGetNumFriends then
  local faction=UnitFactionGroup('player')
  for i=1,BNGetNumFriends() do
   for j=1,BNGetNumFriendGameAccounts(i) do
    local _,name,client,realm,_,theirFaction=BNGetFriendGameAccountInfo(i,j)
    if client=='WoW' and name and theirFaction==faction then list[#list+1]={name,realm} end
   end
  end
 end
 return list
end
local poller=CreateFrame('Frame');local pollWait,pollIndex=0,0
poller:SetScript('OnUpdate',function(_,dt)
 pollWait=pollWait+dt
 if pollWait<.3 then return end
 pollWait=0
 if not (H.settings and H.settings.friendKeyList and FriendsFrame and FriendsFrame:IsShown()) then return end
 local list=onlineFriends()
 if #list==0 then return end
 for _=1,#list do
  pollIndex=pollIndex%#list+1
  local f=list[pollIndex]
  local last=asked[short(f[1])]
  if not last or GetTime()-last>=POLL_EVERY then H:AskKeyStatus(f[1],f[2],POLL_EVERY);return end
 end
end)

-- Redraw the friends list at most twice a second when answers come in.
local redrawPending
local function redrawFriends()
 if redrawPending or not (FriendsFrame and FriendsFrame:IsShown() and FriendsList_Update) then return end
 redrawPending=true
 C_Timer.After(.5,function() redrawPending=nil;pcall(FriendsList_Update) end)
end

local events=CreateFrame('Frame')
events:RegisterEvent('CHAT_MSG_ADDON');events:RegisterEvent('COMBAT_LOG_EVENT_UNFILTERED')
events:SetScript('OnEvent',function(_,event,...)
 if not H.settings then return end
 if event=='CHAT_MSG_ADDON' then
  local prefix,msg,channel,sender=...
  if prefix~=PREFIX or channel~='WHISPER' then return end
  if msg=='?' then answer(sender);return end
  local s=parse(msg)
  if s then s.at=GetTime();H.keyStatus[short(sender)]=s;redrawFriends() end
 elseif event=='COMBAT_LOG_EVENT_UNFILTERED' then
  -- Our own death count during a key, for games without C_ChallengeMode.GetDeathCount.
  local run=H.db and H.db.active
  if not run then return end
  local _,sub,_,_,_,_,_,guid,name=...
  if sub=='UNIT_DIED' and guid and guid:find('^Player') and name and (UnitInParty(name) or name==UnitName('player')) and not UnitIsFeignDeath(name) then
   run.deaths=(run.deaths or 0)+1
  end
 end
end)

-- The made-up key used by /lkh keytest and the settings preview.
local function fakeKey()
 return {kind='key',mapID=227,level=11,elapsed=196,limit=1440,done=1,total=3,forces=22,deaths=0,affixes={6,3,9},at=GetTime(),fake=true}
end

-- Settings preview: run fn while `name` is in that made-up key, then put things back.
function H:WithFakeKeyStatus(name,fn)
 local k=short(name);local old=self.keyStatus[k]
 self.keyStatus[k]=fakeKey()
 local ok,err=pcall(fn)
 self.keyStatus[k]=old
 if not ok then error(err,0) end
end

-- /lkh keytest: pretend your first online friend is in a key, to see the list and tooltip.
function H:FakeKeyStatus()
 local f=onlineFriends()[1]
 local who=f and f[1] or UnitName('player')
 self.keyStatus[short(who)]=fakeKey()
 -- Keep it alive for five minutes so there's time to look.
 local s=self.keyStatus[short(who)]
 local ticker;ticker=C_Timer.NewTicker(FRESH-5,function()
  if self.keyStatus[short(who)]~=s or GetTime()-s.started>300 then ticker:Cancel();return end
  s.elapsed=s.elapsed+(GetTime()-s.at);s.at=GetTime()
 end)
 s.started=GetTime()
 H.Message(who..' is now in a fake Maw of Souls +11 for 5 minutes: look at the friends list and hover them.')
 redrawFriends()
end
