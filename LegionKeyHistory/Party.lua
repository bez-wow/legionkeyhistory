-- /lkh party: everyone in the group side by side, with what their score tooltip shows: score,
-- ranks, the best key in each dungeon (or best Fortified / Tyrannical, per the tooltip setting)
-- and timed keys by level range. The best key of the group in each dungeon is highlighted.
local H=LegionKeyHistory

local LABEL_W,COL_W,ROW_H=150,160,26
local HEAD_Y,SUB_Y,ROWS_Y=-80,-166,-186
local ROLE_ORDER={TANK=1,HEALER=2,DAMAGER=3,NONE=3}
local backdrop={bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1}
local function text(p,size,x,y,w,value)
 local t=p:CreateFontString(nil,'OVERLAY','GameFontNormal');t:SetFont(H:FontPath(),size,'');t:SetPoint('TOPLEFT',x,y)
 t:SetWidth(w);t:SetJustifyH('LEFT');t:SetTextColor(.85,.9,.93);t:SetText(value or '');t:SetWordWrap(false);return t
end
local function button(p,label,w,x,y,fn)
 local b=CreateFrame('Button',nil,p,'UIPanelButtonTemplate');b:SetSize(w,23);b:SetPoint('TOPRIGHT',x,y);b:SetText(label);b:SetScript('OnClick',fn);return b
end
local function place(fs,x,y,w,just) fs:ClearAllPoints();fs:SetPoint('TOPLEFT',x,y);fs:SetWidth(w);fs:SetJustifyH(just) end

-- The group: you and your party, tank / healer / damage then by name. Each member has its unit,
-- name, realm, class token, role and leaderboard record (nil when not in the file or local runs).
function H:PartyMembers()
 local members={}
 for _,unit in ipairs({'player','party1','party2','party3','party4'}) do
  if UnitExists(unit) and UnitIsPlayer(unit) then
   local name,realm=UnitName(unit)
   if name and name~=UNKNOWNOBJECT then
    local role=UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or 'NONE'
    members[#members+1]={unit=unit,name=name,realm=realm,class=select(2,UnitClass(unit)),role=role,p=self:PlayerScore(name,realm)}
   end
  end
 end
 table.sort(members,function(a,b)
  local x,y=ROLE_ORDER[a.role] or 3,ROLE_ORDER[b.role] or 3
  if x~=y then return x<y end
  return a.name<b.name
 end)
 return members
end
-- The spec shown for a member: the one they are in (yours, or an inspected member's), else
-- their best-scoring spec on the leaderboard. Returns the name and its leaderboard rank.
local function memberSpec(m)
 local id
 if m.unit=='player' then local i=GetSpecialization and GetSpecialization();id=i and GetSpecializationInfo(i)
 elseif GetInspectSpecialization then id=GetInspectSpecialization(m.unit) end
 local name=id and id>0 and GetSpecializationInfoByID and select(2,GetSpecializationInfoByID(id))
 local specs=m.p and m.p.specs or {}
 if not name then
  local top;for spec,entry in pairs(specs) do if not top or entry.score>specs[top].score then top=spec end end
  name=top
 end
 return name,name and specs[name] and specs[name].rank
end

function H:CreatePartyFrame()
 local f=CreateFrame('Frame','LegionKeyHistoryPartyFrame',UIParent);self.partyFrame=f
 f:SetSize(LABEL_W+5*COL_W+48,560);f:SetPoint('CENTER');f:SetScale(self.frame and self.frame:GetScale() or 1);f:SetClampedToScreen(true)
 f:SetBackdrop(backdrop);f:SetBackdropColor(.025,.035,.05,.97);f:SetBackdropBorderColor(.17,.30,.34);f:EnableMouse(true)
 f:SetMovable(true);f:RegisterForDrag('LeftButton');f:SetScript('OnDragStart',f.StartMoving);f:SetScript('OnDragStop',f.StopMovingOrSizing)
 table.insert(UISpecialFrames,'LegionKeyHistoryPartyFrame')
 text(f,23,22,-18,400,'|cff4adbc8MYTHIC+|r  Your group')
 button(f,'X',24,-22,-20,function() f:Hide() end)
 f.status=text(f,11,24,-51,LABEL_W+5*COL_W)
 f.heads,f.subs={},{}
 for k=1,5 do
  local h=CreateFrame('Button',nil,f);h:SetSize(COL_W-8,78);h:SetBackdrop(backdrop);h:SetBackdropColor(.06,.085,.11,1);h:SetBackdropBorderColor(.16,.20,.25)
  h:SetHighlightTexture('Interface\\Buttons\\ButtonHilight-Square','ADD')
  h.name=text(h,14,8,-8,COL_W-24);h.spec=text(h,10,8,-27,COL_W-24);h.score=text(h,17,8,-46,COL_W-24);h.rank=text(h,11,8,-50,COL_W-24);h.rank:SetJustifyH('RIGHT')
  -- Hover: their full score tooltip. Click: their runs from the leaderboard file.
  h:SetScript('OnEnter',function(s)
   if not s.member then return end
   GameTooltip:SetOwner(s,'ANCHOR_BOTTOMRIGHT');GameTooltip:SetText(s.member.name)
   H:AddScoreTooltip(GameTooltip,s.member.name,s.member.realm);if H.OpaqueTooltip then H:OpaqueTooltip(GameTooltip) end
  end)
  h:SetScript('OnLeave',function() GameTooltip:Hide() end)
  h:SetScript('OnClick',function(s) local row=s.member and s.member.p and (s.member.p.row or (not s.member.p.partial and s.member.p.rank));if row then H:OpenPlayerRuns(row) end end)
  f.heads[k]=h
  f.subs[k]={text(f,10,0,SUB_Y,70),text(f,10,0,SUB_Y,70)}
 end
 f.lines={}
 local dungeons=(LegionKeyHistoryLeaderboard or {}).dungeons or {}
 local labels={'Timed +10-14','Timed +15-19','Timed +20+'}
 for i=1,#dungeons+#labels do
  local extra=i>#dungeons
  local r=CreateFrame('Frame',nil,f);r:SetHeight(ROW_H-2);r:SetPoint('TOPLEFT',16,ROWS_Y-(i-1)*ROW_H-(extra and 10 or 0));r:SetPoint('RIGHT',-16,0)
  r:SetBackdrop(backdrop);r:SetBackdropColor(.05,.07,.09,i%2==0 and 1 or .55);r:SetBackdropBorderColor(0,0,0,0)
  local map=not extra and ((LegionKeyHistoryLeaderboard or {}).historyMaps or {})[i]
  if map and map.mapID then local icon=r:CreateTexture(nil,'ARTWORK');icon:SetSize(20,20);icon:SetPoint('LEFT',4,0);icon:SetTexCoord(.07,.93,.07,.93);icon:SetTexture(H:DungeonIcon(map.mapID)) end
  r.label=text(r,12,extra and 8 or 30,-6,LABEL_W-34,extra and labels[i-#dungeons] or dungeons[i].short)
  if not extra then
   r:EnableMouse(true);r:SetScript('OnEnter',function(s) GameTooltip:SetOwner(s,'ANCHOR_LEFT');GameTooltip:SetText(dungeons[i].name);GameTooltip:Show() end)
   r:SetScript('OnLeave',function() GameTooltip:Hide() end)
  end
  r.cells={}
  for k=1,5 do
   local top=r:CreateTexture(nil,'BORDER');top:SetColorTexture(.29,.86,.78,.16)
   r.cells[k]={top=top,text(r,12,0,-6,70),text(r,12,0,-6,70)}
  end
  f.lines[i]=r
 end
 f.hint=text(f,10,24,-524,LABEL_W+5*COL_W,'|cff8899a0Point at a name for the full tooltip; click it for their runs. Updates when the group changes.|r')
 f:SetScript('OnEvent',function() if f:IsShown() then H:RefreshParty() end end)
 f:RegisterEvent('GROUP_ROSTER_UPDATE');f:RegisterEvent('PLAYER_SPECIALIZATION_CHANGED');f:RegisterEvent('INSPECT_READY')
end

function H:RefreshParty()
 local f=self.partyFrame;if not f then return end
 local data=LegionKeyHistoryLeaderboard or {};local dungeons=data.dungeons or {}
 local members=self:PartyMembers();local n=#members
 local split=self.settings.tipWeekSplit
 f:SetWidth(LABEL_W+math.max(n,2)*COL_W+48)
 -- Status: the group's average score, and how old the leaderboard file is.
 local total,known=0,0
 for _,m in ipairs(members) do if m.p then total=total+m.p.score;known=known+1 end end
 f.status:SetText((n==1 and 'Not in a group: just you.' or (n..' players'))..(known>0 and string.format('  |  average score %s',self:FormatScore(total/known,true)) or '')
  ..(data.downloaded and ('  |  leaderboard file '..data.downloaded..self:DownloadedAgo(data.downloaded)) or ''))
 local fort=select(3,C_ChallengeMode and C_ChallengeMode.GetAffixInfo and C_ChallengeMode.GetAffixInfo(10) or nil) or 'Interface\\Icons\\ability_toughness'
 local tyr=select(3,C_ChallengeMode and C_ChallengeMode.GetAffixInfo and C_ChallengeMode.GetAffixInfo(9) or nil) or 'Interface\\Icons\\achievement_boss_archaedas'
 for k,h in ipairs(f.heads) do
  local m=members[k];h:SetShown(m~=nil);h.member=m
  for _,s in ipairs(f.subs[k]) do s:SetShown(m~=nil) end
  if m then
   local x=24+LABEL_W+(k-1)*COL_W
   h:ClearAllPoints();h:SetPoint('TOPLEFT',x,HEAD_Y)
   local c=RAID_CLASS_COLORS and RAID_CLASS_COLORS[m.class]
   h.name:SetText(m.name);h.name:SetTextColor(c and c.r or .85,c and c.g or .9,c and c.b or .93)
   local spec,specRank=memberSpec(m)
   h.spec:SetText((spec or '')..(specRank and ('  #'..specRank) or ''))
   if m.p then
    local r,g,b=self:ScoreColor(m.p.score)
    h.score:SetText(string.format('%.1f',m.p.score));h.score:SetTextColor(r,g,b)
    local rank=self:PlayerRank(m.p);h.rank:SetText(rank and ('#'..rank) or '')
   else
    h.score:SetText('--');h.score:SetTextColor(.5,.55,.6);h.rank:SetText('')
    h.spec:SetText('|cff8899a0Not in the leaderboard file|r')
   end
   -- Column heads: Fortified / Tyrannical icons, or key / score.
   local a,b=f.subs[k][1],f.subs[k][2]
   place(a,x,SUB_Y,70,'RIGHT');place(b,x+75,SUB_Y,70,'RIGHT')
   if split then a:SetText('|T'..fort..':14:14:0:0|t');b:SetText('|T'..tyr..':14:14:0:0|t')
   else a:SetText('|cff8899a0KEY|r');b:SetText('|cff8899a0SCORE|r') end
  end
 end
 -- Dungeon rows: each member's key there; the group's best is highlighted.
 for i,r in ipairs(f.lines) do
  local d=dungeons[i];local values={{},{}}
  for k,cell in ipairs(r.cells) do
   local m=members[k];cell[1]:SetShown(m~=nil);cell[2]:SetShown(m~=nil);cell.top:Hide()
   if m then
    local x=8+LABEL_W+(k-1)*COL_W
    place(cell[1],x,-6,70,'RIGHT');place(cell[2],x+75,-6,70,'RIGHT')
    local p=m.p
    if not d then
     -- Timed keys by level range.
     local counts=p and not p.partial and self:TimedCounts(p)
     local range=({'low','high','top'})[i-#dungeons]
     cell[1]:SetText(counts and tostring(counts[range]) or '|cff657080-|r');cell[2]:SetText('')
     values[1][k]=counts and counts[range] or 0
    elseif split then
     local w=p and p.weekBest and p.weekBest[d.id] or {};local ups=p and not p.partial and self:WeekUpgrades(p) or {}
     for s,week in ipairs({'fort','tyr'}) do
      local v=w[week];local run=ups[i] and ups[i][week]
      cell[s]:SetText(v and self:GoldKey(math.abs(v),run and run.level==math.abs(v) and run.upgrades or 0,v<0) or '|cff657080-|r')
      values[s][k]=v and v>0 and v or 0
     end
    else
     local b=p and p.best[d.id];local late=b and self:OverTime(i,b)
     cell[1]:SetText(b and self:GoldKey(b[2],self:KeyUpgrades(b[3],self:DungeonTimer(i)),late) or '|cff657080-|r')
     cell[2]:SetText(b and string.format(late and '|cff7a7a7a%.1f|r' or '%.1f',b[1]) or '')
     values[1][k]=b and b[1] or 0
    end
   end
  end
  -- Highlight the best of each column pair (both halves when they mean one value).
  for s=1,2 do
   local top=0;for k=1,n do top=math.max(top,values[s][k] or 0) end
   for k=1,n do
    if n>1 and top>0 and values[s][k]==top then
     local cell=r.cells[k];cell.top:ClearAllPoints()
     local x=8+LABEL_W+(k-1)*COL_W
     if split and d then cell.top:SetPoint('TOPLEFT',x+(s-1)*75+4,0);cell.top:SetSize(70,ROW_H-2)
     else cell.top:SetPoint('TOPLEFT',x+4,0);cell.top:SetSize(141,ROW_H-2) end
     cell.top:Show()
    end
   end
  end
 end
end
function H:OpenParty()
 if not self.partyFrame then self:CreatePartyFrame() end
 self.partyFrame:Show();self:RefreshParty();self:Front(self.partyFrame)
end
