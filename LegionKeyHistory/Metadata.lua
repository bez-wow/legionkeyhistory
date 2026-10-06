LegionKeyHistory = {}
local H = LegionKeyHistory
H.dungeons = {
 {199,"Black Rook Hold",10804}, {233,"Cathedral of Eternal Night",11700},
 {210,"Court of Stars",10816}, {198,"Darkheart Thicket",10783},
 {197,"Eye of Azshara",10780}, {200,"Halls of Valor",10786},
 {208,"Maw of Souls",10807}, {206,"Neltharion's Lair",10795},
 {227,"Return to Karazhan Lower",11929}, {234,"Return to Karazhan Upper",11929},
 {239,"Seat of the Triumvirate",12008}, {209,"The Arcway",10813}, {207,"Vault of the Wardens",10801}
}
H.affixes = {[1]="Overflowing",[2]="Skittish",[3]="Volcanic",[4]="Necrotic",[5]="Teeming",[6]="Raging",[7]="Bolstering",[8]="Sanguine",[9]="Tyrannical",[10]="Fortified",[11]="Bursting",[12]="Grievous",[13]="Explosive",[14]="Quaking"}
function H:AffixText(run)
 local names={}
 for _,id in ipairs(run.affixes or {}) do names[#names+1]=self.affixes[id] or ("Affix "..id) end
 return #names>0 and table.concat(names,", ") or "Unknown"
end
function H:Clock(seconds)
 if not seconds then return "--:--" end
 return string.format("%d:%02d",math.floor(seconds/60),math.floor(seconds%60))
end
function H:Result(run)
 if run.status~="completed" then return run.status=="abandoned" and "Abandoned" or "Incomplete" end
 if run.timed==nil then return "Completed (?)" end
 return run.timed and "Timed" or "Over time"
end
function H:UpgradeCount(run)
 if run.status~='completed' or run.timed~=true then return nil end
 if type(run.upgrades)=='number' and run.upgrades>=1 and run.upgrades<=3 then return run.upgrades end
 if not run.duration or not run.timeLimit or run.timeLimit<=0 then return nil end
 if run.duration<run.timeLimit*.6 then return 3 end
 if run.duration<run.timeLimit*.8 then return 2 end
 return 1
end
function H:UpgradeText(run)
 local n=self:UpgradeCount(run)
 local colors={[1]='64df97',[2]='68cfff',[3]='e6ba68'}
 return n and ('|cff'..colors[n]..'+'..n..'|r') or '--'
end
function H:DungeonIcon(mapID)
 for _,d in ipairs(self.dungeons) do
  if d[1]==mapID then return (GetAchievementInfo and select(10,GetAchievementInfo(d[3]))) or 'Interface\\Icons\\INV_Misc_Map_01' end
 end
 return 'Interface\\Icons\\INV_Misc_Map_01'
end

function H:CompletionBadge(run)
 if run.timed==true then return self:UpgradeCount(run) and self:UpgradeText(run) or '|cff64df97Timed|r' end
 if run.timed==false then return '|cffffac68Over time|r' end
 return '|cffb0bac5Completed (?)|r'
end

-- Instance IDs differ from challenge-map IDs on Legion completion events.
H.instanceMaps={[1456]=197,[1466]=198,[1501]=199,[1477]=200,[1492]=208,[1458]=206,[1516]=209,[1493]=207,[1571]=210,[1677]=233,[1753]=239}
function H:NormalizeMap(id)
 return self.instanceMaps[id] or id
end
function H:NormalizeRun(run)
 -- A known instance ID must never replace a valid challenge ID (Karazhan has two wings).
 run.mapID=self:NormalizeMap(run.mapID)
 for _,d in ipairs(self.dungeons) do if d[1]==run.mapID then run.dungeon=d[2];break end end
end
function H:RepairHistory()
 local runs=self.db.runs;local consumed={}
 for _,r in ipairs(runs) do
  if r.instanceID and r.mapID and r.instanceID~=1651 then self.instanceMaps[r.instanceID]=self:NormalizeMap(r.mapID) end
  self:NormalizeRun(r)
 end
 if self.db.active then self:NormalizeRun(self.db.active) end
 for _,r in ipairs(runs) do
  if r.status=='completed' and r.partial and r.endedAt and r.duration then
   local match,delta
   for _,start in ipairs(runs) do
    if start.status=='incomplete' and not consumed[start] and start.mapID==r.mapID and start.level==r.level
     and start.ownerGUID==r.ownerGUID and start.startedAt and start.startedAt<r.endedAt then
     local gap=math.abs((r.endedAt-start.startedAt)-r.duration)
     if gap<600 and (not delta or gap<delta) then match=start;delta=gap end
    end
   end
   if match then
    if #(r.affixes or {})==0 then r.affixes=match.affixes end
    r.startedAt=match.startedAt;r.date=match.date;r.timeLimit=match.timeLimit;r.partial=match.partial
    if #(r.members or {})==0 then r.members=match.members end
    consumed[match]=true
   end
  end
 end
 local clean={};for _,r in ipairs(runs) do if not consumed[r] then clean[#clean+1]=r end end;self.db.runs=clean
end
function H:ColoredName(member,classes)
 local class=member.class or (classes and classes[member.guid])
 if not class and GetPlayerInfoByGUID and member.guid then local ok,_,c=pcall(GetPlayerInfoByGUID,member.guid);if ok then class=c end end
 local color=class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
 local hex=color and string.format('%02x%02x%02x',math.floor(color.r*255+.5),math.floor(color.g*255+.5),math.floor(color.b*255+.5)) or 'c6d2db'
 return '|cff'..hex..(member.name or '?'):match('^[^-]+')..'|r'
end
function H:BuildStats()
 local out={total=0,timed=0,seconds=0,days=0,highest=0,triples=0,people={},dungeons={}}
 local people,dungeons,days,classes={},{},{},{}
 for _,r in ipairs(self.db.runs) do for _,m in ipairs(r.members or {}) do if m.class and m.guid then classes[m.guid]=m.class end end end
 local owner=UnitGUID('player')
 local me=self:IdentityKey(UnitName('player'))
 -- Character key per GUID, so a teammate recorded live (GUID and name) and from the
 -- leaderboard file (name only) is one person.
 local keyOf={}
 for _,r in ipairs(self.db.runs) do for _,m in ipairs(r.members or {}) do
  if m.guid and m.name then keyOf[m.guid]=self:IdentityKey(m.name) end
 end end
 for _,r in ipairs(self.db.runs) do
  if r.status=='completed' and self:RunInScope(r) then
   self:ResolveTimer(r);out.total=out.total+1;out.timed=out.timed+(r.timed==true and 1 or 0)
   out.seconds=out.seconds+(r.duration or 0);out.highest=math.max(out.highest,r.level)
   if self:UpgradeCount(r)==3 then out.triples=out.triples+1 end
   local playedDay=r.endedAt and date('%Y-%m-%d',r.endedAt) or (r.date and r.date:sub(1,10))
   if playedDay then days[playedDay]=true end
   local d=dungeons[r.mapID] or {name=r.dungeon,mapID=r.mapID,count=0,timed=0,highest=0};dungeons[r.mapID]=d
   d.count=d.count+1;d.timed=d.timed+(r.timed==true and 1 or 0);d.highest=math.max(d.highest,r.level)
   -- The run's own character is never its teammate, however it was recorded.
   local ownerKey=r.owner and self:IdentityKey(r.owner) or (r.ownerGUID and keyOf[r.ownerGUID])
   local seen={}
   for _,m in ipairs(r.members or {}) do
    local id=(m.name and self:IdentityKey(m.name)) or (m.guid and keyOf[m.guid]) or m.guid
    local isOwner=(m.guid and (m.guid==owner or m.guid==r.ownerGUID)) or id==ownerKey or (not self.accountView and id==me)
    if id and not isOwner and not seen[id] then
     seen[id]=true
     local p=people[id]
     if not p then p={name=m.name,guid=m.guid,class=m.class or classes[m.guid],count=0,timed=0,highest=0};people[id]=p end
     p.guid=p.guid or m.guid;p.class=p.class or m.class or (m.guid and classes[m.guid])
     p.count=p.count+1;p.timed=p.timed+(r.timed==true and 1 or 0);p.highest=math.max(p.highest,r.level)
    end
   end
  end
 end
 for _ in pairs(days) do out.days=out.days+1 end
 for _,v in pairs(people) do out.people[#out.people+1]=v end
 for _,v in pairs(dungeons) do out.dungeons[#out.dungeons+1]=v end
 local function order(a,b) return a.count>b.count or (a.count==b.count and a.name<b.name) end
 table.sort(out.people,order);table.sort(out.dungeons,order);out.classes=classes;return out
end

function H:DailyStats()
 local buckets={};local owner=UnitGUID('player')
 for _,r in ipairs(self.db.runs) do
  if r.status=='completed' and self:RunInScope(r) then
   local day=r.endedAt and date('%Y-%m-%d',r.endedAt) or (r.date and r.date:sub(1,10))
   if day then
    self:ResolveTimer(r)
    local b=buckets[day] or {day=day,count=0,timed=0,seconds=0,highest=0};buckets[day]=b
    b.count=b.count+1;b.timed=b.timed+(r.timed==true and 1 or 0);b.seconds=b.seconds+(r.duration or 0);b.highest=math.max(b.highest,r.level)
   end
  end
 end
 local keys={};for day in pairs(buckets) do keys[#keys+1]=day end;table.sort(keys)
 if #keys==0 then return {} end
 local y,m,d=keys[1]:match('^(%d+)%-(%d+)%-(%d+)$')
 local cursor=time({year=tonumber(y),month=tonumber(m),day=tonumber(d),hour=12})
 local result={}
 while true do
  local day=date('%Y-%m-%d',cursor);if day>keys[#keys] then break end
  result[#result+1]=buckets[day] or {day=day,count=0,timed=0,seconds=0,highest=0}
  cursor=cursor+86400
 end
 return result
end

H.laterDungeons={[227]=true,[234]=true,[233]=true,[239]=true}

-- Character identity, shared by the journal, stats, sync and the leaderboard.
-- Lowercase A-Z only, so keys never depend on the client's locale (a locale-aware lower()
-- can rewrite the bytes of accented letters).
local function lowerASCII(s) return (s:gsub('[A-Z]',string.lower)) end
-- Every spelling the game, the leaderboard file and older saves use for the same realm.
local REALM_ALIASES={enevermoon='evermoon',hutauriwowserver='tauri',huwarriorsofdarkness='wod',warriorsofdarkness='wod'}
function H:RealmKey(realm)
 local key=lowerASCII(realm or ''):gsub('[%[%]%s]','')
 return REALM_ALIASES[key] or key
end
-- One key per character, whatever recorded the name: "Name-[EN] Evermoon" (live runs),
-- "Name-Evermoon" / "Name-Tauri" (leaderboard file), "name-evermoon" and a bare "Name"
-- (your own realm) all become "name-evermoon" / "name-tauri".
function H:IdentityKey(name,realm)
 if not name or name=='' then return nil end
 local n,r=name:match('^([^%-]+)%-(.+)$');n=n or name
 r=r or ((realm and realm~='') and realm) or GetRealmName()
 return lowerASCII(n)..'-'..self:RealmKey(r)
end

-- One key style everywhere, like the website: "+18" in normal colour with one gold star per
-- keystone upgrade when timed; a faded "+18" without stars when over time.
local STAR='|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:11:11:0:0|t'
function H:KeyStars(level,upgrades,overTime)
 if overTime then return '|cff777777+'..level..'|r' end
 return '+'..level..((upgrades and upgrades>0) and (' '..STAR:rep(upgrades)) or '')
end
-- A recorded run: stars from its upgrades, faded when it was over time.
function H:RunKeyText(run)
 return self:KeyStars(run.level,self:UpgradeCount(run),run.timed==false)
end
-- Member role from recorded runs ('TANK', 'HEALER', 'DAMAGER'/'NONE'/nil) as tank/healer/dps.
function H:MemberRole(member)
 local role=member and member.role
 return role=='TANK' and 'tank' or role=='HEALER' and 'healer' or 'dps'
end
