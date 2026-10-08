local H=LegionKeyHistory
-- Lowercase A-Z only, exactly like update_leaderboard.py, so name keys never depend on the
-- client's locale (a locale-aware lower() can rewrite the bytes of accented letters).
local function lowerASCII(s) return (s:gsub('[A-Z]',string.lower)) end
-- Pixels the applicant Role column gives to Name (role icons shrink from 18px to 14px).
local ROLE_TRIM=18
-- Leaderboard-file roles and class ids as recorded runs store them.
local FILE_ROLES={tank='TANK',healer='HEALER',dps='DAMAGER'}
local classes={'WARRIOR','PALADIN','HUNTER','ROGUE','PRIEST','DEATHKNIGHT','SHAMAN','MAGE','WARLOCK','MONK','DRUID','DEMONHUNTER'}
local dungeonIDs={[197]='eoa',[198]='dht',[199]='brh',[200]='hov',[206]='nl',[207]='votw',[208]='mos',[209]='arc',[210]='cos'}
function H:SameSnapshotRun(a,b)
 if a.id==b.id then return true end
 if a.status~='completed' or a.mapID~=b.mapID or a.level~=b.level then return false end
 if not a.duration or math.abs(a.duration-b.duration)>2 or not a.endedAt or math.abs(a.endedAt-b.endedAt)>120 then return false end
 local names={};for _,m in ipairs(a.members or {}) do local key=self:ScoreKey(m.name);if key then names[key]=true end end
 local matched=0;for _,m in ipairs(b.members or {}) do if names[self:ScoreKey(m.name)] then matched=matched+1 end end
 return matched>=3
end
-- rows (optional): only runs with one of these leaderboard rows in the group. Rosters are the
-- only "row:spec" pairs on a line, so a plain search skips other runs without parsing them.
function H:SnapshotRuns(data,rows)
 return coroutine.wrap(function()
  if data.historyText then
   for line in data.historyText:gmatch('[^\n]+') do
    local wanted=not rows
    for _,row in ipairs(rows or {}) do if line:find('[|,]'..row..':') then wanted=true;break end end
    local map,level,ms,stamp,score,aff,party
    if wanted then map,level,ms,stamp,score,aff,party=line:match('^(%d+)|(%d+)|(%d+)|(%d+)|([%d.]+)|([^|]*)|([^|]*)$') end
    if wanted and not map then map,level,ms,stamp,aff,party=line:match('^(%d+)|(%d+)|(%d+)|(%d+)|([^|]*)|([^|]*)$') end
    if map then
     local roster,affixes={},{}
     if data.names then for row,spec in party:gmatch('(%d+):?(%d*)') do roster[#roster+1]={tonumber(row),tonumber(spec)} end
     else for p,s in party:gmatch('(%d+):(%d+)') do roster[#roster+1]={tonumber(p)+1} end end
     for a in aff:gmatch('%d+') do affixes[#affixes+1]=tonumber(a) end
     coroutine.yield(data.historyMaps[tonumber(map)],{tonumber(level),tonumber(ms),tonumber(stamp),tonumber(score or 0),affixes,roster})
    end
   end
  else
   for _,d in ipairs(data.history or {}) do for _,r in ipairs(d.runs) do
    local roster={};for i,pair in ipairs(r[6]) do roster[i]={pair[1]+1} end
    coroutine.yield(d,{r[1],r[2],r[3],r[4],r[5],roster})
   end end
  end
 end)
end
function H:ImportSnapshot(silent)
 local data=LegionKeyHistoryLeaderboard or {}
 if not (data.historyText or data.history) or not (data.historyPlayers or data.names) then
  if not silent then self.Message('No run history in this file. Run LKH Updater.cmd, then /reload.') end
  return 0,0
 end
 local name,realm=UnitName('player');realm=realm and realm~='' and realm or GetRealmName()
 local me=self:ScoreKey(name,realm);local added,skipped=0,0
 -- This character's leaderboard row(s), so only their own runs are read.
 local rows
 if data.names and data.historyText then
  rows={};local lower=lowerASCII(name)
  for i,key in ipairs(data.names) do
   if key==lower and self:ScoreKey(self:LeaderboardFullName(i,data))==me then rows[#rows+1]=i end
  end
 end
 for d,r in self:SnapshotRuns(data,rows) do
  local mine=false;local members={};local identities={}
  for _,pair in ipairs(r[6]) do
   local full=self:LeaderboardFullName(pair[1],data)
   local spec=data.specs and pair[2] and data.specs[pair[2]]
   if full then local key=self:ScoreKey(full)
    if key==me then mine=true end
    members[#members+1]={name=full,role=spec and FILE_ROLES[spec.role],class=data.classes and classes[data.classes[pair[1]]]};identities[#identities+1]=key
   end
  end
  if mine then
   table.sort(identities)
   local run={id='tauri:'..d.mapID..':'..r[1]..':'..r[3]..':'..r[2]..':'..table.concat(identities,','),mapID=d.mapID,dungeon=d.name,level=r[1],duration=r[2]/1000,endedAt=r[3],timeLimit=d.timer,affixes=r[5],members=members,status='completed',source='Tauri file',owner=name..'-'..realm,ownerGUID=UnitGUID('player'),date=date('%Y-%m-%d %H:%M:%S',r[3])}
   local duplicate=false
   for _,old in ipairs(self.db.runs) do if self:SameSnapshotRun(old,run) then duplicate=true;break end end
   if duplicate then skipped=skipped+1 else
    self:ResolveTimer(run);self.db.runs[#self.db.runs+1]=run;self.index[run.id]=#self.db.runs;self.localScoreCache=nil;added=added+1
   end
  end
 end
 if not silent then self.Message(string.format('%s: imported %d missing runs; skipped %d existing runs. File coverage only.',name,added,skipped)) end
 if added>0 and self.Refresh then self:Refresh() end
 return added,skipped
end
-- After login: add this character's runs from the leaderboard file to the journal and Personal
-- Bests, once per downloaded file, so they never lag behind the scores in tooltips.
function H:AutoImportSnapshot()
 local stamp=LegionKeyHistoryLeaderboard and LegionKeyHistoryLeaderboard.downloaded
 if not stamp or not self.db then return end
 local name,realm=UnitName('player');local key=self:ScoreKey(name,(realm and realm~='') and realm or GetRealmName())
 self.db.importStamps=self.db.importStamps or {}
 if self.db.importStamps[key]==stamp then return end
 local added=self:ImportSnapshot(true)
 self.db.importStamps[key]=stamp
 if added and added>0 then self.Message(string.format('Added %d of your runs from the leaderboard file.',added)) end
end
-- UnitName() gives an empty realm for characters on your own realm; IdentityKey treats it
-- like none. Realm spellings ("[HU] Tauri WoW Server", "Tauri") share one key.
function H:ScoreKey(name,realm)
 return self:IdentityKey(name,realm)
end
-- LeaderboardData.lua keeps one compact row per player (see pack() in update_leaderboard.py).
-- A player's full record is built only when a tooltip or leaderboard row needs it, and the
-- weak cache lets unused records be collected again.
local function realmKey(realm) return H:RealmKey(realm) end
local function decodeBest(text,dungeons)
 local best,slot={},0
 for field in (text..';'):gmatch('([^;]*);') do
  slot=slot+1
  local d=dungeons[slot]
  if d and field~='' then
   local score,level,duration,stamp=field:match('^([^,]+),([^,]+),([^,]+),([^,]+)$')
   best[d.id]={tonumber(score),tonumber(level),tonumber(duration),tonumber(stamp)}
  end
 end
 return best
end
function H:LeaderboardFullName(row,data)
 data=data or LegionKeyHistoryLeaderboard or {}
 if data.names then
  local key=data.names[row];if not key then return nil end
  local display=data.info[row]:match('^([^|]*)|')
  if display=='' then display=key:gsub('^[a-z]',string.upper) end
  return display..'-'..data.realmNames[data.realms[row]]
 end
 local p=data.historyPlayers and data.historyPlayers[row]
 return p and (p[1]..'-'..p[2])
end
function H:LeaderboardPlayer(row)
 local data=LegionKeyHistoryLeaderboard
 if not row or not data or not data.info or not data.info[row] then return nil end
 local cache=data.decoded
 if not cache then cache=setmetatable({},{__mode='v'});data.decoded=cache end
 local p=cache[row];if p then return p end
 -- Version 10 adds the Fortified/Tyrannical field before the specs; version 9 files lack it.
 local display,classRank,roles,best,week,specs=data.info[row]:match('^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$')
 if not display then display,classRank,roles,best,specs=data.info[row]:match('^([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$') end
 local key=data.names[row]
 p={name=display~='' and display or (key:gsub('^[a-z]',string.upper)),realm=data.realmNames[data.realms[row]],class=data.classes[row],
  score=data.scores[row],rank=row,classRank=tonumber(classRank),roles={},specs={},best=decodeBest(best,data.dungeons or {})}
 for role,score,rank in roles:gmatch('(%a+)=([%d.]+):(%d+)') do p.roles[role]={score=tonumber(score),rank=tonumber(rank)} end
 -- Best Fortified / Tyrannical key level per dungeon; negative means that run was over time.
 p.weekBest={}
 local slot=0
 for field in ((week or '')..';'):gmatch('([^;]*);') do
  slot=slot+1
  local d=data.dungeons and data.dungeons[slot]
  local fort,tyr=field:match('^(%-?%d*),(%-?%d*)$')
  if d and (fort~='' or tyr~='') and fort then p.weekBest[d.id]={fort=tonumber(fort),tyr=tonumber(tyr)} end
 end
 for spec,score,rank,packed in specs:gmatch('#([^=#]+)=([%d.]+):(%d+):([^#]*)') do
  p.specs[spec]={score=tonumber(score),rank=tonumber(rank),best=packed=='*' and p.best or decodeBest(packed,data.dungeons or {})}
 end
 cache[row]=p
 return p
end
-- Lowercase name -> row (or a list of rows when the name exists on several realms). The keys
-- are the names array's own strings, so the index adds no string copies.
function H:LeaderboardRow(key)
 local data=LegionKeyHistoryLeaderboard
 if not key or not data or not data.names then return nil end
 if self.scoreIndexData~=data then self.scoreIndex=nil end
 if not self.scoreIndex then
  local index={};self.scoreIndexData=data
  for row,name in ipairs(data.names) do
   local old=index[name]
   if old==nil then index[name]=row elseif type(old)=='number' then index[name]={old,row} else old[#old+1]=row end
  end
  self.scoreIndex=index
 end
 local name,realm=key:match('^(.-)%-([^%-]*)$')
 local hit=name and self.scoreIndex[name]
 if not hit then return nil end
 for _,row in ipairs(type(hit)=='table' and hit or {hit}) do
  if realmKey(data.realmNames[data.realms[row]])==realm then return row end
 end
end
function H:PlayerScore(name,realm)
 local key=self:ScoreKey(name,realm)
 if not key then return nil end
 self:LocalScores()
 return self.localScoreCache[key] or self:LeaderboardPlayer(self:LeaderboardRow(key))
end
-- Snapshot score of a leaderboard row, or its locally improved score.
function H:EffectiveScore(row)
 local p=self.localRows and self.localRows[row]
 return p and p.score or LegionKeyHistoryLeaderboard.scores[row]
end
-- Overall rank counting locally recorded runs: players whose local runs beat their snapshot
-- score move up, and everyone they pass moves down one. Ties keep snapshot order.
function H:EffectiveRank(row)
 local data=LegionKeyHistoryLeaderboard
 if not row or not data or not data.scores then return nil end
 self:LocalScores()
 if not next(self.localRows) then return row end
 local score,ahead=self:EffectiveScore(row),0
 for other=1,#data.scores do
  if other~=row then
   local s=self:EffectiveScore(other)
   if s>score or (s==score and other<row) then ahead=ahead+1 end
  end
 end
 return ahead+1
end
-- Rank to show for a PlayerScore record; nil for characters only seen in local runs.
function H:PlayerRank(p)
 return p and self:EffectiveRank(p.row or (not p.localUpdated and p.rank) or nil)
end
-- Characters whose locally recorded runs beat the snapshot, by score key (localScoreCache) and,
-- for snapshot characters, by leaderboard row (localRows).
function H:LocalScores()
 if not self.localScoreCache then
  self.localScoreCache={}
  for _,run in ipairs(self.db and self.db.runs or {}) do
   local score=self:RunScore(run)
   if score then for _,m in ipairs(run.members or {}) do
    local key=self:ScoreKey(m.name)
    if key then
     local p=self.localScoreCache[key] or self:LeaderboardPlayer(self:LeaderboardRow(key));local id=dungeonIDs[run.mapID]
     if not p or not p.best[id] or score>p.best[id][1] then
      if not p or not p.localUpdated then
       local copy={best={},localUpdated=true,partial=not p,name=m.name}
       if p then for k,v in pairs(p) do if k~='best' then copy[k]=v end end;for k,v in pairs(p.best) do copy.best[k]=v end end
       copy.localUpdated=true;copy.tooltipRows=nil;p=copy;self.localScoreCache[key]=p
      end
      p.best[id]={score,run.level,run.duration,run.endedAt or 0}
     end
    end
   end end
  end
  self.localRows={}
  for _,p in pairs(self.localScoreCache) do if p.localUpdated then
   local total=0;for _,v in pairs(p.best) do total=total+v[1] end;p.score=math.floor(total*10+.5)/10
   if not p.partial and p.rank then p.row=p.rank;self.localRows[p.row]=p end
  end end
 end
 return self.localScoreCache
end

function H:RunScore(run)
 if not run or not dungeonIDs[run.mapID] or run.status~='completed' then return nil end
 self:ResolveTimer(run)
 local limit=run.timeLimit;local duration=run.duration;local level=run.level
 if not limit or limit<=0 or not duration or duration<=0 or not level then return nil end
 local ratio=duration/limit
 local score=ratio<=1 and (50+7.5*level+12.5*(1-ratio)) or (50+7.5*(level-1)-20*(ratio-1))
 return math.floor(math.max(0,score)*10+.5)/10
end
function H:PersonalScore()
 local name=UnitName('player');local key=self:ScoreKey(name);local p=self:PlayerScore(name);local best={}
 if p then for id,b in pairs(p.best) do best[id]=b[1] end end
 for _,r in ipairs(self.db and self.db.runs or {}) do
  local yours=false
  for _,m in ipairs(r.members or {}) do if self:ScoreKey(m.name)==key then yours=true;break end end
  if yours then local score=self:RunScore(r);local id=dungeonIDs[r.mapID];if score and score>(best[id] or 0) then best[id]=score end end
 end
 local total=0;for _,score in pairs(best) do total=total+score end
 return total,best
end
-- Legion dungeons drop "(Mythic Keystone)" and "(Mythic)": "Darkheart Thicket (Mythic)" ->
-- "Darkheart Thicket". Older dungeons keep theirs ("Lost City of the Tol'vir (Heroic)").
local LEGION_DUNGEONS={'Assault on Violet Hold','Return to Karazhan','Cathedral of Eternal Night','Seat of the Triumvirate'}
local function isLegionDungeon(name)
 name=name:lower()
 for _,d in ipairs((LegionKeyHistoryLeaderboard or {}).dungeons or {}) do if name:find(d.name:lower(),1,true)==1 then return true end end
 for _,d in ipairs(LEGION_DUNGEONS) do if name:find(d:lower(),1,true)==1 then return true end end
 return false
end
function H:CleanActivityName(name)
 name=tostring(name or '')
 local base=name:match('^(.-)%s*%(Mythic Keystone%)%s*$') or name:match('^(.-)%s*%(Mythic%)%s*$')
 if base and isLegionDungeon(base) then return base end
 return name
end
-- Writes a group finder search row (also the preview in settings) in the chosen style:
--   leaderTop   "M7 VOTW - Leader 1008" over the dungeon name
--   dungeonTop  "M7 VOTW - Vault of the Wardens" (or the short name when that does not fit)
--               over "Leader 1008"
--   plain       the group title over the dungeon name
-- faded: delisted or finished rows, kept in Blizzard's grey. score: fixed score for previews.
function H:FormatSearchRow(nameText,activityText,title,activityName,short,leader,width,faded,score)
 title=tostring(title or '');local dungeon=self:CleanActivityName(activityName)
 local style=self.settings.searchStyle
 local leaderText
 if leader and style~='plain' then
  if not score then local p=self:PlayerScore(leader);score=p and p.score end
  local _,_,_,hex=self:ScoreColor(score)
  leaderText=faded and (leader..' '..self:FormatScore(score)) or ('|cffffffff'..leader..'|r '..hex..self:FormatScore(score)..'|r')
 end
 local sep=faded and ' - ' or '|cff666666 - |r'
 -- One line only: a wrapped top line would run into the dungeon line below it.
 if nameText.SetWordWrap then nameText:SetWordWrap(false) end
 local function fits(text) nameText:SetWidth(0);nameText:SetText(text);return (nameText:GetStringWidth() or 0)<=width end
 -- Group title plus an extra part; when it does not fit, the title is shortened so the extra
 -- part (leader and score, or dungeon) stays readable.
 local function fitTitle(extra)
  if fits(title..sep..extra) then return true end
  for n=#title-1,1,-1 do
   if fits(title:sub(1,n)..'...'..sep..extra) then return true end
  end
  return false
 end
 local second=dungeon
 if style=='dungeonTop' and dungeon~='' then
  local full=faded and dungeon or ('|cffa8a8a8'..dungeon..'|r')
  if not fits(title..sep..full) and short then fitTitle(faded and short or ('|cffa8a8a8'..short..'|r')) end
  second=leaderText or ''
 elseif style=='leaderTop' and leaderText then
  fitTitle(leaderText)
 else
  fits(title)
 end
 -- Anything still too long ends in "..." instead of running under the role icons.
 if (nameText:GetStringWidth() or 0)>width then nameText:SetWidth(width) end
 activityText:SetText(second)
end
function H:TooltipDungeon(activityID)
 if not activityID or not C_LFGList.GetActivityInfo then return end
 local activity=C_LFGList.GetActivityInfo(activityID)
 if type(activity)~='string' then return end
 for _,d in ipairs((LegionKeyHistoryLeaderboard or {}).dungeons or {}) do if activity:lower():find(d.name:lower(),1,true) then return d.id end end
end
-- A best run that went over the dungeon's timer (j-th dungeon of the file): shown in grey.
function H:OverTime(j,b)
 local timer=self:DungeonTimer(j)
 return b~=nil and timer~=nil and timer>0 and b[3]>timer
end
local function grey(text,on) return on and ('|cff7a7a7a'..text..'|r') or text end
function H:PrepareScoreTooltip(p)
 if not p or p.tooltipRows then return end
 self.tooltipCacheQueue=self.tooltipCacheQueue or {}
 local queue=self.tooltipCacheQueue
 queue[#queue+1]=p
 if #queue>128 then local old=table.remove(queue,1);old.tooltipRows=nil end
 p.tooltipRows={}
 for j,d in ipairs((LegionKeyHistoryLeaderboard or {}).dungeons or {}) do
  local b=p.best[d.id]
  p.tooltipRows[d.id]=b and grey(string.format('+%d  %s  |  %.1f IO',b[2],self:Clock(b[3]),b[1]),self:OverTime(j,b)) or '-'
 end
end
-- Tooltip rows whose right side is split into columns (key, time, score) that line up from row
-- to row. The game draws the right text right-aligned in a proportional font, so a "+8" or a
-- narrow "1" shifts everything; each part gets its own right-aligned font string instead, and the
-- real right text keeps the width (invisible) so the tooltip sizes itself as before.
local measure
local function measureWidth(text)
 measure:SetText(text);return measure:GetStringWidth()
end
local function clearColumns(tooltip)
 for _,right in ipairs(tooltip.lkhAligned or {}) do right:SetAlpha(1) end
 for _,cols in pairs(tooltip.lkhCols or {}) do for _,fs in ipairs(cols) do fs:Hide() end end
 tooltip.lkhAligned={}
end
local function alignColumns(tooltip,rows)
 local name=tooltip.GetName and tooltip:GetName()
 if not name or #rows==0 or not _G[name..'TextRight'..rows[1].line] then return end
 if not tooltip.lkhAlignHook then
  tooltip.lkhAlignHook=true;tooltip:HookScript('OnTooltipCleared',clearColumns)
 end
 local font,size,flags=_G[name..'TextRight'..rows[1].line]:GetFont()
 measure=measure or UIParent:CreateFontString(nil,'BACKGROUND');measure:SetFont(font,size,flags)
 local gap=measureWidth('x  x')-measureWidth('xx')
 local widths,widest={},{}
 for _,row in ipairs(rows) do
  for c,part in ipairs(row.parts) do
   local w=measureWidth(part)
   if w>(widths[c] or -1) then widths[c],widest[c]=w,part end
  end
 end
 local placeholder=table.concat(widest,'  ')
 tooltip.lkhCols=tooltip.lkhCols or {};tooltip.lkhAligned=tooltip.lkhAligned or {}
 for _,row in ipairs(rows) do
  local right=_G[name..'TextRight'..row.line]
  right:SetText(placeholder);right:SetAlpha(0);tooltip.lkhAligned[#tooltip.lkhAligned+1]=right
  local cols=tooltip.lkhCols[row.line] or {};tooltip.lkhCols[row.line]=cols
  local x=0
  for c=#row.parts,1,-1 do
   local fs=cols[c]
   if not fs then fs=tooltip:CreateFontString(nil,'ARTWORK');fs:SetJustifyH('RIGHT');cols[c]=fs end
   fs:SetFont(font,size,flags);fs:SetTextColor(1,1,1);fs:ClearAllPoints();fs:SetPoint('RIGHT',right,'RIGHT',-x,0)
   fs:SetText(row.parts[c]);fs:Show()
   x=x+widths[c]+gap
  end
 end
end
function H:AddScoreTooltip(tooltip,name,realm,selected)
 if not name then return end
 local aligned={}
 local p=self:PlayerScore(name,realm)
 self:PrepareScoreTooltip(p)
 tooltip:AddLine(' ')
 tooltip:AddLine('LKH Mythic+ Score',.29,.86,.78)
 if not p then tooltip:AddLine('Not in the downloaded snapshot.',.7,.7,.7);tooltip:Show();return end
 local sr,sg,sb=1,.82,0
 if self.settings.scoreColorMode~='custom' then sr,sg,sb=self:ScoreColor(p.score) end
 tooltip:AddDoubleLine('Current score',string.format('%.1f',p.score),1,1,1,sr,sg,sb)
 -- Overall rank in the snapshot (players only seen in local runs have none).
 local showRanks=self.settings.tipRanks
 local rank=showRanks and self:PlayerRank(p)
 if rank then tooltip:AddDoubleLine('Current rank','#'..rank,1,1,1,1,.82,0) end
 local currentSpec
 if UnitExists and UnitExists('target') and self:ScoreKey(UnitName('target'),select(2,UnitName('target')))==self:ScoreKey(name,realm) then
  local id=GetInspectSpecialization and GetInspectSpecialization('target')
  if id and id>0 and GetSpecializationInfoByID then currentSpec=select(2,GetSpecializationInfoByID(id)) end
 end
 local ranks={}
 for spec,entry in pairs(showRanks and p.specs or {}) do
  if entry.rank and (not currentSpec or spec==currentSpec) then ranks[#ranks+1]={name=spec,rank=entry.rank} end
 end
 table.sort(ranks,function(a,b) return a.name<b.name end)
 if #ranks>0 then tooltip:AddLine(' ') end
 for _,entry in ipairs(ranks) do
  tooltip:AddDoubleLine('Spec rank',entry.name..' #'..entry.rank,.8,.85,.9,.29,.86,.78)
 end
 if showRanks and p.classRank then
  local tokens={'WARRIOR','PALADIN','HUNTER','ROGUE','PRIEST','DEATHKNIGHT','SHAMAN','MAGE','WARLOCK','MONK','DRUID','DEMONHUNTER'}
  local names={'Warrior','Paladin','Hunter','Rogue','Priest','Death Knight','Shaman','Mage','Warlock','Monk','Druid','Demon Hunter'}
  local c=RAID_CLASS_COLORS and RAID_CLASS_COLORS[tokens[p.class]]
  tooltip:AddDoubleLine('Class rank', (names[p.class] or 'Class')..' #'..p.classRank,.8,.85,.9,c and c.r or 1,c and c.g or 1,c and c.b or 1)
 end
 if #ranks>0 or (showRanks and p.classRank) then tooltip:AddLine(' ') end

 local bestID,best
 for id,b in pairs(p.best) do if not best or b[1]>best[1] then bestID,best=id,b end end
 for _,d in ipairs(self.settings.tipBestRun and (LegionKeyHistoryLeaderboard or {}).dungeons or {}) do
  -- In the group finder (selected = the listed dungeon) the best run turns green when it is in
  -- that dungeon; otherwise "Best for dungeon" adds the player's key there.
  if d.id==bestID then
   if bestID==selected then tooltip:AddDoubleLine('Best run',d.short..' +'..best[2],.3,1,.5,.3,1,.5)
   else tooltip:AddDoubleLine('Best run',d.short..' +'..best[2],.8,.85,.9,1,1,1) end
  end
  if d.id==selected and bestID~=selected then local b=p.best[d.id];tooltip:AddDoubleLine('Best for dungeon',d.short..(b and (' +'..b[2]) or ' --'),.3,1,.5,.3,1,.5) end
 end
 local dungeons=(LegionKeyHistoryLeaderboard or {}).dungeons or {}
 if self.settings.tipDungeons then
  tooltip:AddLine(' ')
  for j,d in ipairs(dungeons) do
   local b=p.best[d.id];local late=self:OverTime(j,b);local l=late and .48 or .8
   tooltip:AddDoubleLine((d.id==selected and '|cff4dff80> ' or '')..d.short..(d.id==selected and '|r' or ''),p.tooltipRows[d.id],l,late and .48 or .85,late and .48 or .9,1,1,1)
   if b then aligned[#aligned+1]={line=tooltip:NumLines(),parts={grey('+'..b[2],late),grey(self:Clock(b[3]),late),late and '|cff7a7a7a|||r' or '|',grey(string.format('%.1f IO',b[1]),late)}} end
  end
 end
 -- Best Fortified / Tyrannical key per dungeon; grey when that run was over time.
 if self.settings.tipWeekSplit and p.weekBest and next(p.weekBest) then
  local function level(value) if not value then return '|cff666666--|r' end;return value>0 and ('+'..value) or ('|cff888888+'..(-value)..'|r') end
  tooltip:AddLine(' ');tooltip:AddDoubleLine('Fortified / Tyrannical',' ',.29,.86,.78,1,1,1)
  for _,d in ipairs(dungeons) do
   local w=p.weekBest[d.id]
   if w then
    tooltip:AddDoubleLine(d.short,level(w.fort)..'  /  '..level(w.tyr),.8,.85,.9,1,1,1)
    aligned[#aligned+1]={line=tooltip:NumLines(),parts={level(w.fort),'/',level(w.tyr)}}
   end
  end
 end
 if p.localUpdated then tooltip:AddLine('Includes locally recorded party runs.',.29,.86,.78) end
 if p.partial then tooltip:AddLine('Partial history: player absent from snapshot.',1,.8,.4) end
 alignColumns(tooltip,aligned)
 tooltip:Show()
end
local function scoreLabel(row,name,realm,anchor,x,y)
 if not row.lkhScore then
  row.lkhScore=row:CreateFontString(nil,'OVERLAY','GameFontNormalSmall');row.lkhScore:SetFont(H:FontPath(),11,'')
 end
 row.lkhScore:ClearAllPoints();row.lkhScore:SetPoint('TOPRIGHT',anchor or row,'TOPRIGHT',x or -8,y or -5)
 local p=name and H:PlayerScore(name,realm);H:PrepareScoreTooltip(p);row.lkhPlayerName=name;row.lkhPlayerRealm=realm;row.lkhScore:SetText(name and H:FormatScore(p and p.score) or '')
 row.lkhScore:SetTextColor(H:ScoreColor(p and p.score));row.lkhScore:Show()
end
local function friendName(row)
 if row.buttonType==FRIENDS_BUTTON_TYPE_WOW then local name=GetFriendInfo(row.id);return name end
 if row.buttonType==FRIENDS_BUTTON_TYPE_BNET and BNGetFriendGameAccountInfo then
  for i=1,BNGetNumFriendGameAccounts(row.id) do
   local _,name,client,realm=BNGetFriendGameAccountInfo(row.id,i)
   if client=='WoW' then return name,realm end
  end
 end
end
function H:InstallScoreHooks()
 self.scoreHooks=self.scoreHooks or {}
 -- Blizzard covers the applicant list for group members who are not the leader, which also
 -- blocks the mouse; let the mouse through so everyone can hover applicants.
 local cover=LFGListFrame and LFGListFrame.ApplicationViewer and LFGListFrame.ApplicationViewer.UnempoweredCover
 if cover and not self.scoreHooks.unempoweredCover then
  self.scoreHooks.unempoweredCover=true
  cover:EnableMouse(false);if cover.EnableMouseWheel then cover:EnableMouseWheel(false) end
 end
 -- Player tooltip (mouseover in the world, nameplates, raid frames): keep the game's lines and
 -- add the LKH score below them.
 if GameTooltip and GameTooltip.HookScript and not self.scoreHooks.unitTooltip then
  self.scoreHooks.unitTooltip=true
  GameTooltip:HookScript('OnTooltipSetUnit',function(tooltip)
   if not H.settings.hoverUnit or not H:HoverModifierHeld() then return end
   local _,unit=tooltip:GetUnit()
   if unit and UnitIsPlayer(unit) then local name,realm=UnitName(unit);H:AddScoreTooltip(tooltip,name,realm) end
  end)
 end
 local function hook(name,fn) if type(_G[name])=='function' and not self.scoreHooks[name] then hooksecurefunc(name,fn);self.scoreHooks[name]=true end end
 hook('FriendsFrame_UpdateFriendButton',function(row)
  local name,realm=friendName(row)
  if H.settings.scoreFriends then
   scoreLabel(row,name,realm)
   if row.name and name then row.name:SetWidth(math.max(60,row:GetWidth()-110)) end
  elseif row.lkhScore then row.lkhScore:Hide() end
  if not row.lkhHover then
   row.lkhHover=true
   row:HookScript('OnEnter',function(s) if not H.settings.hoverFriends then return end;local n,r=friendName(s);if n then GameTooltip:SetOwner(s,'ANCHOR_RIGHT');GameTooltip:SetText(n);H:AddScoreTooltip(GameTooltip,n,r) end end)
   row:HookScript('OnLeave',function() GameTooltip:Hide() end)
  end
 end)
 hook('LFGListApplicationViewer_UpdateApplicantMember',function(row,appID,memberIdx)
  local name=C_LFGList.GetApplicantMemberInfo(appID,memberIdx)
  row.lkhPlayerName=name
  local _,activity=C_LFGList.GetActiveEntryInfo();row.lkhActivity=activity
  -- The row's OnEnter is bound to Blizzard's function when the frame is created, so hooking the
  -- global function does nothing; hook the row's own script instead.
  if not row.lkhHover then
   row.lkhHover=true
   row:HookScript('OnEnter',function(s)
    if not H.settings.hoverApplicants or not GameTooltip:IsOwned(s) then return end
    -- Beside the list, like the search results tooltip, instead of over the applicants.
    local applicant=s:GetParent()
    if applicant then GameTooltip:ClearAllPoints();GameTooltip:SetPoint('BOTTOMLEFT',applicant,'TOPRIGHT',28,0) end
    local n=s.lkhPlayerName or C_LFGList.GetApplicantMemberInfo(s:GetParent().applicantID,s.memberIdx)
    H:AddScoreTooltip(GameTooltip,n,nil,H:TooltipDungeon(s.lkhActivity));H:OpaqueTooltip(GameTooltip)
   end)
  end
  H:LayoutApplicantColumns()
  if not H.settings.scoreApplicants then
   if row.lkhScore then row.lkhScore:Hide() end
   -- Blizzard's role icons again: 18px from x=104.
   if row.lkhRoles then
    row.lkhRoles=nil
    for i=1,3 do local icon=row['RoleIcon'..i];if icon then icon:SetSize(18,18) end end
    if row.RoleIcon1 then row.RoleIcon1:ClearAllPoints();row.RoleIcon1:SetPoint('LEFT',104,0) end
   end
   return
  end
  -- Keep the 20px row height and leave role controls/item level in place.
  -- The score sits in its own "IO" column, centred and on the same line as the name.
  -- Role icons shrink to 14px so the Role column gives the name ROLE_TRIM more room; three
  -- icons (tank, healer and damage) still fit.
  row.Name:SetWidth(58+ROLE_TRIM)
  row.lkhRoles=true
  for i=1,3 do local icon=row['RoleIcon'..i];if icon then icon:SetSize(14,14) end end
  if row.RoleIcon1 then row.RoleIcon1:ClearAllPoints();row.RoleIcon1:SetPoint('LEFT',104+ROLE_TRIM,0) end
  scoreLabel(row,name,nil,row,0,-5)
  local font,size,flags=row.Name:GetFont()
  if font then row.lkhScore:SetFont(font,size,flags) end
  row.lkhScore:ClearAllPoints();row.lkhScore:SetPoint('CENTER',row,'LEFT',84+ROLE_TRIM,-1);row.lkhScore:SetJustifyH('CENTER')
  local p=name and H:PlayerScore(name);row.lkhScore:SetText(H:FormatScore(p and p.score,true))
  if row.FriendIcon then row.FriendIcon:ClearAllPoints();row.FriendIcon:SetPoint('RIGHT',row,'LEFT',5,0) end
 end)
 hook('LFGListSearchEntry_Update',function(row)
  if not row.Name or not row.ActivityName then return end
  local info={C_LFGList.GetSearchResultInfo(row.resultID)}
  local activityName=C_LFGList.GetActivityInfo and C_LFGList.GetActivityInfo(info[2])
  local dungeonID=H:TooltipDungeon(info[2]);local dungeon
  for _,d in ipairs((LegionKeyHistoryLeaderboard or {}).dungeons or {}) do if d.id==dungeonID then dungeon=d end end
  -- Blizzard sets the dungeon line to the room the row has for text (less beside voice chat).
  H:FormatSearchRow(row.Name,row.ActivityName,info[3],activityName,dungeon and dungeon.short,info[13],row.ActivityName:GetWidth() or 176,info[12])
 end)
 hook('LFGListUtil_SetSearchEntryTooltip',function(tooltip,id)
  if not H.settings.hoverSearch then return end
  local name=select(13,C_LFGList.GetSearchResultInfo(id));local _,activity=C_LFGList.GetSearchResultInfo(id);H:AddScoreTooltip(tooltip,name,nil,H:TooltipDungeon(activity));H:OpaqueTooltip(tooltip)
 end)
end
-- True when the player tooltip may show the score: always, or while the chosen key is held.
-- Group finder tooltips sit over the Personal Bests panel, so they get a solid background.
-- Tooltip skins such as ElvUI make tooltips see-through and set that again whenever one opens;
-- the solid background is put back after them and the skin's own value returns afterwards.
local function applyOpaque(tooltip)
 if not tooltip.lkhOpaque then return end
 local r,g,b,a=tooltip:GetBackdropColor()
 if r and a and a<1 then tooltip.lkhSkinAlpha=tooltip.lkhSkinAlpha or a;tooltip:SetBackdropColor(r,g,b,1) end
end
local function restoreOpaque(tooltip)
 tooltip.lkhOpaque=nil
 if tooltip.lkhSkinAlpha then
  local r,g,b=tooltip:GetBackdropColor()
  if r then tooltip:SetBackdropColor(r,g,b,tooltip.lkhSkinAlpha) end
  tooltip.lkhSkinAlpha=nil
 end
end
function H:OpaqueTooltip(tooltip)
 if not tooltip or not tooltip.GetBackdropColor or not tooltip.HookScript then return end
 if not tooltip.lkhOpaqueHooks then
  tooltip.lkhOpaqueHooks=true
  tooltip:HookScript('OnShow',applyOpaque);tooltip:HookScript('OnUpdate',applyOpaque)
  tooltip:HookScript('OnTooltipCleared',restoreOpaque);tooltip:HookScript('OnHide',restoreOpaque)
 end
 tooltip.lkhOpaque=true;applyOpaque(tooltip)
end
-- Applicant list headers: Name | IO | Role | iLvl. The Name header gives up the room for IO.
-- Done when the list updates, after skins such as ElvUI have placed Blizzard's headers.
function H:LayoutApplicantColumns()
 local viewer=LFGListFrame and LFGListFrame.ApplicationViewer
 if not viewer or not viewer.NameColumnHeader or not viewer.RoleColumnHeader then return end
 local name,role=viewer.NameColumnHeader,viewer.RoleColumnHeader
 local show=self.settings.scoreApplicants
 if not viewer.lkhIOHeader then
  if not show then return end
  local io=CreateFrame('Button',nil,viewer,'LFGListColumnHeaderTemplate');viewer.lkhIOHeader=io
  io:SetText('IO');io:SetSize(34,24);io:EnableMouse(false)
  -- ElvUI restyles Blizzard's headers; give this one the same look.
  local E=ElvUI and ElvUI[1];local S=E and E.GetModule and E:GetModule('Skins',true)
  if S and S.HandleButton then pcall(S.HandleButton,S,io,true);if io.Label and io.Label.FontTemplate then pcall(io.Label.FontTemplate,io.Label) end end
  viewer.lkhNameWidth,viewer.lkhRoleWidth=name:GetWidth(),role:GetWidth()
 end
 local io=viewer.lkhIOHeader
 local _,_,_,gap=role:GetPoint(1);gap=tonumber(gap) or 0
 if show then
  name:SetWidth(viewer.lkhNameWidth-34-gap+ROLE_TRIM);role:SetWidth(viewer.lkhRoleWidth-ROLE_TRIM)
  io:ClearAllPoints();io:SetPoint('LEFT',name,'RIGHT',gap,0);io:Show()
  role:ClearAllPoints();role:SetPoint('LEFT',io,'RIGHT',gap,0)
 else
  io:Hide();name:SetWidth(viewer.lkhNameWidth);role:SetWidth(viewer.lkhRoleWidth)
  role:ClearAllPoints();role:SetPoint('LEFT',name,'RIGHT',gap,0)
 end
end
function H:HoverModifierHeld()
 local key=self.settings.hoverModifier
 if key=='ctrl' then return IsControlKeyDown() elseif key=='alt' then return IsAltKeyDown() elseif key=='shift' then return IsShiftKeyDown() end
 return true
end
local socialEvents=CreateFrame('Frame');socialEvents:RegisterEvent('PLAYER_LOGIN');socialEvents:RegisterEvent('ADDON_LOADED');socialEvents:RegisterEvent('PLAYER_ENTERING_WORLD');socialEvents:RegisterEvent('MODIFIER_STATE_CHANGED')
socialEvents:SetScript('OnEvent',function(_,event)
 if event=='MODIFIER_STATE_CHANGED' then
  -- Pressing or releasing the key redraws the tooltip under the mouse, adding or removing the score.
  if H.settings and H.settings.hoverUnit and H.settings.hoverModifier~='always' and GameTooltip:IsShown() then
   local _,unit=GameTooltip:GetUnit()
   if unit then GameTooltip:SetUnit(unit) end
  end
  return
 end
 H:InstallScoreHooks()
 if event=='PLAYER_LOGIN' then H:PlayerScore(UnitName('player'));C_Timer.After(6,function() H:AutoImportSnapshot() end) end
end)
local labels={'Warrior','Paladin','Hunter','Rogue','Priest','Death Knight','Shaman','Mage','Warlock','Monk','Druid','Demon Hunter'}
local realms={'All realms','Evermoon','Tauri','WoD'}
local PAGE=12
local backdrop={bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1}
local function text(p,size,x,y,w,value)
 local t=p:CreateFontString(nil,'OVERLAY','GameFontNormal');t:SetFont(H:FontPath(),size,'');t:SetPoint('TOPLEFT',x,y);t:SetWidth(w);t:SetJustifyH('LEFT');t:SetTextColor(.85,.9,.93);t:SetText(value or '')
 -- One line per cell: a value that does not fit is cut with "..." instead of spilling into the next row.
 t:SetWordWrap(false);return t
end
local function button(p,label,w,x,y,fn)
 local b=CreateFrame('Button',nil,p,'UIPanelButtonTemplate');b:SetSize(w,23);b:SetPoint('TOPLEFT',x,y);b:SetText(label);b:SetScript('OnClick',fn);return b
end
-- Matches "name realm" like a plain substring search, without building that string per row.
local function searchMatches(name,realm,query)
 if query=='' or name:find(query,1,true) or realm:find(query,1,true) then return true end
 local head,tail=query:match('^(.-) (.*)$')
 return head~=nil and name:sub(-#head)==head and realm:sub(1,#tail)==tail
end
-- Returns leaderboard rows: row numbers, or {row=,score=} entries ranked within one spec.
-- Use LeaderboardEntry to get the record to display.
function H:LeaderboardList(query,realm,classID,specName)
 local data=LegionKeyHistoryLeaderboard or {};local result={};query=lowerASCII(query or '')
 if not data.names then return result end
 local realmLower={};for i,r in ipairs(data.realmNames) do realmLower[i]=lowerASCII(r) end
 local specPattern=specName and ('#'..specName:gsub('%p','%%%0')..'=([%d.]+):')
 for row,name in ipairs(data.names) do
  local realmIndex=data.realms[row]
  if (not realm or realm=='All realms' or data.realmNames[realmIndex]==realm) and (not classID or classID==0 or data.classes[row]==classID)
   and searchMatches(name,realmLower[realmIndex],query) then
   if not specName then result[#result+1]=row
   else
    local score=data.info[row]:match(specPattern)
    if score then result[#result+1]={row=row,score=tonumber(score)} end
   end
  end
 end
 if specName then
  table.sort(result,function(a,b) if a.score~=b.score then return a.score>b.score end;return a.row<b.row end)
 elseif next(self:LocalScores() and self.localRows) then
  -- Locally recorded runs can lift players above their snapshot position.
  table.sort(result,function(a,b)
   local sa,sb=self:EffectiveScore(a),self:EffectiveScore(b)
   if sa~=sb then return sa>sb end;return a<b
  end)
 end
 return result
end
function H:LeaderboardEntry(entry,position,specName)
 if type(entry)=='number' then return self:LocalScores() and self.localRows[entry] or self:LeaderboardPlayer(entry) end
 local p=entry and self:LeaderboardPlayer(entry.row);local spec=p and p.specs[specName]
 if not spec then return nil end
 return {name=p.name,realm=p.realm,class=p.class,score=spec.score,best=spec.best,spec=specName,rank=position}
end
function H:RefreshLeaderboard()
 local f=self.leaderboardFrame;if not f then return end
 if f.help and f.title then f.help:ClearAllPoints();f.help:SetPoint('LEFT',f.title,'LEFT',math.ceil(f.title:GetStringWidth() or 300)+12,0) end
 local data=LegionKeyHistoryLeaderboard or {};local rows
 local runsView=f.view=='runs'
 f.playersButton:SetEnabled(runsView);f.runsButton:SetEnabled(not runsView)
 for _,w in ipairs(f.runWidgets or {}) do w:SetShown(runsView) end
 if runsView then
  for _,w in ipairs(f.listOnly or {}) do w:Hide() end
  for _,w in ipairs({f.specButton,f.compareButton,f.compareShow,f.compareView}) do w:Hide() end
  for _,row in ipairs(f.rows) do row:Hide() end
  f.compareHint:SetText('');for _,w in ipairs({f.footer,f.prev,f.pages,f.next}) do w:Show() end
  return self:RefreshRunBoard(f)
 end
 for _,line in ipairs(f.runLines or {}) do line:Hide() end
 f.compareButton:Show()
 f.footer:SetText('Unofficial score: best per dungeon summed. Click a player to see their runs. Hover for details.')
 f.empty:SetText('No matching players. Try All realms or update the snapshot.')
 if f.compareOnly and f.compareCount>0 then
  -- Only the picked players, best score first.
  rows={};for row in pairs(f.compare) do rows[#rows+1]=row end
  table.sort(rows,function(a,b) local sa,sb=self:EffectiveScore(a),self:EffectiveScore(b);if sa~=sb then return sa>sb end;return a<b end)
 else
  f.compareOnly=false
  rows=self:LeaderboardList(f.search:GetText(),realms[f.realm],f.classID,f.specName)
 end
 f.compareButton:SetText(f.compareMode and 'Stop' or 'Compare')
 f.compareShow:SetShown(f.compareMode and not f.compareOnly);f.compareShow:SetText('Show '..f.compareCount)
 f.compareShow:SetEnabled(f.compareCount>=2)
 f.compareHint:SetText(f.compareMode and not f.compareOnly and ('|cfff7b500Comparing: click up to 5 players to pick them ('..f.compareCount..' picked), then click Show '..f.compareCount..'.|r') or '')
 -- The comparison replaces the table: only Stop stays.
 local listing=not f.compareOnly
 for _,w in ipairs(f.listOnly or {}) do w:SetShown(listing) end
 -- Best run per dungeon among the compared players, by run score.
 local bestOf={}
 if f.compareOnly then
  for _,row in ipairs(rows) do
   local p=self:LeaderboardEntry(row)
   for _,d in ipairs(data.dungeons or {}) do local b=p and p.best[d.id];if b and b[1]>(bestOf[d.id] or -1) then bestOf[d.id]=b[1] end end
  end
 end
 local pages=math.max(1,math.ceil(#rows/PAGE));f.page=math.max(1,math.min(f.page,pages))
 f.realmButton:SetText(realms[f.realm]);f.classButton:SetText(labels[f.classID] or 'All classes')
 f.specButton:SetShown(f.classID>0 and listing);f.specButton:SetText(f.specName or 'All specs')
 f.status:SetText((data.season or 'No snapshot')..'  |  '..#rows..' players  |  Downloaded '..(data.downloaded or 'never')..self:DownloadedAgo(data.downloaded))
 f.pages:SetText(f.page..' / '..pages);f.prev:SetEnabled(f.page>1);f.next:SetEnabled(f.page<pages)
 f.empty:SetShown(#rows==0 and listing)
 for i,row in ipairs(f.rows) do
  local position=(f.page-1)*PAGE+i;local entry=rows[position];local p=self:LeaderboardEntry(entry,position,f.specName);row.player=p;row:SetShown(p~=nil and listing)
  row.entryRow=type(entry)=='table' and entry.row or entry
  local picked=f.compareMode and not f.compareOnly and row.entryRow and f.compare[row.entryRow]
  if picked then row:SetBackdropBorderColor(.97,.71,0) else row:SetBackdropBorderColor(.10,.15,.20) end
  if p then
   row.rank:SetText(p.spec and p.rank or self:PlayerRank(p) or p.rank);row.name:SetText(p.name);row.realm:SetText(p.realm);row.score:SetText(string.format('%.1f',p.score))
   local c=RAID_CLASS_COLORS and RAID_CLASS_COLORS[classes[p.class]];row.name:SetTextColor(c and c.r or .85,c and c.g or .9,c and c.b or .93)
   for j,d in ipairs(data.dungeons or {}) do
    local best=p.best[d.id]
    row.keys[j]:SetText(best and self:KeyText(best[2],self:KeyUpgrades(best[3],self:DungeonTimer(j)),9) or '|cff657080-|r')
    local top=f.compareOnly and best and best[1]==bestOf[d.id]
    row.keyBg[j]:SetShown(top and true or false)
   end
  end
 end
 self:RefreshCompareView(f,f.compareOnly and rows or nil)
end
-- " (35 min ago)" for the file's "2026-10-07 19:00 UTC" stamp, so the age is clear at a glance.
-- Both times are read as UTC fields through time(), so the local offset cancels out.
function H:DownloadedAgo(stamp)
 local y,mo,d,h,mi=(stamp or ''):match('^(%d+)-(%d+)-(%d+) (%d+):(%d+)')
 if not y then return '' end
 local now=date('!*t');if type(now)~='table' then return '' end;now.isdst=false
 local seconds=time(now)-time({year=tonumber(y),month=tonumber(mo),day=tonumber(d),hour=tonumber(h),min=tonumber(mi),sec=0,isdst=false})
 if seconds<0 then return '' end
 local minutes=math.floor(seconds/60)
 local ago=minutes<1 and 'just now' or minutes<60 and (minutes..' min ago') or minutes<48*60 and (math.floor(minutes/60)..' h ago') or (math.floor(minutes/1440)..' days ago')
 return ' ('..ago..')'
end
-- The comparison: a row per dungeon with each picked player's best run there, the best of them
-- at full brightness and the others dimmed. Two players get a Lead column between them: a bar
-- from the middle towards whoever leads, as long as the lead, with the points beside it.
local SPARE_COLOR={.31,.76,.97}
local VIEW_LEFT,VIEW_RIGHT,LEAD_MID,LEAD_HALF=232,976,562,110
local function put(fs,parent,x,y,w,just) fs:ClearAllPoints();fs:SetPoint('TOPLEFT',parent,'TOPLEFT',x,y);fs:SetWidth(w);fs:SetJustifyH(just);fs:Show() end
function H:RefreshCompareView(f,rows)
 local view=f.compareView;view:SetShown(rows~=nil);if not rows then return end
 local data=LegionKeyHistoryLeaderboard or {};local dungeons=data.dungeons or {}
 local players={};for i,row in ipairs(rows) do players[i]=self:LeaderboardEntry(row) end
 local n=#players;local duel=n==2
 local colors,used={},{}
 for k,p in ipairs(players) do
  local c=RAID_CLASS_COLORS and RAID_CLASS_COLORS[classes[p.class]];local col={c and c.r or .85,c and c.g or .9,c and c.b or .93}
  colors[k]=used[p.class] and SPARE_COLOR or col;used[p.class]=true
 end
 -- Column k: beside the Lead column for two players, evenly spread otherwise.
 local function column(k)
  if duel then return k==1 and VIEW_LEFT or LEAD_MID+LEAD_HALF+20,LEAD_MID-LEAD_HALF-20-VIEW_LEFT,k==1 and 'RIGHT' or 'LEFT' end
  local w=math.floor((VIEW_RIGHT-VIEW_LEFT)/n);return VIEW_LEFT+(k-1)*w,w,'CENTER'
 end
 for k,h in ipairs(view.heads) do
  local p=players[k];h.name:SetShown(p~=nil);h.sub:SetShown(p~=nil)
  if p then
   local x,w,just=column(k)
   put(h.name,view,x+8,-8,w,just);put(h.sub,view,x+8,-26,w,just)
   h.name:SetText(p.name);h.name:SetTextColor(colors[k][1],colors[k][2],colors[k][3])
   h.sub:SetText(string.format('%.1f  |  #%d',p.score,self:PlayerRank(p) or p.rank))
  end
 end
 view.leadHead:SetShown(duel)
 -- Points between the two per dungeon, and the largest, so the bars share one scale.
 local largest=duel and math.abs(players[1].score-players[2].score) or 0
 if duel then
  for _,d in ipairs(dungeons) do
   local x,y=players[1].best[d.id],players[2].best[d.id]
   largest=math.max(largest,math.abs((x and x[1] or 0)-(y and y[1] or 0)))
  end
 end
 largest=math.max(largest,1)
 local function lead(r,diff)
  local points=math.floor(math.abs(diff)*10+.5)/10;local side=diff>=0 and 1 or 2;local c=colors[side]
  r.mid:Show();r.bar:SetShown(points>0)
  if points>0 then
   r.bar:ClearAllPoints();r.bar:SetColorTexture(c[1],c[2],c[3],.85);r.bar:SetSize(math.max(2,LEAD_HALF*points/largest),8)
   r.bar:SetPoint(side==1 and 'RIGHT' or 'LEFT',r,'LEFT',LEAD_MID,0)
  end
  r.value:SetText(points==0 and '=' or string.format('+%.1f',points))
  if points==0 then r.value:SetTextColor(.55,.55,.55) else r.value:SetTextColor(c[1],c[2],c[3]) end
  if side==1 then put(r.value,r,LEAD_MID+6,-9,70,'LEFT') else put(r.value,r,LEAD_MID-76,-9,70,'RIGHT') end
 end
 for i,r in ipairs(view.lines) do
  local d=dungeons[i];local total=i==#dungeons+1;r:SetShown(d~=nil or total)
  if d or total then
   local values={}
   for k,p in ipairs(players) do
    local b=d and p.best[d.id];values[k]=total and p.score or (b and b[1] or 0)
    local x,w,just=column(k);put(r.cells[k],r,x,-8,w,just)
    r.cells[k]:SetText(total and string.format('%.1f',p.score)
     or b and (self:KeyText(b[2],self:KeyUpgrades(b[3],self:DungeonTimer(i)),10)..'   '..string.format('%.1f',b[1])) or '|cff657080-|r')
   end
   for k=n+1,#r.cells do r.cells[k]:Hide() end
   local top=math.max(0,unpack(values))
   for k in ipairs(players) do r.cells[k]:SetAlpha((n>1 and values[k]>0 and values[k]<top) and .45 or 1) end
   local map=d and (data.historyMaps or {})[i]
   r.icon:SetShown(map~=nil);if map then r.icon:SetTexture(self:DungeonIcon(map.mapID)) end
   r.name:SetText(total and 'SCORE' or d.name)
   if duel then lead(r,values[1]-values[2]) else r.mid:Hide();r.bar:Hide();r.value:Hide() end
  end
 end
end
function H:OpenLeaderboard()
 if not self.leaderboardFrame then self:CreateLeaderboard() end
 for _,f in pairs({self.frame,self.statsFrame,self.daysFrame}) do f:Hide() end
 self.leaderboardFrame:Show();self:RefreshLeaderboard();self:Front(self.leaderboardFrame)
end
function H:CreateLeaderboard()
 local data=LegionKeyHistoryLeaderboard or {};local f=CreateFrame('Frame','LegionKeyHistoryLeaderboardFrame',UIParent);self.leaderboardFrame=f
 f:SetSize(1040,560);f:SetPoint('CENTER');f:SetScale(self.frame and self.frame:GetScale() or 1);f:SetClampedToScreen(true)
 f:SetBackdrop(backdrop);f:SetBackdropColor(.025,.035,.05,1);f:SetBackdropBorderColor(.17,.30,.34);f:EnableMouse(true)
 f:SetMovable(true);f:RegisterForDrag('LeftButton');f:SetScript('OnDragStart',f.StartMoving);f:SetScript('OnDragStop',f.StopMovingOrSizing)
 table.insert(UISpecialFrames,'LegionKeyHistoryLeaderboardFrame')
 f.title=text(f,23,22,-18,650,'|cff4adbc8MYTHIC+|r  Player leaderboard')
 button(f,'Your runs',95,875,-20,function() f:Hide();H:OpenJournal() end)
 button(f,'X',24,994,-20,function() f:Hide() end)
 f.status=text(f,11,24,-51,980)
 f.search=CreateFrame('EditBox',nil,f,'InputBoxTemplate');f.search:SetSize(270,22);f.search:SetPoint('TOPLEFT',29,-87);f.search:SetAutoFocus(false)
 f.search:SetScript('OnEscapePressed',function(s) s:ClearFocus() end)
 f.searchLabel=text(f,10,24,-72,280,'SEARCH PLAYER / REALM')
 f.realm=2;f.classID=0;f.page=1;f.dungeon=false
 f.realmButton=button(f,'Evermoon',125,321,-86,function() f.realm=f.realm%#realms+1;f.page=1;H:RefreshLeaderboard() end)
 f.classButton=button(f,'All classes',125,458,-86,function() f.classID=(f.classID+1)%13;f.specName=nil;f.page=1;H:RefreshLeaderboard() end)
 f.specButton=button(f,'All specs',125,595,-86,function()
  if not f.specMenu then f.specMenu=CreateFrame('Frame','LKHSpecMenu',UIParent,'UIDropDownMenuTemplate') end
  local function selectSpec(name) f.specName=name;f.page=1;H:RefreshLeaderboard() end
  local menu={{text='All specs',checked=not f.specName,func=function() selectSpec(nil) end}}
  for _,spec in ipairs((LegionKeyHistoryLeaderboard or {}).specs or {}) do
   if spec.class==f.classID then local name=spec.name;menu[#menu+1]={text=name,checked=f.specName==name,func=function() selectSpec(name) end} end
  end
  EasyMenu(menu,f.specMenu,'cursor',0,0,'MENU')
 end)
 f.findButton=button(f,'Find me',75,732,-86,function() f.realm=1;f.classID=0;f.specName=nil;f.page=1;f.search:SetText(UnitName('player') or '');H:RefreshLeaderboard() end)
 f.clearButton=button(f,'Clear',65,817,-86,function() f.realm=2;f.classID=0;f.specName=nil;f.page=1;f.search:SetText('');H:RefreshLeaderboard() end)
 -- "i" next to the title: how the score works and where the data comes from.
 local help=CreateFrame('Button',nil,f);help:SetSize(22,22);help:SetPoint('TOPLEFT',335,-22);f.help=help
 help:SetBackdrop(backdrop);help:SetBackdropColor(.06,.08,.105,1);help:SetBackdropBorderColor(.29,.86,.78)
 help.label=text(help,13,0,-4,22,'i');help.label:SetJustifyH('CENTER');help.label:SetTextColor(.29,.86,.78)
 help:SetScript('OnEnter',function(s)
  GameTooltip:SetOwner(s,'ANCHOR_LEFT');GameTooltip:SetText('Raider.IO-style score (unofficial)')
  GameTooltip:AddLine('Sum of the best run score in each listed dungeon. Fortified and Tyrannical are not counted separately.',1,1,1,true)
  GameTooltip:AddLine('Timed: 50 + 7.5 x level + 12.5 x fraction under timer.',.8,.9,.9,true)
  GameTooltip:AddLine('Overtime: 50 + 7.5 x (level - 1) - 20 x fraction over timer; minimum 0.',.8,.9,.9,true)
  -- update_leaderboard_api.py reads the Tauri API live; update_leaderboard.py the GitHub snapshot.
  local live=(data.source or ''):find('Tauri armory API',1,true)
  GameTooltip:AddLine('Scored with the Tauri Achievements formula; these are not official Raider.IO ratings.',1,.8,.3,true)
  GameTooltip:AddLine('Keys you recorded yourself count straight away for everyone in them; all other runs arrive with the next file update.',1,1,1,true)
  if live then
   GameTooltip:AddLine('Read from the Tauri API outside WoW. Newer runs arrive with the next leaderboard file; /reload to load it.',1,1,1,true)
   GameTooltip:AddLine('Source: Tauri armory API (chapi.tauri.hu)',.6,.8,.8,true)
   GameTooltip:AddLine('Read from the API: '..(data.downloaded or '?'),.6,.8,.8,true)
  else
   GameTooltip:AddLine('Run Update Leaderboard.cmd outside WoW, then /reload. Requires Python 3.',1,1,1,true)
   GameTooltip:AddLine('Source: tauriachievements/tauriachievements.github.io',.6,.8,.8,true)
   GameTooltip:AddLine('Source commit: '..(data.revision or '?'):sub(1,12)..' ('..(data.sourceDate or '?')..')',.6,.8,.8,true)
  end
  GameTooltip:Show()
 end);help:SetScript('OnLeave',function() GameTooltip:Hide() end)
 -- Compare: pick players (click their rows), then Show to see only them, with the best
 -- run in each dungeon highlighted.
 -- Runs view: dungeon tiles as on the journal, smaller: All (default) or one dungeon.
 f.dungeonTiles={}
 for j=0,#(data.dungeons or {}) do
  local d=(data.dungeons or {})[j];local map=(data.historyMaps or {})[j]
  local b=CreateFrame('Button',nil,f);b:SetSize(46,46);b:SetPoint('TOPLEFT',24+j*50,-82);b.slot=d and j or 0
  b:SetBackdrop(backdrop);b:SetBackdropColor(.06,.085,.11,1);b:SetBackdropBorderColor(.16,.20,.25)
  local icon=b:CreateTexture(nil,'ARTWORK');icon:SetSize(28,28);icon:SetPoint('TOP',0,-3);icon:SetTexCoord(.07,.93,.07,.93)
  icon:SetTexture(map and map.mapID and H:DungeonIcon(map.mapID) or 'Interface\\Icons\\INV_Misc_Map_01')
  local label=text(b,8,0,-33,46,d and d.short or 'ALL');label:SetJustifyH('CENTER')
  b:SetHighlightTexture('Interface\\Buttons\\ButtonHilight-Square','ADD')
  b:SetScript('OnClick',function(s) f.dungeon=s.slot>0 and s.slot or false;f.page=1;H:RefreshLeaderboard() end)
  b:SetScript('OnEnter',function(s) GameTooltip:SetOwner(s,'ANCHOR_TOP');GameTooltip:SetText(d and d.name or 'All dungeons')
   GameTooltip:AddLine(d and 'Runs in this dungeon only' or 'Runs in every dungeon',.6,.8,.8);GameTooltip:Show() end)
  b:SetScript('OnLeave',function() GameTooltip:Hide() end)
  f.dungeonTiles[#f.dungeonTiles+1]=b
 end
 -- Players or Runs. The Runs view ranks every run in the file by its score, as on the website.
 f.view='players';f.runOrder='best'
 f.playersButton=button(f,'Players',80,690,-20,function() f.view='players';f.page=1;H:RefreshLeaderboard() end)
 f.runsButton=button(f,'Runs',80,775,-20,function() f.view='runs';f.page=1;H:RefreshLeaderboard() end)
 f.runOrderButton=button(f,'Order: Best',115,895,-94,function() f.runOrder=f.runOrder=='best' and 'latest' or 'best';f.page=1;H:RefreshLeaderboard() end)
 f.runHeaders,f.runLines=H:CreateRunLines(f,-140,-158)
 f.runWidgets={f.runOrderButton}
 for _,w in ipairs(f.runHeaders) do f.runWidgets[#f.runWidgets+1]=w end
 for _,b in ipairs(f.dungeonTiles) do f.runWidgets[#f.runWidgets+1]=b end
 f.compare={};f.compareCount=0;f.compareMode=false;f.compareOnly=false
 f.compareButton=button(f,'Compare',70,895,-86,function()
  f.compareMode=not f.compareMode
  if not f.compareMode then f.compare={};f.compareCount=0;f.compareOnly=false end
  f.page=1;H:RefreshLeaderboard()
 end)
 f.compareShow=button(f,'Show',60,970,-86,function() f.compareOnly=not f.compareOnly;f.page=1;H:RefreshLeaderboard() end)
 f.compareHint=text(f,11,24,-112,980,'')
 f.tableHeaders={text(f,10,24,-126,45,'RANK'),text(f,10,79,-126,205,'PLAYER'),text(f,10,290,-126,105,'REALM')};f.scoreHeader=text(f,10,402,-126,75,'SCORE')
 f.dungeonHeaders={}
 for j,d in ipairs(data.dungeons or {}) do f.dungeonHeaders[j]=text(f,10,486+(j-1)*59,-126,56,d.short) end
 f.rows={}
 for i=1,PAGE do
  local row=CreateFrame('Button',nil,f);f.rows[i]=row;row:SetSize(992,28);row:SetPoint('TOPLEFT',24,-145-(i-1)*30)
  row:SetBackdrop(backdrop);row:SetBackdropColor(.06,.08,.105,1);row:SetBackdropBorderColor(.10,.15,.20)
  row:SetHighlightTexture('Interface\\Buttons\\ButtonHilight-Square','ADD')
  row.rank=text(row,11,4,-7,46);row.name=text(row,12,55,-7,205);row.realm=text(row,11,266,-7,105);row.score=text(row,12,378,-7,75);row.keys={};row.keyBg={};row.keyCells={}
  for j=1,#(data.dungeons or {}) do
   -- Each key is its own hover target: that run's time, result and score.
   local cell=CreateFrame('Button',nil,row);cell:SetSize(57,28);cell:SetPoint('TOPLEFT',456+(j-1)*59,0)
   -- Compare highlight: on the cell itself, so the row background cannot cover it.
   row.keyBg[j]=cell:CreateTexture(nil,'BACKGROUND');row.keyBg[j]:SetPoint('TOPLEFT',1,-3);row.keyBg[j]:SetPoint('BOTTOMRIGHT',-3,3)
   row.keyBg[j]:SetColorTexture(.97,.71,0,.35);row.keyBg[j]:Hide()
   cell:SetHighlightTexture('Interface\\Buttons\\ButtonHilight-Square','ADD')
   row.keys[j]=text(cell,11,6,-7,52);row.keyCells[j]=cell
   cell:SetScript('OnEnter',function(s)
    local p=row.player;local d=(LegionKeyHistoryLeaderboard.dungeons or {})[j];if not p or not d then return end
    local b=p.best[d.id];GameTooltip:SetOwner(s,'ANCHOR_TOP')
    if not b then GameTooltip:SetText(d.name..': no run');GameTooltip:Show();return end
    local up=H:KeyUpgrades(b[3],H:DungeonTimer(j))
    GameTooltip:SetText(d.name..'  '..H:KeyText(b[2],up))
    GameTooltip:AddLine(H:Clock(b[3])..'  '..(up>0 and ('timed +'..up) or 'over time'),1,1,1)
    GameTooltip:AddDoubleLine('Run score',string.format('%.1f',b[1]),.8,.85,.9,1,.82,0)
    if b[4] and b[4]>0 then GameTooltip:AddLine(date('%a %d %b %Y  %H:%M',b[4]),.6,.65,.7) end
    GameTooltip:Show()
   end)
   cell:SetScript('OnLeave',function() GameTooltip:Hide() end)
   cell:SetScript('OnClick',function() local click=row:GetScript('OnClick');if click then click(row) end end)
  end
  -- Click: open that player's runs, or pick them while comparing.
  row:SetScript('OnClick',function(s)
   local p=s.player;if not p or not s.entryRow then return end
   if f.compareMode then
    if f.compare[s.entryRow] then f.compare[s.entryRow]=nil;f.compareCount=f.compareCount-1
    elseif f.compareCount<5 then f.compare[s.entryRow]=true;f.compareCount=f.compareCount+1 end
    H:RefreshLeaderboard()
   else
    H:OpenPlayerRuns(s.entryRow)
   end
  end)
  row:SetScript('OnEnter',function(s)
   local p=s.player;if not p then return end
   GameTooltip:SetOwner(s,'ANCHOR_LEFT');GameTooltip:SetText(p.name..' - '..p.realm)
   GameTooltip:AddLine(string.format('%.1f points | Rank %d',p.score,p.spec and p.rank or H:PlayerRank(p) or p.rank),1,.82,0)
   if p.spec then GameTooltip:AddLine(p.spec..' runs only',.29,.86,.78) end
   for j,d in ipairs(data.dungeons or {}) do local b=p.best[d.id];local late=H:OverTime(j,b)
    GameTooltip:AddDoubleLine(grey(d.name,late),b and grey(string.format('+%d  %s  |  %.1f',b[2],H:Clock(b[3]),b[1]),late) or '-',.85,.9,.93,1,1,1)
   end
   GameTooltip:Show()
  end);row:SetScript('OnLeave',function() GameTooltip:Hide() end)
 end
 -- The comparison (RefreshCompareView), in place of the table while comparing.
 local view=CreateFrame('Frame',nil,f);f.compareView=view;view:SetSize(992,350);view:SetPoint('TOPLEFT',24,-114)
 view:SetBackdrop(backdrop);view:SetBackdropColor(.035,.05,.07,1);view:SetBackdropBorderColor(.10,.15,.20)
 text(view,10,12,-16,200,'DUNGEON')
 view.heads={}
 for k=1,5 do
  local h={name=text(view,13,0,-8,180,''),sub=text(view,10,0,-26,180,'')};h.sub:SetTextColor(.6,.65,.7);view.heads[k]=h
 end
 view.leadHead=text(view,10,LEAD_MID-52,-16,120,'LEAD');view.leadHead:SetJustifyH('CENTER');view.leadHead:SetTextColor(.97,.71,0)
 view.lines={}
 for i=1,#(data.dungeons or {})+1 do
  local r=CreateFrame('Frame',nil,view);r:SetSize(976,28);r:SetPoint('TOPLEFT',8,-46-(i-1)*29)
  local bg=r:CreateTexture(nil,'BACKGROUND');bg:SetAllPoints();bg:SetColorTexture(1,1,1,i%2==1 and .03 or 0)
  r.icon=r:CreateTexture(nil,'ARTWORK');r.icon:SetSize(22,22);r.icon:SetPoint('LEFT',4,0);r.icon:SetTexCoord(.07,.93,.07,.93)
  r.name=text(r,11,32,-8,190,'')
  r.cells={};for k=1,5 do r.cells[k]=text(r,11,0,-8,180,'') end
  r.mid=r:CreateTexture(nil,'ARTWORK');r.mid:SetColorTexture(.35,.4,.45,1);r.mid:SetSize(1,18);r.mid:SetPoint('CENTER',r,'LEFT',LEAD_MID,0)
  r.bar=r:CreateTexture(nil,'ARTWORK');r.value=text(r,10,0,-9,70,'')
  view.lines[i]=r
 end
 view:Hide()
 f.empty=text(f,14,25,-200,980,'No matching players. Try All realms or update the snapshot.');f.empty:SetJustifyH('CENTER')
 f.footer=text(f,10,24,-521,780,'Unofficial score: best per dungeon summed. Click a player to see their runs. Hover for details.')
 f.prev=button(f,'<',30,880,-515,function() f.page=f.page-1;H:RefreshLeaderboard() end)
 f.pages=text(f,11,920,-521,65)
 f.next=button(f,'>',30,986,-515,function() f.page=f.page+1;H:RefreshLeaderboard() end)
 f.search:SetScript('OnTextChanged',function() f.page=1;H:RefreshLeaderboard() end)
 f.listOnly={f.search,f.searchLabel,f.realmButton,f.classButton,f.findButton,f.clearButton,f.footer,f.prev,f.pages,f.next,f.scoreHeader}
 for _,w in ipairs(f.tableHeaders) do f.listOnly[#f.listOnly+1]=w end
 for _,w in ipairs(f.dungeonHeaders) do f.listOnly[#f.listOnly+1]=w end
 f:Hide()
end

-- A player's runs -------------------------------------------------------------------------------

-- Keystone upgrades for a clear: 3 within 60% of the timer, 2 within 80%, 1 in time, 0 over.
function H:KeyUpgrades(seconds,timer)
 if not timer or not seconds or seconds>timer then return 0 end
 return seconds<=timer*.6 and 3 or seconds<=timer*.8 and 2 or 1
end
-- Leaderboard keys use the shared style: stars when timed, faded when over time.
function H:KeyText(level,upgrades,size)
 return self:KeyStars(level,upgrades,upgrades==0,size)
end
-- Timer of the j-th dungeon in the leaderboard file (historyMaps follows the dungeon order).
function H:DungeonTimer(j)
 local maps=(LegionKeyHistoryLeaderboard or {}).historyMaps
 return maps and maps[j] and maps[j].timer
end

local function runScore(level,seconds,timer)
 if not timer or timer<=0 or seconds<=0 then return 0 end
 local ratio=seconds/timer
 local score=ratio<=1 and (50+7.5*level+12.5*(1-ratio)) or (50+7.5*(level-1)-20*(ratio-1))
 return math.floor(math.max(0,score)*10+.5)/10
end
-- One line of the file's run history: map|level|ms|stamp|[score|]affixes|party.
local function historyFields(line)
 local map,level,ms,stamp,aff,party=line:match('^(%d+)|(%d+)|(%d+)|(%d+)|([^|]*)|([^|]*)$')
 if not map then map,level,ms,stamp,aff,party=line:match('^(%d+)|(%d+)|(%d+)|(%d+)|[%d.]+|([^|]*)|([^|]*)$') end
 return map,level,ms,stamp,aff,party
end
-- A run, ready to show, from one history line.
local function historyRun(data,line)
 local map,level,ms,stamp,aff,party=historyFields(line);if not map then return nil end
 local slot=tonumber(map);local info=data.historyMaps[slot] or {}
 local seconds=tonumber(ms)/1000;local timer=info.timer
 local dungeon=data.dungeons and data.dungeons[slot] or {}
 local run={line=line,slot=slot,mapID=info.mapID,dungeon={name=info.name or dungeon.name,short=dungeon.short},level=tonumber(level),seconds=seconds,stamp=tonumber(stamp),
  affixes={},members={},score=runScore(tonumber(level),seconds,timer),upgrades=H:KeyUpgrades(seconds,timer)}
 for a in aff:gmatch('%d+') do run.affixes[#run.affixes+1]=tonumber(a) end
 for r,s in party:gmatch('(%d+):?(%d*)') do run.members[#run.members+1]={row=tonumber(r),spec=data.specs and data.specs[tonumber(s) or 0]} end
 return run
end
-- Every run in the file ranked by run score (best first; the earlier run wins a tie), for all
-- dungeons (slot nil) or one. Entries are {line,score,stamp,rank}; runs are built per page.
-- Kept once per file, along with each run's season rank for the players' run lists.
function H:RunRanking(slot)
 local data=LegionKeyHistoryLeaderboard;if not data or not data.historyText then return {} end
 local cache=data.runRanking;if not cache then cache={};data.runRanking=cache end
 local key=slot or 0;if cache[key] then return cache[key] end
 local list={}
 for line in data.historyText:gmatch('[^\n]+') do
  local map,level,ms,stamp=historyFields(line)
  if map and (not slot or tonumber(map)==slot) then
   local info=data.historyMaps[tonumber(map)] or {}
   list[#list+1]={line=line,score=runScore(tonumber(level),tonumber(ms)/1000,info.timer),stamp=tonumber(stamp)}
  end
 end
 table.sort(list,function(a,b) if a.score~=b.score then return a.score>b.score end;return a.stamp<b.stamp end)
 for i,e in ipairs(list) do e.rank=i end
 cache[key]=list
 if not slot then data.runRankByLine={};for _,e in ipairs(list) do data.runRankByLine[e.line]=e.rank end end
 return list
end
-- The same runs newest first; each keeps its score rank.
function H:LatestRuns(slot)
 local data=LegionKeyHistoryLeaderboard or {};local key='latest'..(slot or 0)
 local cache=data.runRanking or {};if cache[key] then return cache[key] end
 local list={};for i,e in ipairs(self:RunRanking(slot)) do list[i]=e end
 table.sort(list,function(a,b) if a.stamp~=b.stamp then return a.stamp>b.stamp end;return a.rank<b.rank end)
 data.runRanking[key]=list;return list
end
-- Every run in the leaderboard file that a character (leaderboard row) played.
function H:PlayerRuns(row)
 local data=LegionKeyHistoryLeaderboard
 if not row or not data or not data.historyText then return {} end
 local needle=','..row..':';local runs={}
 for line in data.historyText:gmatch('[^\n]+') do
  local map,_,_,_,_,party=historyFields(line)
  if map and (','..party):find(needle,1,true) then runs[#runs+1]=historyRun(data,line) end
 end
 return runs
end
-- "12 min ago", "5 h ago", "3 d ago".
function H:Ago(stamp)
 local minutes=math.max(0,math.floor((time()-stamp)/60))
 if minutes<1 then return 'just now' elseif minutes<60 then return minutes..' min ago' end
 local hours=math.floor(minutes/60)
 return hours<24 and (hours..' h ago') or (math.floor(hours/24)..' d ago')
end
local function memberText(data,member)
 local key=data.names[member.row];if not key then return '?' end
 local display=data.info[member.row]:match('^([^|]*)|')
 local name=display~='' and display or key:gsub('^[a-z]',string.upper)
 local c=RAID_CLASS_COLORS and RAID_CLASS_COLORS[classes[data.classes[member.row]]]
 return c and string.format('|cff%02x%02x%02x%s|r',c.r*255,c.g*255,c.b*255,name) or name
end
-- Run lists (the leaderboard's Runs view and a player's runs): name, x, width. The dungeon's
-- icon sits left of its name.
local RUN_COLUMNS={{'RANK',8,40},{'DUNGEON',50,64},{'LEVEL',122,78},{'TIME',204,56},{'AFFIXES',264,68},{'TANK',336,116},{'HEALER',454,116},{'DPS',572,276},{'SCORE',852,56},{'COMPLETED',912,76}}
local RUN_ICON_X=50
function H:CreateRunLines(f,headerY,firstY)
 local headers={}
 for k,col in ipairs(RUN_COLUMNS) do headers[k]=text(f,10,24+col[2],headerY,col[3],col[1]) end
 local lines={}
 for i=1,PAGE do
  local line=CreateFrame('Button',nil,f);lines[i]=line;line:SetSize(992,28);line:SetPoint('TOPLEFT',24,firstY-(i-1)*30)
  line:SetBackdrop(backdrop);line:SetBackdropColor(.06,.08,.105,1);line:SetBackdropBorderColor(.10,.15,.20)
  line:SetHighlightTexture('Interface\\Buttons\\ButtonHilight-Square','ADD')
  line.cells={};line.affixes={}
  for k,col in ipairs(RUN_COLUMNS) do
   local x=col[1]=='DUNGEON' and col[2]+24 or col[2]
   line.cells[k]=text(line,col[1]=='LEVEL' and 12 or 11,x,-7,col[1]=='DUNGEON' and col[3]-24 or col[3])
  end
  line.icon=line:CreateTexture(nil,'ARTWORK');line.icon:SetSize(20,20);line.icon:SetPoint('TOPLEFT',RUN_ICON_X,-4);line.icon:SetTexCoord(.07,.93,.07,.93)
  for k=1,3 do local icon=line:CreateTexture(nil,'ARTWORK');icon:SetSize(18,18);icon:SetPoint('TOPLEFT',RUN_COLUMNS[5][2]+(k-1)*21,-5);line.affixes[k]=icon end
  line:SetScript('OnEnter',function(s)
   local run=s.run;if not run then return end
   local data=LegionKeyHistoryLeaderboard
   GameTooltip:SetOwner(s,'ANCHOR_LEFT');GameTooltip:SetText((run.dungeon.name or '?')..' +'..run.level)
   GameTooltip:AddLine(date('%a %d %b %Y  %H:%M',run.stamp),.8,.85,.9)
   GameTooltip:AddLine(H:Clock(run.seconds)..(run.upgrades>0 and ('  |cff3fbf5ftimed +'..run.upgrades..'|r') or '  |cffe06666over time|r')..string.format('  |  %.1f',run.score),1,1,1)
   for _,m in ipairs(run.members) do GameTooltip:AddDoubleLine(memberText(data,m),m.spec and m.spec.name or '',1,1,1,.7,.75,.8) end
   GameTooltip:Show()
  end)
  line:SetScript('OnLeave',function() GameTooltip:Hide() end)
 end
 return headers,lines
end
function H:FillRunLine(line,run,rank)
 local data=LegionKeyHistoryLeaderboard;line.run=run;line:SetShown(run~=nil)
 if not run then return end
 line.cells[1]:SetText(rank and tostring(rank) or '-')
 line.icon:SetTexture(run.mapID and self:DungeonIcon(run.mapID) or 'Interface\\Icons\\INV_Misc_Map_01')
 line.cells[2]:SetText(run.dungeon.short or '?')
 line.cells[3]:SetText(self:KeyText(run.level,run.upgrades))
 line.cells[4]:SetText((run.upgrades>0 and '' or '|cff888888')..self:Clock(run.seconds)..(run.upgrades>0 and '' or '|r'))
 for k=1,3 do
  local id=run.affixes[k];local icon=line.affixes[k]
  local texture=id and C_ChallengeMode.GetAffixInfo and select(3,C_ChallengeMode.GetAffixInfo(id))
  icon:SetTexture(texture);icon:SetShown(texture~=nil)
 end
 local tank,healer,dps={},{},{}
 for _,m in ipairs(run.members) do
  local role=m.spec and m.spec.role or 'dps'
  local list=role=='tank' and tank or role=='healer' and healer or dps
  list[#list+1]=memberText(data,m)
 end
 line.cells[6]:SetText(table.concat(tank,'  '));line.cells[7]:SetText(table.concat(healer,'  '));line.cells[8]:SetText(table.concat(dps,'  '))
 line.cells[9]:SetText(string.format('%.1f',run.score));line.cells[10]:SetText(self:Ago(run.stamp))
end
function H:OpenPlayerRuns(row)
 local data=LegionKeyHistoryLeaderboard;if not data or not data.names or not data.names[row] then return end
 if not self.playerRunsFrame then self:CreatePlayerRuns() end
 local f=self.playerRunsFrame
 f.player=self:LeaderboardEntry(row);f.runs=self:PlayerRuns(row);f.page=1
 f:Show();self:RefreshPlayerRuns();self:Front(f)
end
function H:RefreshPlayerRuns()
 local f=self.playerRunsFrame;if not f then return end
 local data=LegionKeyHistoryLeaderboard;local p=f.player
 local runs=f.runs
 table.sort(runs,function(a,b)
  if f.order=='best' then if a.score~=b.score then return a.score>b.score end end
  return a.stamp>b.stamp
 end)
 self:RunRanking()
 local ranks=data.runRankByLine or {}
 local c=RAID_CLASS_COLORS and RAID_CLASS_COLORS[classes[p.class]]
 f.title:SetText((c and string.format('|cff%02x%02x%02x',c.r*255,c.g*255,c.b*255) or '')..p.name..'|r  '..p.realm)
 f.status:SetText(string.format('%.1f points  |  Rank %s  |  %d runs in the leaderboard file',p.score,tostring(self:PlayerRank(p) or '?'),#runs))
 f.orderButton:SetText(f.order=='best' and 'Order: Best' or 'Order: Latest')
 local pages=math.max(1,math.ceil(#runs/PAGE));f.page=math.max(1,math.min(f.page,pages))
 f.pages:SetText(f.page..' / '..pages);f.prev:SetEnabled(f.page>1);f.next:SetEnabled(f.page<pages)
 f.empty:SetShown(#runs==0)
 for i,line in ipairs(f.rows) do
  local run=runs[(f.page-1)*PAGE+i];self:FillRunLine(line,run,run and ranks[run.line])
 end
end
function H:CreatePlayerRuns()
 local f=CreateFrame('Frame','LegionKeyHistoryPlayerRuns',UIParent);self.playerRunsFrame=f
 f:SetSize(1040,560);f:SetPoint('CENTER');f:SetScale(self.leaderboardFrame and self.leaderboardFrame:GetScale() or 1);f:SetClampedToScreen(true)
 f:SetFrameStrata('DIALOG');f:SetBackdrop(backdrop);f:SetBackdropColor(.025,.035,.05,1);f:SetBackdropBorderColor(.17,.30,.34);f:EnableMouse(true)
 f:SetMovable(true);f:RegisterForDrag('LeftButton');f:SetScript('OnDragStart',f.StartMoving);f:SetScript('OnDragStop',f.StopMovingOrSizing)
 table.insert(UISpecialFrames,'LegionKeyHistoryPlayerRuns')
 f.title=text(f,23,22,-18,650,'')
 f.status=text(f,11,24,-51,980)
 f.order='latest'
 f.orderButton=button(f,'Order: Latest',115,755,-20,function() f.order=f.order=='best' and 'latest' or 'best';f.page=1;H:RefreshPlayerRuns() end)
 button(f,'Leaderboard',105,875,-20,function() f:Hide() end)
 button(f,'X',24,994,-20,function() f:Hide() end)
 local _,lines=self:CreateRunLines(f,-90,-108);f.rows=lines
 f.empty=text(f,14,25,-200,980,'No runs for this player in the leaderboard file.');f.empty:SetJustifyH('CENTER')
 text(f,10,24,-521,780,'Runs in the leaderboard file. Rank: the run\'s place among every run of the season. Hover a run for the date and the group.')
 f.prev=button(f,'<',30,880,-515,function() f.page=f.page-1;H:RefreshPlayerRuns() end)
 f.pages=text(f,11,920,-521,65)
 f.next=button(f,'>',30,986,-515,function() f.page=f.page+1;H:RefreshPlayerRuns() end)
 if self.ApplyFont then self:ApplyFont(f) end
 f:Hide()
end
-- The leaderboard's Runs view: every run in the file by run score, for all dungeons or the
-- dungeon tile picked; Latest lists them newest first, each keeping its rank.
function H:RefreshRunBoard(f)
 local data=LegionKeyHistoryLeaderboard or {};local slot=f.dungeon or nil
 local list=f.runOrder=='latest' and self:LatestRuns(slot) or self:RunRanking(slot)
 for _,b in ipairs(f.dungeonTiles or {}) do
  local on=b.slot==(f.dungeon or 0);b:SetBackdropBorderColor(on and .29 or .16,on and .86 or .20,on and .78 or .25)
 end
 f.runOrderButton:SetText(f.runOrder=='latest' and 'Order: Latest' or 'Order: Best')
 local name=slot and data.dungeons and data.dungeons[slot] and data.dungeons[slot].name
 f.status:SetText((data.season or 'No snapshot')..'  |  '..#list..' runs  |  '..(name or 'All dungeons')..'  |  Downloaded '..(data.downloaded or 'never')..self:DownloadedAgo(data.downloaded))
 local pages=math.max(1,math.ceil(#list/PAGE));f.page=math.max(1,math.min(f.page,pages))
 f.pages:SetText(f.page..' / '..pages);f.prev:SetEnabled(f.page>1);f.next:SetEnabled(f.page<pages)
 f.footer:SetText('Every run in the leaderboard file by run score (unofficial). Latest: newest first, each keeping its rank. Hover a run for the group.')
 f.empty:SetText('No runs in the leaderboard file. Run LKH Updater.cmd, then /reload.');f.empty:SetShown(#list==0)
 for i,line in ipairs(f.runLines) do
  local e=list[(f.page-1)*PAGE+i];self:FillRunLine(line,e and historyRun(data,e.line),e and e.rank)
 end
end

-- Runs imported before roles were kept: fill in each member's role and class from the
-- leaderboard file, once. Matches on dungeon, level, completion time and clear time.
function H:BackfillImportedRoles()
 local data=LegionKeyHistoryLeaderboard
 if self.rolesBackfilled or not data or not data.historyText or not data.specs or not self.db then return 0 end
 self.rolesBackfilled=true
 local wanted={}
 for _,run in ipairs(self.db.runs) do
  if run.source=='Tauri file' and run.members and run.members[1] and not run.members[1].role and run.id then
   local map,level,stamp,ms=run.id:match('^tauri:(%d+):(%d+):(%d+):(%d+):')
   if map then wanted[map..':'..level..':'..stamp..':'..ms]=run end
  end
 end
 if not next(wanted) then return 0 end
 local filled=0
 for line in data.historyText:gmatch('[^\n]+') do
  local m,level,ms,stamp,_,party=line:match('^(%d+)|(%d+)|(%d+)|(%d+)|([^|]*)|([^|]*)$')
  local info=m and data.historyMaps[tonumber(m)]
  local run=info and wanted[info.mapID..':'..level..':'..stamp..':'..ms]
  if run then
   local byKey={}
   for row,spec in party:gmatch('(%d+):(%d+)') do
    local full=self:LeaderboardFullName(tonumber(row),data);local s=data.specs[tonumber(spec)]
    if full and s then byKey[self:IdentityKey(full)]={role=FILE_ROLES[s.role],class=classes[data.classes[tonumber(row)]]} end
   end
   for _,member in ipairs(run.members) do
    local found=member.name and byKey[self:IdentityKey(member.name)]
    if found then member.role=member.role or found.role;member.class=member.class or found.class end
   end
   filled=filled+1;wanted[info.mapID..':'..level..':'..stamp..':'..ms]=nil
  end
 end
 return filled
end
