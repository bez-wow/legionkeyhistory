-- Talents in your keys: every group member's spec and the talent picked on each tier, saved with the
-- run. Members with LKH send their own (a hidden addon message when the key starts; talents are locked
-- once it runs); the others are inspected. When the key is finished the run is also saved as an upload
-- for Keystone Tauri (run.upload, JSON), which shows each run's talents next to the leaderboard. The game
-- sends nothing anywhere: update.ps1 uploads it, unless sharing is turned off in LKH Updater.cmd.
local H=LegionKeyHistory
local PREFIX='LKHT'
if RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(PREFIX) end
local CLASS_IDS={WARRIOR=1,PALADIN=2,HUNTER=3,ROGUE=4,PRIEST=5,DEATHKNIGHT=6,SHAMAN=7,MAGE=8,WARLOCK=9,MONK=10,DRUID=11,DEMONHUNTER=12}
local UNITS={'player','party1','party2','party3','party4'}
local KEEP_UPLOAD=14*86400 -- Keystone Tauri only takes keys from the last 8 days

local function now() return GetServerTime and GetServerTime() or time() end
local function short(name) return name and (name:match('^([^%-]+)') or name):lower() end

-- The talent picked on each of the 7 tiers (0: none); nil when nothing is picked or it can't be read.
local function readTalents(unit,inspect)
 local group=GetActiveSpecGroup(inspect)
 if not group or group<1 then return end
 local ids,any={},false
 for tier=1,7 do
  ids[tier]=0
  for column=1,3 do
   local id,_,_,selected=GetTalentInfo(tier,column,group,inspect,unit)
   if selected and id and id>0 then ids[tier]=id;any=true end
  end
 end
 return any and ids or nil
end

local function ownTalents()
 local i=GetSpecialization and GetSpecialization()
 local spec=i and GetSpecializationInfo(i)
 local ids=spec and readTalents('player',false)
 if ids then return {spec=spec,ids=ids,source='self',at=now()} end
end

-- What group members' LKH sent, by GUID; copied into the active run (messages can come before it exists).
local heard={}
local function unitOf(sender)
 for _,unit in ipairs(UNITS) do if UnitExists(unit) and short(UnitName(unit))==short(sender) then return unit end end
end
local function remember(run,guid,entry)
 if not run or not guid or not entry then return end
 run.talents=run.talents or {}
 local old=run.talents[guid]
 -- Your own reading beats a message, and a message beats an inspect.
 local rank={self=3,addon=2,inspect=1}
 if not old or rank[entry.source]>=rank[old.source] then run.talents[guid]=entry end
end
local function fillFromHeard(run)
 for _,unit in ipairs(UNITS) do
  local guid=UnitGUID(unit)
  if guid and heard[guid] then remember(run,guid,heard[guid]) end
 end
end

local function groupChannel()
 if IsInGroup(LE_PARTY_CATEGORY_HOME) then return 'PARTY' end
 if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return 'INSTANCE_CHAT' end
end
local lastSent=0
local function send(ask)
 local channel=groupChannel()
 if not channel or not SendAddonMessage then return end
 if ask then SendAddonMessage(PREFIX,'?',channel) end
 if GetTime()-lastSent<2 then return end
 local own=ownTalents()
 if own then lastSent=GetTime();SendAddonMessage(PREFIX,'T|'..own.spec..'|'..table.concat(own.ids,','),channel) end
end

-- ---------------------------------------------------------------------------------------------------------
-- Inspecting group members without LKH, one at a time, until each is read or the key ends.

local pending,attempts,loop={},{},0
local function missing(run)
 for _,unit in ipairs(UNITS) do
  local guid=UnitGUID(unit)
  if guid and unit~='player' and not (run.talents and run.talents[guid]) and (attempts[guid] or 0)<6
   and CanInspect(unit) and UnitIsConnected(unit) and CheckInteractDistance(unit,1) then return unit,guid end
 end
end
local function inspectStep(token)
 local run=H.db and H.db.active
 if token~=loop or not run then return end
 -- Never take over an inspect window the player opened.
 local busy=InspectFrame and InspectFrame:IsShown()
 local unit,guid=missing(run)
 if busy or not unit then C_Timer.After(3,function() inspectStep(token) end);return end
 attempts[guid]=(attempts[guid] or 0)+1
 pending={unit=unit,guid=guid,token=token}
 NotifyInspect(unit)
 C_Timer.After(5,function() if pending.guid==guid and pending.token==token then pending={};inspectStep(token) end end)
end
local function startInspecting()
 loop=loop+1;attempts={};pending={}
 local token=loop
 C_Timer.After(3,function() inspectStep(token) end)
end
local function inspected(guid)
 if not pending.guid or pending.guid~=guid then return end
 local unit,token=pending.unit,pending.token;pending={}
 local run=H.db and H.db.active
 if run and UnitGUID(unit)==guid then
  local spec=GetInspectSpecialization(unit)
  local ids=spec and spec>0 and readTalents(unit,true)
  if ids then remember(run,guid,{spec=spec,ids=ids,source='inspect',at=now()}) end
 end
 ClearInspectPlayer()
 C_Timer.After(1.5,function() inspectStep(token) end)
end

-- ---------------------------------------------------------------------------------------------------------
-- The upload: Keystone Tauri's v1 run (https://keystone-tauri.vercel.app); update.ps1 wraps it in {version,client,run}.

local function json(value)
 local kind=type(value)
 if kind=='string' then
  return '"'..value:gsub('[%c"\\]',function(c)
   local named={['"']='\\"',['\\']='\\\\',['\n']='\\n',['\r']='\\r',['\t']='\\t'}
   return named[c] or string.format('\\u%04x',c:byte())
  end)..'"'
 elseif kind=='number' then return string.format('%d',value)
 elseif kind=='boolean' then return tostring(value)
 elseif value==nil then return 'null' end
 local parts={}
 if value[1]~=nil or value.isArray then
  for _,v in ipairs(value) do parts[#parts+1]=json(v) end
  return '['..table.concat(parts,',')..']'
 end
 for _,k in ipairs(value.order) do parts[#parts+1]=json(k)..':'..json(value[k]) end
 return '{'..table.concat(parts,',')..'}'
end
local function object(order,fields) fields.order=order;return fields end
local function split(full) local name,realm=(full or ''):match('^([^%-]+)%-(.+)$');return name,realm end

function H:BuildUpload(run)
 if run.status~='completed' or not run.serverEndedAt or not run.duration or (run.level or 0)<2 or #(run.members or {})~=5 then return end
 local durationMs=math.floor(run.duration*1000+.5)
 local members={isArray=true}
 for _,m in ipairs(run.members) do
  local name,realm=split(m.name)
  if not name or not CLASS_IDS[m.class] then return end
  local t=run.talents and run.talents[m.guid]
  local talents=t and object({'source','capturedAt','ids'},{source=t.source=='self' and 'self' or 'inspect',capturedAt=t.at,ids=t.ids})
  members[#members+1]=object({'name','realm','classId','specId','talents'},{name=name,realm=realm,classId=CLASS_IDS[m.class],specId=t and t.spec or 0,talents=talents})
 end
 local uploader,uploaderRealm=split(run.owner)
 if not uploader then return end
 local affixes={isArray=true};for i,id in ipairs(run.affixes or {}) do if i<=4 then affixes[#affixes+1]=id end end
 -- The run's id holds your character's GUID; the upload gets a random one instead, kept with the run.
 run.uploadId=run.uploadId or string.format('lkh-%08x%08x',math.random(0,0x7fffffff),math.random(0,0x7fffffff))
 return json(object({'addonRunId','mapId','level','affixes','startedAt','endedAt','endedAtSource','durationMs','onTime','uploader','members'},{
  addonRunId=run.uploadId,mapId=run.mapID,level=run.level,affixes=affixes,
  startedAt=run.serverEndedAt-math.floor(run.duration+.5),endedAt=run.serverEndedAt,endedAtSource='server',
  durationMs=durationMs,onTime=run.timed==true,uploader=object({'name','realm'},{name=uploader,realm=uploaderRealm}),members=members}))
end

-- ---------------------------------------------------------------------------------------------------------
-- Hooks into the run journal (Core.lua).

local baseBegin=H.BeginRun
function H:BeginRun(partial,attempt)
 baseBegin(self,partial,attempt)
 local run=self.db.active
 if not run then return end
 remember(run,UnitGUID('player'),ownTalents())
 fillFromHeard(run)
 send(true)
 startInspecting()
end

local baseComplete=H.CompleteRun
function H:CompleteRun(attempt)
 local run=self.db.active
 baseComplete(self,attempt)
 if not run or run.status~='completed' or run.upload then return end
 run.serverEndedAt=now()
 fillFromHeard(run)
 loop=loop+1;pending={}
 run.upload=self:BuildUpload(run)
 -- Older uploads are past Keystone Tauri's window: drop them so the saved file stays small.
 for _,old in ipairs(self.db.runs) do
  if old.upload and old~=run and (old.serverEndedAt or 0)<run.serverEndedAt-KEEP_UPLOAD then old.upload=nil end
 end
end

local events=CreateFrame('Frame')
for _,event in ipairs({'CHAT_MSG_ADDON','INSPECT_READY','CHALLENGE_MODE_RESET'}) do events:RegisterEvent(event) end
events:SetScript('OnEvent',function(_,event,...)
 if not H.db then return end
 if event=='CHAT_MSG_ADDON' then
  local prefix,msg,_,sender=...
  if prefix~=PREFIX or short(sender)==short(UnitName('player')) then return end
  if msg=='?' then send(false);return end
  local spec,list=msg:match('^T|(%d+)|([%d,]+)$')
  local unit=spec and unitOf(sender)
  local guid=unit and UnitGUID(unit)
  if not guid then return end
  local ids={};for id in list:gmatch('%d+') do ids[#ids+1]=tonumber(id) end
  if #ids~=7 then return end
  heard[guid]={spec=tonumber(spec),ids=ids,source='addon',at=now()}
  if H.db.active then remember(H.db.active,guid,heard[guid]) end
 elseif event=='INSPECT_READY' then inspected(...)
 elseif event=='CHALLENGE_MODE_RESET' then loop=loop+1;pending={} end
end)
