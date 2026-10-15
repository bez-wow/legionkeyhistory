-- Settings and profiles, and the "Legion Key History" page in Interface > AddOns.
-- Every character uses the account-wide "Default" profile unless it picks another one.
local H=LegionKeyHistory

H.defaultSettings={
 minimapHidden=false,minimapAngle=220,
 -- Personal Bests
 hud=false,bestMode='timed',hudOverall=true,hudSpec=true,hudClass=true,hudRole=true,
 -- Scores in the game's own windows: next to the name, and details on hover
 scoreFriends=true,hoverFriends=true,scoreApplicants=true,hoverApplicants=true,hoverSearch=true,hoverUnit=true,
 -- Group finder search rows: 'leaderTop', 'dungeonTop' or 'plain' (see FormatSearchRow)
 searchStyle='leaderTop',hoverModifier='always',
 -- Score colour: 'custom' (scoreColor) or 'rio' (Raider.IO-style gradient)
 scoreDecimals=false,scoreSuffix=false,scoreColor='4adbc8',scoreColorMode='rio',
 -- Friends' keys: answer friends/guild asking whether we're in a key; show theirs in the tooltip and list
 shareKeyStatus=true,friendKeyStatus=true,friendKeyList=true,
 -- Party keys: the window in dungeons with each group member's keystone (partyKeysPoint: where)
 partyKeys=true,partyKeysLocked=false,
 -- Score tooltip
 tipRanks=true,tipBestRun=true,tipTimedRuns=true,tipDungeons=true,tipWeekSplit=true,
 -- Journal (not on the settings page)
 showLaterDungeons=false,dayChart='bar',
 -- Font of the addon's windows: 'auto' (Expressway when installed, else Arial Narrow) or a font name
 font='auto'
}
local DEFAULT='Default'
local MODIFIERS={always='Always',ctrl='While holding CTRL',alt='While holding ALT',shift='While holding SHIFT'}
local COLOR_MODES={custom='My colour',rio='Raider.IO style'}
local SEARCH_STYLES={leaderTop='Leader and score on top',dungeonTop='Dungeon on top, leader below',plain='No leader or score'}

local function characterKey()
 local name,realm=UnitName('player')
 return H:IdentityKey(name,realm) or 'unknown'
end

-- Points H.settings at this character's profile; missing values fall back to the defaults.
function H:InitializeProfiles()
 local db=self.db
 db.profiles=db.profiles or {}
 db.profileKeys=db.profileKeys or {}
 -- Saves from before profiles kept one settings table for the whole account.
 if db.settings then db.profiles[DEFAULT]=db.profiles[DEFAULT] or db.settings;db.settings=nil end
 db.profiles[DEFAULT]=db.profiles[DEFAULT] or {}
 -- Sync (party run sharing) was removed in 1.8.0: drop what it saved.
 db.syncDebug=nil
 for _,profile in pairs(db.profiles) do profile.syncMode=nil;profile.syncAutoTrusted=nil end
 local name=db.profileKeys[characterKey()]
 if not name or not db.profiles[name] then name=DEFAULT end
 self.profileName=name
 self.settings=setmetatable(db.profiles[name],{__index=self.defaultSettings})
end

function H:ProfileNames()
 local names={}
 for name in pairs(self.db.profiles) do names[#names+1]=name end
 table.sort(names,function(a,b) if a==DEFAULT then return true elseif b==DEFAULT then return false end;return a<b end)
 return names
end

function H:UseProfile(name)
 self.db.profiles[name]=self.db.profiles[name] or {}
 self.db.profileKeys[characterKey()]=name~=DEFAULT and name or nil
 self:InitializeProfiles();self:ApplySettings()
end

-- Saves the current settings as a new profile and switches this character to it.
function H:SaveProfileAs(name)
 name=(name or ''):gsub('^%s+',''):gsub('%s+$','')
 if name=='' then return false,'Enter a profile name.' end
 if self.db.profiles[name] then return false,'A profile called '..name..' already exists.' end
 local copy={};for key,value in pairs(self.db.profiles[self.profileName]) do copy[key]=value end
 self.db.profiles[name]=copy;self:UseProfile(name)
 return true
end

function H:DeleteProfile(name)
 if name==DEFAULT or not self.db.profiles[name] then return false end
 self.db.profiles[name]=nil
 for character,profile in pairs(self.db.profileKeys) do if profile==name then self.db.profileKeys[character]=nil end end
 self:InitializeProfiles();self:ApplySettings()
 return true
end

-- Characters that use their own profile, for "Copy from character".
function H:ProfileCharacters()
 local list={}
 for character,profile in pairs(self.db.profileKeys) do
  if character~=characterKey() and self.db.profiles[profile] then list[#list+1]={character=character,profile=profile} end
 end
 table.sort(list,function(a,b) return a.character<b.character end)
 return list
end

-- Overwrites the current profile with another profile's values.
function H:CopyProfile(from)
 local source=self.db.profiles[from];if not source or from==self.profileName then return false end
 local target=self.db.profiles[self.profileName];for key in pairs(target) do target[key]=nil end
 for key,value in pairs(source) do target[key]=value end
 self:ApplySettings();return true
end

function H:ResetProfile()
 local target=self.db.profiles[self.profileName];for key in pairs(target) do target[key]=nil end
 self:ApplySettings()
end

-- "LKH1:key=value;..." with every setting, so a friend gets the exact setup.
function H:ExportSettings()
 local keys={};for key in pairs(self.defaultSettings) do keys[#keys+1]=key end;table.sort(keys)
 local parts={}
 for _,key in ipairs(keys) do
  local value=self.settings[key]
  if type(value)=='boolean' then value=value and '1' or '0' end
  parts[#parts+1]=key..'='..tostring(value)
 end
 return 'LKH1:'..table.concat(parts,';')
end

-- Applies only known settings with values of the right type; returns how many were set.
function H:ImportSettings(text)
 local body=(text or ''):match('^%s*LKH1:(.-)%s*$')
 if not body then return nil,'That is not a Legion Key History settings string.' end
 local target=self.db.profiles[self.profileName];local count=0
 for key,value in body:gmatch('([%w_]+)=([^;]*)') do
  local default=self.defaultSettings[key]
  if type(default)=='boolean' and (value=='1' or value=='0') then target[key]=value=='1';count=count+1
  elseif type(default)=='number' and tonumber(value) then target[key]=tonumber(value);count=count+1
  elseif key=='bestMode' and (value=='timed' or value=='completed') then target[key]=value;count=count+1
  elseif key=='dayChart' and (value=='line' or value=='bar') then target[key]=value;count=count+1
  elseif key=='hoverModifier' and MODIFIERS[value] then target[key]=value;count=count+1
  elseif key=='scoreColorMode' and COLOR_MODES[value] then target[key]=value;count=count+1
  elseif key=='searchStyle' and SEARCH_STYLES[value] then target[key]=value;count=count+1
  elseif key=='font' and value~='' then target[key]=value;count=count+1
  elseif key=='scoreColor' and value:match('^%x%x%x%x%x%x$') then target[key]=value:lower();count=count+1 end
 end
 self:ApplySettings()
 return count
end

-- Puts every visible part of the addon in line with the current settings.
function H:ApplySettings()
 if self.SetMinimapHidden then self:SetMinimapHidden(self.settings.minimapHidden) end
 if self.ApplyFontEverywhere and self.settings.font~=self.appliedFont then self.appliedFont=self.settings.font;self:ApplyFontEverywhere() end
 if self.RefreshHUD then self:RefreshHUD() end
 if self.frame and self.frame:IsShown() and self.Refresh then self:Refresh() end
 if self.leaderboardFrame and self.leaderboardFrame:IsShown() and self.RefreshLeaderboard then self:RefreshLeaderboard() end
 if FriendsFrame and FriendsFrame:IsShown() and FriendsList_Update then pcall(FriendsList_Update) end
 if self.RefreshPartyKeys then self:RefreshPartyKeys() end
 if self.settingsPanel and self.settingsPanel:IsShown() then self.settingsPanel:Refresh() end
end

-- "1674 IO", "1674.3 IO", "1674" or "1674.3"; "--" when there is no score.
-- True when version a ("1.10.0") is newer than b ("1.9.2").
function H:VersionNewer(a,b)
 local x,y={},{}
 for n in tostring(a):gmatch('%d+') do x[#x+1]=tonumber(n) end
 for n in tostring(b):gmatch('%d+') do y[#y+1]=tonumber(n) end
 for i=1,math.max(#x,#y) do
  if (x[i] or 0)~=(y[i] or 0) then return (x[i] or 0)>(y[i] or 0) end
 end
 return false
end
-- Once per login: the leaderboard file carries the newest released version.
function H:CheckAddonVersion()
 local latest=LegionKeyHistoryLeaderboard and LegionKeyHistoryLeaderboard.latestAddon
 local current=GetAddOnMetadata and GetAddOnMetadata('LegionKeyHistory','Version')
 if latest and current and self:VersionNewer(latest,current) then
  self.Message('Version '..latest..' is available (you have '..current..'). Run "LKH Updater.cmd" (Linux: "bash LKH-Updater.sh") in the addon folder and choose "Update the addon".')
  return true
 end
 return false
end
-- Opening any LKH window with a newer version out: a small notice at the top of the screen, once
-- per session, saying how to update.
function H:UpdateNotice()
 if self.updateNoticeShown then return end
 local latest=LegionKeyHistoryLeaderboard and LegionKeyHistoryLeaderboard.latestAddon
 local current=GetAddOnMetadata and GetAddOnMetadata('LegionKeyHistory','Version')
 if not (latest and current and self:VersionNewer(latest,current)) then return end
 self.updateNoticeShown=true
 local f=self.updateNoticeFrame
 if not f then
  f=CreateFrame('Frame','LegionKeyHistoryUpdateNotice',UIParent);f:SetSize(440,132);f:SetPoint('TOP',0,-120)
  f:SetFrameStrata('FULLSCREEN_DIALOG');f:SetFrameLevel(200);f:EnableMouse(true)
  f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
  f:SetBackdropColor(.025,.035,.05,.97);f:SetBackdropBorderColor(.29,.86,.78)
  f.title=f:CreateFontString(nil,'ARTWORK','GameFontNormalLarge');f.title:SetPoint('TOP',0,-12)
  f.text=f:CreateFontString(nil,'ARTWORK','GameFontHighlight');f.text:SetPoint('TOP',0,-38);f.text:SetWidth(390);f.text:SetJustifyH('CENTER')
  local ok=CreateFrame('Button',nil,f,'UIPanelButtonTemplate');ok:SetSize(90,22);ok:SetPoint('BOTTOM',0,10);ok:SetText('OK')
  ok:SetScript('OnClick',function() f:Hide() end)
  tinsert(UISpecialFrames,'LegionKeyHistoryUpdateNotice')
  self.updateNoticeFrame=f
 end
 f.title:SetText('|cff4adbc8Legion Key History '..latest..' is out|r')
 f.text:SetText('You have '..current..'. To update, run |cffffd100LKH Updater.cmd|r (Linux: |cffffd100LKH-Updater.sh|r) in your\nInterface\\AddOns\\LegionKeyHistory folder and choose |cffffd1003|r\n(Update the addon to the newest version), then restart WoW.')
 f:Show()
 return true
end
-- noSuffix: for places with their own "IO" heading, such as the applicant column.
function H:FormatScore(score,noSuffix)
 local text=score and string.format(self.settings.scoreDecimals and '%.1f' or '%.0f',score) or '--'
 return (self.settings.scoreSuffix and not noSuffix) and (text..' IO') or text
end
-- Raider.IO colours a score by where it stands among all players this season: white up to the
-- 40th percentile, green at the 40th, blue at the 75th, purple at the 90th, orange for the top 1%
-- and gold (the game's UI gold, ffd100) for the top 0.1%, blended in between. Raider.IO's own numbers come from
-- retail's formula, so the anchors are taken from this leaderboard instead (its scores are stored
-- best first).
local TIER_COLORS={{1,1,1},{.12,1,0},{0,.44,.87},{.64,.21,.93},{1,.5,0},{1,.82,0}}
function H:ScoreTiers()
 local scores=LegionKeyHistoryLeaderboard and LegionKeyHistoryLeaderboard.scores
 if not scores or #scores<20 then return nil end
 if self.scoreTiersFor~=scores then
  local n=#scores
  while n>1 and (scores[n] or 0)<=0 do n=n-1 end
  -- The score that the best `share` of players reach.
  local function top(share) return scores[math.max(1,math.ceil(n*share))] end
  self.scoreTiersFor=scores;self.scoreTiers={scores[n],top(.60),top(.25),top(.10),top(.01),top(.001)}
 end
 return self.scoreTiers
end
local function rgbHex(r,g,b) return string.format('%02x%02x%02x',math.floor(r*255+.5),math.floor(g*255+.5),math.floor(b*255+.5)) end
-- The colour for a score next to names, as r,g,b (0-1) and a |c code: the player's own colour,
-- or a Raider.IO-style colour for that score.
function H:ScoreColor(score)
 local mode=self.settings.scoreColorMode
 local tiers=mode~='custom' and score and score>0 and self:ScoreTiers()
 if tiers then
  local r,g,b
  local last=#tiers
  if score>=tiers[last] then r,g,b=unpack(TIER_COLORS[last])
  elseif score<tiers[1] then r,g,b=.62,.62,.62
  else
   for i=1,last-1 do
    if score<tiers[i+1] then
     local a,c=TIER_COLORS[i],TIER_COLORS[i+1];local t=(score-tiers[i])/math.max(tiers[i+1]-tiers[i],.001)
     r,g,b=a[1]+(c[1]-a[1])*t,a[2]+(c[2]-a[2])*t,a[3]+(c[3]-a[3])*t
     break
    end
   end
  end
  return r,g,b,'|cff'..rgbHex(r,g,b)
 end
 local hex=tostring(self.settings.scoreColor or ''):match('^%x%x%x%x%x%x$') or self.defaultSettings.scoreColor
 return tonumber(hex:sub(1,2),16)/255,tonumber(hex:sub(3,4),16)/255,tonumber(hex:sub(5,6),16)/255,'|cff'..hex
end
-- One run's score on the same colours: as if every dungeon had that run (score x dungeons), so a
-- run that would make a top-1% player is orange.
function H:RunScoreColor(score)
 local dungeons=#((LegionKeyHistoryLeaderboard or {}).dungeons or {})
 return self:ScoreColor(score and score*math.max(dungeons,1))
end
-- "|cff..1787.6|r": a score in its colour, for text built from pieces.
function H:ColoredScore(score,run)
 local hex=select(4,(run and self.RunScoreColor or self.ScoreColor)(self,score))
 return hex..string.format('%.1f',score or 0)..'|r'
end
function H:SetScoreColor(r,g,b)
 self.settings.scoreColor=rgbHex(r,g,b)
 self:ApplySettings()
end

-- Characters with recorded runs, for "Clear history for one character".
function H:HistoryCharacters()
 local counts={}
 for _,run in ipairs(self.db.runs) do
  local key=run.owner and self:IdentityKey(run.owner)
  if key then counts[key]=(counts[key] or 0)+1 end
 end
 local list={};for key,count in pairs(counts) do list[#list+1]={key=key,count=count} end
 table.sort(list,function(a,b) return a.key<b.key end)
 return list
end

function H:ClearCharacterHistory(key)
 local kept,removed={},0
 for _,run in ipairs(self.db.runs) do
  if run.owner and self:IdentityKey(run.owner)==key then removed=removed+1 else kept[#kept+1]=run end
 end
 self.db.runs=kept;self.index={}
 for i,run in ipairs(self.db.runs) do self.index[run.id]=i end
 self.localScoreCache=nil
 if self.Refresh then self:Refresh() end
 return removed
end

function H:DeleteDuplicateRuns()
 local before=#self.db.runs
 self:RepairHistory()
 self.index={};for i,run in ipairs(self.db.runs) do self.index[run.id]=i end
 self.localScoreCache=nil
 if self.Refresh then self:Refresh() end
 return before-#self.db.runs
end

-- Settings previews ---------------------------------------------------------------------------
-- While you point at an option in "Scores in the game" or "How scores look", a window beside the
-- settings mocks that place (friends list, applicants, search results, player tooltip, or score
-- style and colour), drawn with your current settings. It stays while that option's dropdown is
-- open, so each choice can be seen as it is picked.
local BOX_W=256
local CLASS_TOKENS={'WARRIOR','PALADIN','HUNTER','ROGUE','PRIEST','DEATHKNIGHT','SHAMAN','MAGE','WARLOCK','MONK','DRUID','DEMONHUNTER'}
local CLASS_NAMES={'Warrior','Paladin','Hunter','Rogue','Priest','Death Knight','Shaman','Mage','Warlock','Monk','Druid','Demon Hunter'}
-- Example players for the previews: real leaderboard players spread from the top to the middle,
-- so tooltips show real ranks and keys and the colours show their range.
local FALLBACK={{name='Gaangasta',class=11,score=1008},{name='Hanganisback',class=10,score=407},{name='Simanhiil',class=2,score=1180},{name='Pretz',class=10,score=1322}}
local function samplePlayers()
 local data=LegionKeyHistoryLeaderboard;local n=data and data.names and #data.names or 0
 if n<50 or not H.LeaderboardPlayer then return FALLBACK end
 local list={}
 for i,share in ipairs({.04,.45,.15,.01}) do list[i]=H:LeaderboardPlayer(math.max(1,math.ceil(n*share))) or FALLBACK[i] end
 return list
end
local function boxText(parent,template,x,y,w)
 local t=parent:CreateFontString(nil,'ARTWORK',template);t:SetPoint('TOPLEFT',x,y);if w then t:SetWidth(w) end;t:SetJustifyH('LEFT')
 if t.SetWordWrap then t:SetWordWrap(false) end
 return t
end
local function shade(parent,x,y,w,h,a)
 local t=parent:CreateTexture(nil,'BACKGROUND');t:SetPoint('TOPLEFT',x,y);t:SetSize(w,h);t:SetTexture('Interface\\Buttons\\WHITE8X8');t:SetVertexColor(1,1,1,a or .06);return t
end
local function classColor(class)
 local token=type(class)=='number' and CLASS_TOKENS[class] or class
 local c=RAID_CLASS_COLORS and RAID_CLASS_COLORS[token];return c and c.r or 1,c and c.g or 1,c and c.b or 1
end
-- The dungeon a player's best run is in, so group finder previews can show it highlighted.
-- The LKH lines of a tooltip (Leaderboard.lua), when it is loaded.
local function addScore(...) if H.AddScoreTooltip then H:AddScoreTooltip(...) end end
local function bestDungeon(p)
 local bestID,best
 for id,b in pairs(p and p.best or {}) do if not best or b[1]>best[1] then bestID,best=id,b end end
 for _,d in ipairs((LegionKeyHistoryLeaderboard or {}).dungeons or {}) do if d.id==bestID then return d,best[2] end end
 return {id=nil,short='BRH',name='Black Rook Hold'},8
end

function H:CreateSettingsPreview(body,refreshers)
 local box=CreateFrame('Frame','LegionKeyHistorySettingsPreview',UIParent);box:SetSize(BOX_W,60);box:SetFrameStrata('DIALOG');box:Hide()
 box:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
 box:SetBackdropColor(.025,.035,.05,.97);box:SetBackdropBorderColor(.17,.30,.34)
 local caption=boxText(box,'GameFontNormalSmall',8,-6,BOX_W-16)
 -- The hover tooltip under the box: a real tooltip, filled the way the game would fill it.
 local tip=CreateFrame('GameTooltip','LegionKeyHistoryPreviewTooltip',UIParent,'GameTooltipTemplate')
 box:SetScript('OnHide',function() tip:Hide() end)
 local function startTip()
  tip:SetOwner(box,'ANCHOR_NONE');tip:ClearAllPoints();tip:SetPoint('TOPLEFT',box,'BOTTOMLEFT',0,-4)
  return tip
 end
 local views,current={},nil
 local players
 local function view(key,label,build,update)
  local f=CreateFrame('Frame',nil,box);f:SetAllPoints(box);f:Hide()
  views[key]={frame=f,label=label,update=update};build(f)
 end
 local function note(f) return boxText(f,'GameFontHighlightSmall',10,-6,BOX_W-20) end
 -- Friends list: the score at the right of the row; on hover, the score tooltip.
 local friend={}
 view('friends','Friends list',function(f)
  shade(f,6,-22,BOX_W-12,32)
  friend.name=boxText(f,'GameFontNormal',12,-25,150);friend.info=boxText(f,'GameFontDisableSmall',12,-40,150)
  friend.score=f:CreateFontString(nil,'ARTWORK','GameFontNormalSmall');friend.score:SetPoint('TOPRIGHT',-14,-26)
  friend.note=boxText(f,'GameFontHighlightSmall',10,-60,BOX_W-20)
 end,function()
  local p=players[1]
  friend.name:SetText(p.name);friend.name:SetTextColor(classColor(p.class));friend.info:SetText('Level 110 '..(CLASS_NAMES[p.class] or '')..' - Dalaran')
  friend.score:SetText(H.settings.scoreFriends and H:FormatScore(p.score) or '');friend.score:SetTextColor(H:ScoreColor(p.score))
  friend.note:SetText(H.settings.hoverFriends and '' or '|cff9d9d9dNo tooltip on hover|r')
  box:SetHeight(H.settings.hoverFriends and 62 or 76)
  if H.settings.hoverFriends then
   local t=startTip();t:SetText(p.name,classColor(p.class));addScore(t,p.name,p.realm);t:Show()
  end
 end)
 -- Friends in keys: a friend in a made-up Maw of Souls +11; the zone and the tooltip follow the settings.
 local keys={}
 view('friendkeys','Friends in keys',function(f)
  shade(f,6,-22,BOX_W-12,32)
  keys.name=boxText(f,'GameFontNormal',12,-25,150);keys.info=boxText(f,'GameFontDisableSmall',12,-40,190)
  keys.score=f:CreateFontString(nil,'ARTWORK','GameFontNormalSmall');keys.score:SetPoint('TOPRIGHT',-14,-26)
  keys.note=boxText(f,'GameFontHighlightSmall',10,-60,BOX_W-20)
 end,function()
  local p=players[1]
  keys.name:SetText(p.name);keys.name:SetTextColor(classColor(p.class))
  keys.score:SetText(H.settings.scoreFriends and H:FormatScore(p.score) or '');keys.score:SetTextColor(H:ScoreColor(p.score))
  keys.note:SetText(H.settings.shareKeyStatus and '' or '|cff9d9d9dYou are not sharing your own key: friends will not see yours.|r')
  box:SetHeight(H.settings.shareKeyStatus and 62 or 76)
  if not H.WithFakeKeyStatus then return end
  H:WithFakeKeyStatus(p.name,function()
   local zone=H.settings.friendKeyList and H:KeyStatusZone(p.name)
   keys.info:SetText(zone or 'Level 110 '..(CLASS_NAMES[p.class] or '')..' - Helmouth Cliffs')
   if H.settings.friendKeyStatus or H.settings.hoverFriends then
    local t=startTip();t:SetText(p.name,classColor(p.class))
    H:AddKeyStatusTooltip(t,p.name)
    if H.settings.hoverFriends then addScore(t,p.name,p.realm) end
    t:Show()
   end
  end)
 end)
 -- Applicants: Name | IO | Role | iLvl; the tooltip is the game's, plus the score for the
 -- listed dungeon (here the first player's best, so its line shows green).
 local app={rows={}}
 view('applicants','Group finder applicants',function(f)
  app.head={name=boxText(f,'GameFontNormalSmall',12,-24),io=boxText(f,'GameFontNormalSmall',108,-24),role=boxText(f,'GameFontNormalSmall',142,-24),ilvl=boxText(f,'GameFontNormalSmall',206,-24)}
  app.head.name:SetText('Name');app.head.io:SetText('IO');app.head.role:SetText('Role');app.head.ilvl:SetText('iLvl')
  for i=1,2 do
   local y=-40-(i-1)*22;shade(f,6,y,BOX_W-12,20)
   local row={};app.rows[i]=row
   row.name=boxText(f,'GameFontNormalSmall',12,y-5,90);row.score=boxText(f,'GameFontNormalSmall',104,y-5,40)
   row.role=f:CreateTexture(nil,'ARTWORK');row.role:SetSize(14,14);row.role:SetAtlas('groupfinder-icon-role-large-dps')
   row.role:SetPoint('TOPLEFT',148,y-3)
   row.ilvl=boxText(f,'GameFontNormalSmall',206,y-5,40)
  end
 end,function()
  local io=H.settings.scoreApplicants
  app.head.io:SetShown(io)
  for i,row in ipairs(app.rows) do
   local p=players[i]
   row.name:SetText(p.name);row.name:SetTextColor(classColor(p.class))
   row.score:SetShown(io);row.score:SetText(H:FormatScore(p.score,true));row.score:SetTextColor(H:ScoreColor(p.score))
   row.ilvl:SetText(i==1 and '873' or '865');row.ilvl:SetTextColor(1,.82,0)
  end
  box:SetHeight(88)
  local p=players[1];local d=bestDungeon(p);local t=startTip()
  t:SetText(p.name,classColor(p.class));t:AddLine('Level 110 '..(CLASS_NAMES[p.class] or ''),1,1,1);t:AddLine('Item Level: 873',1,1,1)
  if H.settings.hoverApplicants then addScore(t,p.name,p.realm,d.id) end
  t:Show()
 end)
 -- Search results: two groups in the chosen list style; the tooltip is the game's plus the
 -- leader's score for that dungeon.
 local search={rows={}}
 view('search','Group finder search results',function(f)
  for i=1,2 do
   local y=-22-(i-1)*38;shade(f,6,y,BOX_W-12,36)
   local row={};search.rows[i]=row
   row.name=f:CreateFontString(nil,'ARTWORK','GameFontNormal');row.name:SetPoint('TOPLEFT',14,y-4);row.name:SetJustifyH('LEFT')
   row.activity=boxText(f,'GameFontDisableSmallLeft',14,y-20,176)
  end
 end,function()
  local groups={}
  for i,row in ipairs(search.rows) do
   local p=players[i];local d,level=bestDungeon(p)
   local title=i==1 and (d.short..' +'..level) or ('M'..level..' '..d.short..' LF TANK')
   groups[i]={p=p,d=d,title=title}
   if H.FormatSearchRow then H:FormatSearchRow(row.name,row.activity,title,d.name..' (Mythic Keystone)',d.short,p.name,176,false) end
  end
  box:SetHeight(102)
  local g=groups[1];local t=startTip()
  t:SetText(g.title,1,1,1);t:AddLine(g.d.name..' (Mythic Keystone)',1,.82,0);t:AddLine(' ');t:AddLine('Leader: |cffffffff'..g.p.name..'|r',1,.82,0)
  if H.settings.hoverSearch then addScore(t,g.p.name,g.p.realm,g.d.id) end
  t:Show()
 end)
 -- Player tooltip: the game's lines, then the LKH lines (and the key to hold, if any).
 local unit={}
 view('unit','Player tooltip',function() end,function()
  local p=players[1];local on=H.settings.hoverUnit
  box:SetHeight(24)
  local t=startTip()
  t:SetText(p.name,classColor(p.class));t:AddLine('<Some Guild>',.25,1,.25);t:AddLine('Level 110 '..(CLASS_NAMES[p.class] or ''),1,1,1)
  if on then addScore(t,p.name,p.realm) end
  t:Show()
 end)
 -- Score style and colour: players with scores from high to the middle of the leaderboard.
 local look={rows={}}
 view('look','Score style and colour',function(f)
  for i=1,4 do
   local y=-22-(i-1)*24;shade(f,6,y,BOX_W-12,22)
   local row={};look.rows[i]=row
   row.name=boxText(f,'GameFontNormal',12,y-5,140)
   row.score=f:CreateFontString(nil,'ARTWORK','GameFontNormal');row.score:SetPoint('TOPRIGHT',-14,y-5)
  end
 end,function()
  local sorted={};for i,p in ipairs(players) do sorted[i]=p end
  table.sort(sorted,function(a,b) return (a.score or 0)<(b.score or 0) end)
  for i,row in ipairs(look.rows) do
   local p=sorted[i];row.name:SetText(p.name);row.name:SetTextColor(classColor(p.class))
   row.score:SetText(H:FormatScore(p.score));row.score:SetTextColor(H:ScoreColor(p.score))
  end
  box:SetHeight(124)
 end)
 -- show(view) opens the window on that view beside the settings; show(nil) closes it.
 local function show(key)
  if not key then box:Hide();return end
  players=samplePlayers()
  current=views[key] and key or 'friends'
  for k,v in pairs(views) do v.frame:SetShown(k==current) end
  caption:SetText('PREVIEW  |cff9d9d9d'..views[current].label..'|r')
  tip:Hide()
  box:ClearAllPoints();box:SetPoint('TOPLEFT',InterfaceOptionsFrame or UIParent,'TOPRIGHT',6,0);box:Show()
  views[current].update()
 end
 -- One preview at a time beside the settings: a view in the window above, 'tooltip' (your own
 -- score tooltip) or 'hud' (the Personal Bests panel).
 local kind
 local function showTooltip()
  local name,realm=UnitName('player');local _,class=UnitClass('player')
  tip:SetOwner(UIParent,'ANCHOR_NONE');tip:ClearAllPoints();tip:SetPoint('TOPLEFT',InterfaceOptionsFrame or UIParent,'TOPRIGHT',6,0)
  tip:SetText(name or '',classColor(class));tip:AddLine('Preview: your own score tooltip',.6,.6,.6)
  addScore(tip,name,realm);tip:Show()
 end
 local function set(k)
  kind=k
  if k~='hud' and H.hudPreview then H:PreviewHUD(false) end
  if k=='tooltip' then box:Hide();showTooltip()
  elseif k=='hud' then box:Hide();tip:Hide();H:PreviewHUD(true)
  elseif k then show(k)
  else box:Hide();tip:Hide() end
 end
 refreshers[#refreshers+1]=function()
  if kind=='tooltip' then showTooltip() elseif kind and kind~='hud' then show(kind) end
 end
 -- A preview shows while the mouse is over its option, and while the dropdown that option opened
 -- is open. After a pick it stays ("sticky") so the result can be seen, until the mouse points at
 -- another control or leaves the settings window. With "Preview" ticked it always stays.
 local owner,sticky,pinned
 -- A list an option opened: a dropdown, or the font list (which stays open while fonts are tried).
 local function listOpen() return (DropDownList1 and DropDownList1:IsShown()) or (H.fontPicker and H.fontPicker:IsShown()) end
 -- Clicking an option (ticking a box, say) keeps its preview open after the mouse leaves, until
 -- the mouse points at another control, so the change can be seen.
 local clicked
 local function hoverPreview(frame,k)
  frame:HookScript('OnEnter',function() if listOpen() and owner~=frame then return end;if owner~=frame then clicked=false end;owner,sticky=frame,false;set(k) end)
  frame:HookScript('OnLeave',function() if not pinned and not sticky and not clicked and not listOpen() then owner=nil;set(nil) end end)
  if frame.HasScript and frame:HasScript('OnClick') then
   frame:HookScript('OnClick',function() owner,clicked=frame,true;set(k) end)
  end
 end
 local function listClosed() if owner and kind then sticky=true end end
 if DropDownList1 and DropDownList1.HookScript then DropDownList1:HookScript('OnHide',listClosed) end
 H.SettingsListClosed=listClosed
 local scroll=body:GetParent();local panel=scroll and scroll:GetParent()
 local neutral={[body]=true}
 for _,f in ipairs({scroll,panel,InterfaceOptionsFrame,InterfaceOptionsFramePanelContainer}) do if f then neutral[f]=true end end
 local watch=CreateFrame('Frame',nil,panel or body)
 watch:SetScript('OnUpdate',function()
  if pinned or not (sticky or clicked) or listOpen() then return end
  local focus=GetMouseFocus and GetMouseFocus()
  if focus==owner then sticky=false
  elseif focus and not neutral[focus] then sticky,clicked=false,false;owner=nil;set(nil) end
 end)
 local function pin(on)
  pinned=on and true or false;sticky,clicked=false,false
  if pinned then set(kind or 'search') else owner=nil;set(nil) end
 end
 return set,hoverPreview,pin
end

-- The Personal Bests panel beside the settings window (see RefreshHUD).
function H:PreviewHUD(on)
 self.hudPreview=on or nil
 if self.RefreshHUD then self:RefreshHUD() end
end

-- The settings page --------------------------------------------------------------------------

local function menu(owner,items)
 if not H.settingsMenu then H.settingsMenu=CreateFrame('Frame','LKHSettingsMenu',UIParent,'UIDropDownMenuTemplate') end
 if H.fontPicker then H.fontPicker:Hide() end
 H:Menu(items,H.settingsMenu,owner)
end

local function confirm(text,onAccept)
 StaticPopupDialogs.LKH_CONFIRM=StaticPopupDialogs.LKH_CONFIRM or {button1=YES,button2=NO,timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3}
 StaticPopupDialogs.LKH_CONFIRM.text=text
 StaticPopupDialogs.LKH_CONFIRM.OnAccept=onAccept
 StaticPopup_Show('LKH_CONFIRM')
end

-- The Font setting's list: a short scrolling list under its button, each name in its own font.
-- (A dropdown of every LibSharedMedia font runs off the screen.)
local PICKER_ROWS=14
local function fontPicker(owner)
 local p=H.fontPicker
 if not p then
  p=CreateFrame('Frame','LKHFontPicker',UIParent);H.fontPicker=p
  p:SetSize(260,PICKER_ROWS*20+12);p:SetFrameStrata('FULLSCREEN_DIALOG');p:SetClampedToScreen(true)
  p:EnableMouse(true);p:EnableMouseWheel(true);p:Hide();tinsert(UISpecialFrames,'LKHFontPicker')
  p:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
  p:SetBackdropColor(.025,.035,.05,.97);p:SetBackdropBorderColor(.17,.30,.34)
  p.offset=0
  local bar=p:CreateTexture(nil,'ARTWORK');bar:SetColorTexture(.29,.86,.78,.6);bar:SetWidth(3);p.bar=bar
  p.rows={}
  for i=1,PICKER_ROWS do
   local b=CreateFrame('Button',nil,p);b:SetSize(244,20);b:SetPoint('TOPLEFT',6,-6-(i-1)*20)
   local hl=b:CreateTexture(nil,'HIGHLIGHT');hl:SetAllPoints();hl:SetColorTexture(1,1,1,.08)
   b.label=b:CreateFontString(nil,'OVERLAY');b.label:SetPoint('LEFT',6,0);b.label:SetPoint('RIGHT',-6,0);b.label:SetJustifyH('LEFT')
   -- Picking applies the font at once and keeps the list open, so several can be tried.
   b:SetScript('OnClick',function(s) H.settings.font=s.name;H:ApplySettings();p:Refresh() end)
   p.rows[i]=b
  end
  function p:Refresh()
   local count=#self.names;self.offset=math.max(0,math.min(self.offset,count-PICKER_ROWS))
   for i,b in ipairs(self.rows) do
    local name=self.names[self.offset+i];b.name=name;b:SetShown(name~=nil)
    if name then
     -- A font file that fails to load falls back to Arial Narrow, so the name still shows.
     if b.label:SetFont(H:FontPath(name),12,'')==false or not b.label:GetFont() then b.label:SetFont(H.builtinFonts['Arial Narrow'],12,'') end
     b.label:SetText(name=='auto' and 'Automatic (Expressway if installed)' or name)
     if name==H.settings.font then b.label:SetTextColor(.29,.86,.78) else b.label:SetTextColor(.85,.9,.93) end
    end
   end
   -- Where the visible rows are in the whole list.
   local track=PICKER_ROWS*20;self.bar:SetShown(count>PICKER_ROWS)
   if count>PICKER_ROWS then
    self.bar:SetHeight(math.max(12,track*PICKER_ROWS/count));self.bar:ClearAllPoints()
    self.bar:SetPoint('TOPRIGHT',-3,-6-(track-self.bar:GetHeight())*self.offset/(count-PICKER_ROWS))
   end
  end
  p:SetScript('OnMouseWheel',function(s,delta) s.offset=s.offset-delta*3;s:Refresh() end)
  p:SetScript('OnHide',function() if H.SettingsListClosed then H.SettingsListClosed() end end)
 end
 if p:IsShown() then p:Hide();return end
 p.names={'auto'};for _,name in ipairs(H:FontNames()) do p.names[#p.names+1]=name end
 p.offset=0
 for i,name in ipairs(p.names) do if name==H.settings.font then p.offset=i-math.floor(PICKER_ROWS/2) end end
 p:ClearAllPoints();p:SetPoint('TOPLEFT',owner,'BOTTOMLEFT',0,-2);p:Refresh();p:Show()
end

H.OpenFontPicker=fontPicker
function H:CreateSettingsPanel()
 if self.settingsPanel then return self.settingsPanel end
 local panel=CreateFrame('Frame','LegionKeyHistorySettings',UIParent);panel.name='Legion Key History';panel:Hide()
 self.settingsPanel=panel
 local scroll=CreateFrame('ScrollFrame','LegionKeyHistorySettingsScroll',panel,'UIPanelScrollFrameTemplate')
 scroll:SetPoint('TOPLEFT',4,-4);scroll:SetPoint('BOTTOMRIGHT',-28,4)
 local body=CreateFrame('Frame',nil,scroll);body:SetSize(560,1360);scroll:SetScrollChild(body)
 -- Open lists stay where they opened, so scrolling the page closes them.
 scroll:HookScript('OnVerticalScroll',function() CloseDropDownMenus();if H.fontPicker then H.fontPicker:Hide() end end)
 local y=-12
 local refreshers={}
 local function heading(text)
  y=y-10
  local t=body:CreateFontString(nil,'ARTWORK','GameFontNormalLarge');t:SetPoint('TOPLEFT',14,y);t:SetText(text)
  y=y-26
 end
 local function note(text)
  local t=body:CreateFontString(nil,'ARTWORK','GameFontHighlightSmall');t:SetPoint('TOPLEFT',22,y);t:SetWidth(520);t:SetJustifyH('LEFT');t:SetText(text)
  y=y-(t:GetStringHeight()>14 and 30 or 18)
  return t
 end
 local hoverPreview
 local function check(label,key,previewKind)
  local cb=CreateFrame('CheckButton',nil,body,'InterfaceOptionsCheckButtonTemplate');cb:SetPoint('TOPLEFT',16,y)
  cb.Text:SetText(label);cb.label=label
  cb:SetScript('OnClick',function(s) H.settings[key]=s:GetChecked() and true or false;H:ApplySettings() end)
  refreshers[#refreshers+1]=function() cb:SetChecked(H.settings[key]==true) end
  if previewKind then hoverPreview(cb,previewKind) end
  y=y-28
  return cb
 end
 local function choice(label,width,current,items)
  local t=body:CreateFontString(nil,'ARTWORK','GameFontHighlight');t:SetPoint('TOPLEFT',22,y-5);t:SetText(label)
  local b=CreateFrame('Button',nil,body,'UIPanelButtonTemplate');b:SetSize(width,22);b:SetPoint('TOPLEFT',230,y)
  b:SetScript('OnClick',function(s) menu(s,items()) end)
  refreshers[#refreshers+1]=function() b:SetText(current()) end
  y=y-30
  return b
 end
 local function action(label,width,x,onClick)
  local b=CreateFrame('Button',nil,body,'UIPanelButtonTemplate');b:SetSize(width,22);b:SetPoint('TOPLEFT',x,y);b:SetText(label)
  b:SetScript('OnClick',onClick)
  return b
 end

 local title=body:CreateFontString(nil,'ARTWORK','GameFontNormalHuge');title:SetPoint('TOPLEFT',14,y);title:SetText('|cff4adbc8Legion Key History|r')
 local version=body:CreateFontString(nil,'ARTWORK','GameFontDisableSmall');version:SetPoint('BOTTOMLEFT',title,'BOTTOMRIGHT',8,3)
 version:SetText('v'..(GetAddOnMetadata and GetAddOnMetadata('LegionKeyHistory','Version') or '?'));y=y-34
 local preview,pinPreview;preview,hoverPreview,pinPreview=H:CreateSettingsPreview(body,refreshers);H.ShowSettingsPreview=preview

 -- "Preview": keep the preview beside the settings open while browsing every section.
 local previewCheck=CreateFrame('CheckButton',nil,body,'InterfaceOptionsCheckButtonTemplate');previewCheck:SetPoint('TOPLEFT',300,y-6)
 previewCheck.Text:SetText('Preview');previewCheck:SetChecked(false)
 previewCheck:SetScript('OnClick',function(s) pinPreview(s:GetChecked()) end)
 previewCheck.tooltipText='Keep the preview beside this window open. It follows the option you point at.'
 heading('General')
 local minimap=check('Show the minimap icon','minimapHidden')
 minimap:SetScript('OnClick',function(s) H.settings.minimapHidden=not s:GetChecked();H:ApplySettings() end)
 refreshers[#refreshers+1]=function() minimap:SetChecked(not H.settings.minimapHidden) end
 -- Font of the addon's windows. Automatic: ElvUI's Expressway when installed, else Arial Narrow.
 local fontChoice=choice('Font',200,function() return H.settings.font=='auto' and 'Automatic' or H.settings.font end,function() end)
 fontChoice:SetScript('OnClick',function(s) CloseDropDownMenus();fontPicker(s) end)
 hoverPreview(fontChoice,'hud')

 heading('Scores in the game')
 -- One row per place, with separate switches for the score next to the name and the details on hover.
 local function gridHeader(text,x)
  local t=body:CreateFontString(nil,'ARTWORK','GameFontNormalSmall');t:SetPoint('TOPLEFT',x,y);t:SetText(text)
 end
 note('Point at an option below to see it beside this window, with your settings.')
 gridHeader('Score next to name',250);gridHeader('Details on hover',390);y=y-18
 -- Pointing at a row (its name or a box) shows that place in the preview at the top.
 local function gridRow(label,scoreKey,hoverKey,view)
  local t=body:CreateFontString(nil,'ARTWORK','GameFontHighlight');t:SetPoint('TOPLEFT',22,y-6);t:SetText(label)
  local zone=CreateFrame('Frame',nil,body);zone:SetPoint('TOPLEFT',18,y);zone:SetSize(260,26);zone:EnableMouse(true)
  hoverPreview(zone,view)
  for column,key in ipairs({scoreKey or false,hoverKey}) do
   if key then
    local cb=CreateFrame('CheckButton',nil,body,'InterfaceOptionsCheckButtonTemplate');cb:SetPoint('TOPLEFT',column==1 and 290 or 425,y)
    cb.Text:SetText('');cb.label=label..(column==1 and ': score next to name' or ': details on hover')
    cb:SetScript('OnClick',function(s) H.settings[key]=s:GetChecked() and true or false;H:ApplySettings() end)
    hoverPreview(cb,view)
    refreshers[#refreshers+1]=function() cb:SetChecked(H.settings[key]==true) end
   end
  end
  y=y-28
 end
 gridRow('Friends list','scoreFriends','hoverFriends','friends')
 gridRow('Group finder applicants','scoreApplicants','hoverApplicants','applicants')
 gridRow('Group finder search results',nil,'hoverSearch','search')
 gridRow('Player tooltip (world and unit frames)',nil,'hoverUnit','unit')

 heading('How scores look')
 -- Group finder list: how each group's rows read (shown in the preview at the top).
 local listChoice=choice('Group finder list',200,function() return SEARCH_STYLES[H.settings.searchStyle] or SEARCH_STYLES.leaderTop end,function()
  local items={}
  for _,key in ipairs({'leaderTop','dungeonTop','plain'}) do
   items[#items+1]={text=SEARCH_STYLES[key],checked=H.settings.searchStyle==key,func=function() H.settings.searchStyle=key;H:ApplySettings() end}
  end
  return items
 end)
 hoverPreview(listChoice,'search')
 local keyChoice=choice('Player tooltip score',150,function() return MODIFIERS[H.settings.hoverModifier] or MODIFIERS.always end,function()
  local items={}
  for _,key in ipairs({'always','ctrl','alt','shift'}) do
   items[#items+1]={text=MODIFIERS[key],checked=H.settings.hoverModifier==key,func=function() H.settings.hoverModifier=key;H:ApplySettings() end}
  end
  return items
 end)
 local styles={{false,true},{true,true},{false,false},{true,false}}
 local styleChoice=choice('Score style',150,function() return H:FormatScore(1674.34) end,function()
  local items={}
  for _,style in ipairs(styles) do
   local decimals,suffix=style[1],style[2]
   items[#items+1]={text=(decimals and '1674.3' or '1674')..(suffix and ' IO' or ''),
    checked=H.settings.scoreDecimals==decimals and H.settings.scoreSuffix==suffix,
    func=function() H.settings.scoreDecimals=decimals;H.settings.scoreSuffix=suffix;H:ApplySettings() end}
  end
  return items
 end)
 hoverPreview(styleChoice,'look')
 -- Colour of the score next to names (friends list, applicants, search results).
 local colorChoice=choice('Score colour',150,function() return COLOR_MODES[H.settings.scoreColorMode] or COLOR_MODES.rio end,function()
  local items={}
  for _,key in ipairs({'custom','rio'}) do
   items[#items+1]={text=COLOR_MODES[key],checked=H.settings.scoreColorMode==key,func=function() H.settings.scoreColorMode=key;H:ApplySettings() end}
  end
  return items
 end)
 hoverPreview(colorChoice,'look')
 local swatch=CreateFrame('Button',nil,body);swatch:SetSize(22,22);swatch:SetPoint('TOPLEFT',230,y);hoverPreview(swatch,'look')
 swatch.texture=swatch:CreateTexture(nil,'ARTWORK');swatch.texture:SetAllPoints(swatch);swatch.texture:SetTexture('Interface\\Buttons\\WHITE8X8')
 local sample=body:CreateFontString(nil,'ARTWORK','GameFontNormal');sample:SetPoint('TOPLEFT',262,y-4)
 -- Raider.IO modes: a preview of the colour bands on this leaderboard instead of the picker.
 local bands=body:CreateFontString(nil,'ARTWORK','GameFontNormal');bands:SetPoint('TOPLEFT',230,y-4)
 refreshers[#refreshers+1]=function()
  local custom=H.settings.scoreColorMode=='custom' or not H:ScoreTiers()
  swatch:SetShown(custom);sample:SetShown(custom);bands:SetShown(not custom)
  if H.defaultColorButton then H.defaultColorButton:SetShown(custom) end
  if custom then
   local r,g,b=H:ScoreColor();swatch.texture:SetVertexColor(r,g,b);sample:SetText(H:FormatScore(1674.34));sample:SetTextColor(r,g,b)
  else
   local parts={}
   for i,score in ipairs(H:ScoreTiers()) do local _,_,_,hex=H:ScoreColor(score);parts[i]=hex..string.format('%.0f',score)..'|r' end
   bands:SetText(table.concat(parts,'  '))
  end
 end
 swatch:SetScript('OnClick',function()
  local r,g,b=H:ScoreColor()
  local function apply(restore)
   if restore then H:SetScoreColor(restore.r,restore.g,restore.b) else H:SetScoreColor(ColorPickerFrame:GetColorRGB()) end
  end
  ColorPickerFrame.hasOpacity=false;ColorPickerFrame.previousValues={r=r,g=g,b=b}
  ColorPickerFrame.func=apply;ColorPickerFrame.cancelFunc=apply
  ColorPickerFrame:SetColorRGB(r,g,b);ColorPickerFrame:Hide();ColorPickerFrame:Show()
 end)
 H.defaultColorButton=action('Default colour',110,340,function() H.settings.scoreColor=nil;H:ApplySettings() end)
 y=y-32

 heading('Score tooltip shows')
 note('Point at an option to see your own tooltip beside this window.')
 check('Overall, spec and class rank','tipRanks','tooltip')
 check('Best run','tipBestRun','tooltip')
 check('Timed +10-14, +15-19 and +20+ runs','tipTimedRuns','tooltip')
 check('Best key per dungeon','tipDungeons','tooltip')
 check('Best Fortified / Tyrannical key per dungeon (instead of time and score)','tipWeekSplit','tooltip')

 heading('Personal Bests')
 note('Point at an option to see the panel beside this window.')
 check('Show next to Mythic Dungeons in the Dungeon Finder','hud','hud')
 local records=choice('Records',150,function() return H.settings.bestMode=='completed' and 'Highest completed' or 'Best timed' end,function()
  return {{text='Best timed',checked=H.settings.bestMode~='completed',func=function() H.settings.bestMode='timed';H:ApplySettings() end},
   {text='Highest completed',checked=H.settings.bestMode=='completed',func=function() H.settings.bestMode='completed';H:ApplySettings() end}}
 end)
 hoverPreview(records,'hud')
 check('Overall rank column','hudOverall','hud')
 check('Spec rank column','hudSpec','hud')
 check('Class rank column','hudClass','hud')
 check('Role rank column','hudRole','hud')

 heading('Friends in keys')
 note('Friends and guildmates who also use LKH tell you live whether they are in a key. Point at an option to see it; /lkh keytest shows it on a real friend.')
 check('Share whether I am in a key with friends, guild and group','shareKeyStatus','friendkeys')
 check('Show their key in the friends list tooltip (timer, bosses, forces, deaths)','friendKeyStatus','friendkeys')
 check('Show their key instead of the zone in the friends list ("Maw of Souls +11")','friendKeyList','friendkeys')

 heading('Party keys')
 note('Inside a dungeon, a small window lists the keystone each group member has; keys for the dungeon you are in are on top, in green. Group members with LKH send theirs; keystones linked in party chat (!keys) count too.')
 check('Show the party keys window in dungeons','partyKeys')
 action('Move it',90,28,function() H:TogglePartyKeysLock() end);y=y-32

 heading('Your group')
 note('Everyone in your group side by side: score, ranks, best key per dungeon and timed keys. Also /lkh party.')
 action('Open the group window',170,28,function() H:OpenParty() end);y=y-32

 heading('Profile')
 note('Every character uses the account-wide Default profile unless you pick another one here.')
 choice('Profile for this character',190,function() return H.profileName end,function()
  local items={}
  for _,name in ipairs(H:ProfileNames()) do items[#items+1]={text=name,checked=name==H.profileName,func=function() H:UseProfile(name) end} end
  return items
 end)
 local nameBox=CreateFrame('EditBox',nil,body,'InputBoxTemplate');nameBox:SetSize(150,22);nameBox:SetPoint('TOPLEFT',28,y);nameBox:SetAutoFocus(false)
 nameBox:SetScript('OnEscapePressed',function(s) s:ClearFocus() end)
 action('Save as new profile',150,190,function()
  local ok,why=H:SaveProfileAs(nameBox:GetText());if ok then nameBox:SetText('');nameBox:ClearFocus() else H.Message(why) end
 end)
 action('Delete this profile',130,350,function()
  if H.profileName=='Default' then H.Message('The Default profile cannot be deleted.');return end
  local name=H.profileName;confirm('Delete the profile "'..name..'"?',function() H:DeleteProfile(name) end)
 end)
 y=y-32
 action('Copy from character',150,22,function(s)
  local items={}
  for _,entry in ipairs(H:ProfileCharacters()) do
   items[#items+1]={text=entry.character..'  ('..entry.profile..')',notCheckable=true,func=function()
    confirm('Replace the "'..H.profileName..'" profile with the settings of '..entry.character..'?',function() H:CopyProfile(entry.profile) end)
   end}
  end
  if #items==0 then items[1]={text='No other character uses its own profile',notCheckable=true,disabled=true} end
  menu(s,items)
 end)
 action('Reset to defaults',130,182,function()
  confirm('Reset the "'..H.profileName..'" profile to the default settings?',function() H:ResetProfile() end)
 end)
 y=y-32
 note('Export copies your settings as a line of text you can send to a friend. Paste one into the box and click Import to use it.')
 local share=CreateFrame('EditBox',nil,body,'InputBoxTemplate');share:SetSize(330,22);share:SetPoint('TOPLEFT',28,y);share:SetAutoFocus(false)
 share:SetScript('OnEscapePressed',function(s) s:ClearFocus() end)
 action('Export',70,370,function() share:SetText(H:ExportSettings());share:SetFocus();share:HighlightText() end)
 action('Import',70,445,function()
  local count,why=H:ImportSettings(share:GetText())
  if count then H.Message('Imported '..count..' settings into the "'..H.profileName..'" profile.');share:SetText('') else H.Message(why) end
 end)
 y=y-36

 heading('Data')
 action('Import from file',150,22,function() H:ImportSnapshot() end)
 local fileDate=body:CreateFontString(nil,'ARTWORK','GameFontHighlightSmall');fileDate:SetPoint('TOPLEFT',184,y-5)
 refreshers[#refreshers+1]=function()
  local data=LegionKeyHistoryLeaderboard
  fileDate:SetText(data and data.downloaded and ('Leaderboard file from '..data.downloaded) or 'No leaderboard file loaded')
 end
 y=y-24
 note('Adds the runs in the leaderboard file that your current character played in. Runs you already have are skipped.')
 action('Clear history for a character',190,22,function(s)
  local items={}
  for _,entry in ipairs(H:HistoryCharacters()) do
   items[#items+1]={text=entry.key..'  ('..entry.count..' runs)',notCheckable=true,func=function()
    confirm('Delete all '..entry.count..' recorded runs of '..entry.key..'? This cannot be undone.',function()
     H.Message('Deleted '..H:ClearCharacterHistory(entry.key)..' runs of '..entry.key..'.')
    end)
   end}
  end
  if #items==0 then items[1]={text='No recorded runs',notCheckable=true,disabled=true} end
  menu(s,items)
 end)
 action('Delete duplicate runs',150,222,function()
  local removed=H:DeleteDuplicateRuns()
  H.Message(removed>0 and ('Deleted '..removed..' duplicate runs.') or 'No duplicate runs found.')
 end)
 y=y-40
 body:SetHeight(-y+20)

 function panel:Refresh() for _,refresh in ipairs(refreshers) do refresh() end end
 panel.refresh=panel.Refresh
 panel:SetScript('OnShow',function(s) s:Refresh();H:UpdateNotice() end)
 panel:SetScript('OnHide',function() pinPreview(false);previewCheck:SetChecked(false);if H.fontPicker then H.fontPicker:Hide() end end)
 if InterfaceOptions_AddCategory then InterfaceOptions_AddCategory(panel) end
 return panel
end

function H:OpenSettings()
 local panel=self:CreateSettingsPanel()
 if InterfaceOptionsFrame_OpenToCategory then
  -- The first call only expands the AddOns list on some clients; the second selects the page.
  InterfaceOptionsFrame_OpenToCategory(panel);InterfaceOptionsFrame_OpenToCategory(panel)
 end
end
