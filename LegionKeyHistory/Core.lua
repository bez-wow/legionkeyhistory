local H=LegionKeyHistory
local function message(text) print('|cff4adbc8Legion Key History:|r '..text) end
H.Message=message
function H:InitializeDB()
 LegionKeyHistoryDB=LegionKeyHistoryDB or {version=1,runs={}}
 self.db=LegionKeyHistoryDB; self.db.runs=self.db.runs or {}
 self:InitializeProfiles()
 self.accountView=false
 self:RepairHistory()
 self.index={}
 for i,run in ipairs(self.db.runs) do self.index[run.id]=i end
end
local function identityName(n) return H:IdentityKey(n) or '' end
function H:RunInScope(run)
 if self.accountView then return true end
 local guid=UnitGUID('player')
 if run.ownerGUID and run.ownerGUID~='' then return run.ownerGUID==guid end
 local n,realm=UnitName('player');local full=n and (n..'-'..((realm and realm~='') and realm or GetRealmName()))
 if run.owner and run.owner~='' then return identityName(run.owner)==identityName(full) end
 for _,m in ipairs(run.members or {}) do
  if m.guid and m.guid~='' then if m.guid==guid then return true end
  elseif m.name and identityName(m.name)==identityName(full) then return true end
 end
 -- Unidentified historical runs remain available in Account view.
 return false
end
function H:SetAccountView(enabled)
 self.accountView=enabled and true or false
 self.page=1;self.statsPage=1;self.statsDungeonPage=1;self.dayWindow=0;self.dayTablePage=1;self.selected=nil
 for _,b in ipairs(self.scopeButtons or {}) do b:SetText(self.accountView and 'View: Account' or 'View: Character') end
 if self.Refresh then self:Refresh() end
 if self.daysFrame and self.daysFrame:IsShown() then self:RefreshDays() end
end
function H:ResolveTimer(run)
 self:NormalizeRun(run)
 if (not run.timeLimit or run.timeLimit<=0) and C_ChallengeMode then
  local api=C_ChallengeMode.GetMapInfo or C_ChallengeMode.GetMapUIInfo
  if api then
   local ok,name,_,limit=pcall(api,run.mapID)
   if ok and type(limit)=='number' and limit>0 then run.timeLimit=limit end
  end
 end
 if run.status=='completed' and run.duration and run.timeLimit and run.timeLimit>0 and run.timed==nil then
  run.timed=run.duration<=run.timeLimit;run.timingSource='client dungeon time limit'
 end
end
function H:AddRun(run)
 self.localScoreCache=nil
 if type(run)~='table' or not run.id or not run.mapID or not run.level then return false end
 self:ResolveTimer(run)
 local i=self.index[run.id]
 if not i then
  for j,old in ipairs(self.db.runs) do
   local sameFinish=old.duration and run.duration and old.endedAt and run.endedAt
    and math.abs(old.duration-run.duration)<1 and math.abs(old.endedAt-run.endedAt)<15
   local sameStart=old.startedAt and run.startedAt and not old.partial and not run.partial
    and math.abs(old.startedAt-run.startedAt)<5
   if old.mapID==run.mapID and old.level==run.level and (sameFinish or sameStart)
    and (not old.ownerGUID or not run.ownerGUID or old.ownerGUID==run.ownerGUID) then i=j;break end
  end
 end
 if i then
  local old=self.db.runs[i]
  if old.status=='completed' and run.status~='completed' then return false end
  if old.source=='live' and run.source~='live' then return false end
  self.index[old.id]=nil;self.db.runs[i]=run;self.index[run.id]=i
  return false
 end
 self.db.runs[#self.db.runs+1]=run;self.index[run.id]=#self.db.runs
 return true
end
function H:ImportPrepared(silent)
 local added=0
 for _,run in ipairs((LegionKeyHistoryImport or {}).runs or {}) do if self:AddRun(run) then added=added+1 end end
 if not silent then message(added..' new runs imported. Duplicate runs were skipped/updated.') end
 if self.Refresh then self:Refresh() end
 return added
end
local function fullName(unit)
 local name,realm=UnitName(unit)
 return name and (name..'-'..((realm and realm~='') and realm or GetRealmName()))
end
function H:CaptureParty(run)
 local members={}
 for _,v in ipairs(run.members or {}) do members[v.guid]=v end
 for _,unit in ipairs({'player','party1','party2','party3','party4'}) do
  local guid=UnitGUID(unit)
  if guid then
   local _,class=UnitClass(unit)
   members[guid]={guid=guid,name=fullName(unit),class=class,role=UnitGroupRolesAssigned(unit)}
  end
 end
 run.members={};for _,v in pairs(members) do run.members[#run.members+1]=v end
 table.sort(run.members,function(a,b) return a.name<b.name end)
end
function H:BeginRun(partial,attempt)
 local mapID=self:NormalizeMap(C_ChallengeMode.GetActiveChallengeMapID())
 local level,affixes=C_ChallengeMode.GetActiveKeystoneInfo()
 if not mapID or mapID==0 or not level or level==0 then
  if (attempt or 0)<4 then C_Timer.After(.5,function() H:BeginRun(partial,(attempt or 0)+1) end) end
  return
 end
 if self.db.active then
  local old=self.db.active
  if old.mapID==mapID and old.level==level and (partial or time()-(old.startedAt or 0)<5) then self:CaptureParty(old);return end
  old.status='incomplete';self:AddRun(old);self.db.active=nil
 end
 local api=C_ChallengeMode.GetMapInfo or C_ChallengeMode.GetMapUIInfo
 local name,_,limit=api(mapID)
 local now=time()
 local run={id='live:'..UnitGUID('player')..':'..now,mapID=mapID,dungeon=name or ('Dungeon '..mapID),level=level,affixes=affixes or {},startedAt=now,date=date('%Y-%m-%d %H:%M:%S',now),source='live',status='incomplete',timeLimit=limit,owner=fullName('player'),ownerGUID=UnitGUID('player'),partial=partial,rosterSource='live party roster'}
 self:CaptureParty(run); self.db.active=run
end
function H:CompleteRun(attempt)
 local mapID,level,ms,timed,upgrades=C_ChallengeMode.GetCompletionInfo()
 if mapID==1651 and self.db.active and (self.db.active.mapID==227 or self.db.active.mapID==234) then mapID=self.db.active.mapID end
 mapID=self:NormalizeMap(mapID)
 if not mapID or mapID==0 or not ms or ms<=0 then
  if (attempt or 0)<4 then C_Timer.After(0.5,function() H:CompleteRun((attempt or 0)+1) end) end
  return
 end
 local run=self.db.active
 if not run or run.mapID~=mapID then
  local api=C_ChallengeMode.GetMapInfo or C_ChallengeMode.GetMapUIInfo
  local name=api(mapID)
  run={id='live:'..UnitGUID('player')..':'..time(),mapID=mapID,level=level,dungeon=name or ('Dungeon '..mapID),affixes={},source='live',owner=fullName('player'),ownerGUID=UnitGUID('player'),partial=true,rosterSource='live completion roster'}
 end
 run.endedAt=time();run.duration=ms/1000;run.level=level or run.level;run.status='completed';run.timed=timed;run.upgrades=upgrades
 run.date=run.date or date('%Y-%m-%d %H:%M:%S',run.endedAt)
 local oldScore=self.PersonalScore and self:PersonalScore()
 self:CaptureParty(run);self:AddRun(run);self.db.active=nil
 if oldScore then
  local total=self:PersonalScore();local gain=math.floor((total-oldScore)*10+.5)/10
  if gain>0 then message(string.format('+%.1f IO -> %.1f total (unofficial)',gain,total)) end
 end
 message(run.dungeon..' +'..run.level..' saved ('..self:Clock(run.duration)..').')
 if self.Refresh then self:Refresh() end
 if FriendsFrame_Update then FriendsFrame_Update() end
end
function H:HasAffix(run,id)
 for _,v in ipairs(run.affixes or {}) do if v==id then return true end end
 return false
end
function H:BestRuns(mode,affix)
 local best={};local guid=UnitGUID('player')
 for _,run in ipairs(self.db.runs) do
  self:ResolveTimer(run)
  if run.status=='completed' and (mode=='completed' or run.timed==true)
   and (not affix or self:HasAffix(run,affix)) and self:RunInScope(run) then
   local old=best[run.mapID]
   local rank=run.timed==true and 2 or run.timed==false and 1 or 0
   local oldRank=old and (old.timed==true and 2 or old.timed==false and 1 or 0) or 0
   if not old or run.level>old.level or (run.level==old.level and
    (rank>oldRank or (rank==oldRank and (run.duration or math.huge)<(old.duration or math.huge)))) then best[run.mapID]=run end
  end
 end
 return best
end
local events=CreateFrame('Frame')
for _,event in ipairs({'ADDON_LOADED','PLAYER_LOGIN','PLAYER_ENTERING_WORLD','CHALLENGE_MODE_START','CHALLENGE_MODE_COMPLETED','CHALLENGE_MODE_RESET','GROUP_ROSTER_UPDATE','CHALLENGE_MODE_MAPS_UPDATE','PLAYER_SPECIALIZATION_CHANGED'}) do events:RegisterEvent(event) end
events:SetScript('OnEvent',function(_,event,arg)
 if event=='ADDON_LOADED' and arg=='LegionKeyHistory' then H:InitializeDB()
 elseif not H.db then return
 elseif event=='PLAYER_LOGIN' then H:InitializeProfiles();H:CreateUI();H:CreateSettingsPanel();C_Timer.After(8,function() H:CheckAddonVersion() end); if C_ChallengeMode.RequestMapInfo then C_ChallengeMode.RequestMapInfo() end
 elseif event=='CHALLENGE_MODE_START' then C_Timer.After(0.5,function() H:BeginRun(false) end)
 elseif event=='PLAYER_ENTERING_WORLD' then C_Timer.After(2,function() if C_ChallengeMode.IsChallengeModeActive() then H:BeginRun(true) end end)
 elseif event=='CHALLENGE_MODE_COMPLETED' then H:CompleteRun(0)
 elseif event=='CHALLENGE_MODE_RESET' and H.db.active then
  local run=H.db.active;run.status='abandoned';run.endedAt=time();H:AddRun(run);H.db.active=nil;if H.Refresh then H:Refresh() end
 elseif event=='GROUP_ROSTER_UPDATE' and H.db.active then H:CaptureParty(H.db.active)
 elseif event=='PLAYER_SPECIALIZATION_CHANGED' and arg=='player' and H.RefreshHUD then H:RefreshHUD()
 elseif event=='CHALLENGE_MODE_MAPS_UPDATE' and H.Refresh then H:Refresh() end
end)
SLASH_LEGIONKEYHISTORY1='/lkh'
SlashCmdList.LEGIONKEYHISTORY=function(msg)
 msg=(msg or ''):lower()
 if not H.frame then H:CreateUI() end
 if msg=='hud' then H.settings.hud=not H.settings.hud;H:RefreshHUD()
 elseif msg=='leaderboard' or msg=='lb' then H:OpenLeaderboard()
 elseif msg=='debug' or msg=='syncdebug' then H:OpenSyncDebug()
 elseif msg=='sync' then H:OpenSync()
 elseif msg=='later' then H.settings.showLaterDungeons=not H.settings.showLaterDungeons;H:Refresh()
 elseif msg=='import' then H:ImportSnapshot()
 elseif msg=='config' or msg=='settings' or msg=='options' then H:OpenSettings()
 else H.frame:SetShown(not H.frame:IsShown());H:Refresh() end
end
