local H=LegionKeyHistory
local PAGE_SIZE=8
function H:FontPath()
 local media=LibStub and LibStub('LibSharedMedia-3.0',true)
 if media and media.IsValid and media:IsValid('font','Expressway') then return media:Fetch('font','Expressway') end
 -- Without ElvUI's Expressway, use the narrow Arial that ships with every client: the layout is
 -- sized for a narrow font, and the default Friz Quadrata makes text overflow its columns.
 return 'Fonts\\ARIALN.TTF'
end
function H:ApplyFont(frame)
 if not frame then return end
 if frame.GetFont and frame.SetFont then
  local _,size,flags=frame:GetFont();if size then frame:SetFont(self:FontPath(),size,flags or '') end
 end
 if frame.GetRegions then for _,region in pairs({frame:GetRegions()}) do if region.GetFont and region.SetFont then self:ApplyFont(region) end end end
 if frame.GetChildren then for _,child in pairs({frame:GetChildren()}) do self:ApplyFont(child) end end
end
function H:Front(frame)
 if not frame then return end
 self:ApplyFont(frame)
 if not frame.lkhFrontHook then frame.lkhFrontHook=true;frame:HookScript('OnMouseDown',function() H:Front(frame) end) end
 local level=100
 for _,f in pairs({self.frame,self.hud,self.statsFrame,self.daysFrame,self.syncFrame,self.syncDebugFrame,self.leaderboardFrame}) do
  if f and f:IsShown() then level=math.max(level,f:GetFrameLevel()) end
 end
 frame:SetFrameStrata('FULLSCREEN_DIALOG');frame:SetFrameLevel(level+20)
end
function H:OpenJournal()
 if self.leaderboardFrame then self.leaderboardFrame:Hide() end
 if self.daysFrame then self.daysFrame:Hide() end
 if self.statsFrame then self.statsFrame:Hide() end
 self.frame:Show();self:Front(self.frame);self:Refresh()
end
function H:SetMinimapHidden(hidden)
 self.settings.minimapHidden=hidden and true or false
 if self.minimapButton then self.minimapButton:SetShown(not hidden) end
 if self.showIconButton then self.showIconButton:SetShown(hidden) end
end
function H:MinimapMenu()
 if not self.minimapMenu then self.minimapMenu=CreateFrame('Frame','LegionKeyHistoryMinimapMenu',UIParent,'UIDropDownMenuTemplate') end
 EasyMenu({
  {text='Stats',notCheckable=true,func=function() H:OpenJournal();H:OpenStats() end},
  {text='Days',notCheckable=true,func=function() H:OpenJournal();H:OpenStats();H:OpenDays() end},
  {text='Leaderboard',notCheckable=true,func=function() H:OpenLeaderboard() end},
  {text='Settings',notCheckable=true,func=function() H:OpenSettings() end},
  {text='Hide icon from minimap',notCheckable=true,func=function() H:SetMinimapHidden(true) end}
 },self.minimapMenu,'cursor',0,0,'MENU')
end
local bg={bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1}
local function text(parent,size,x,y,value)
 local t=parent:CreateFontString(nil,'OVERLAY','GameFontNormal');t:SetFont(H:FontPath(),size,'');t:SetPoint('TOPLEFT',x,y);t:SetTextColor(.85,.9,.93);t:SetText(value or '');t:SetJustifyH('LEFT');return t
end
local function button(parent,label,w,x,y,fn)
 local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate');b:SetSize(w,23);b:SetPoint('TOPLEFT',x,y);b:SetText(label);b:SetScript('OnClick',fn);return b
end
local function scopeButton(parent,x,y)
 local b=button(parent,H.accountView and 'View: Account' or 'View: Character',140,x,y,function() H:SetAccountView(not H.accountView) end)
 H.scopeButtons=H.scopeButtons or {};H.scopeButtons[#H.scopeButtons+1]=b
 return b
end
local function edit(parent,w,x,y)
 local e=CreateFrame('EditBox',nil,parent,'InputBoxTemplate');e:SetSize(w,22);e:SetPoint('TOPLEFT',x,y);e:SetAutoFocus(false);e:SetScript('OnEscapePressed',function(self) self:ClearFocus() end);return e
end
function H:PartyText(run)
 local names={};for _,m in ipairs(run.members or {}) do names[#names+1]=(m.name or '?'):match('^[^-]+') end;table.sort(names);return #names>0 and table.concat(names,', ') or 'Roster unavailable'
end
function H:ColoredPartyText(run)
 local members={};for _,m in ipairs(run.members or {}) do members[#members+1]=m end
 table.sort(members,function(a,b) return (a.name or '')<(b.name or '') end)
 local names={};for _,m in ipairs(members) do names[#names+1]=self:ColoredName(m,self.partyClasses) end
 return #names>0 and table.concat(names,', ') or 'Roster unavailable'
end
function H:FilteredRuns()
 local result={};local needle=(self.search:GetText() or ''):lower();local lo=tonumber(self.minLevel:GetText()) or 0;local hi=tonumber(self.maxLevel:GetText()) or 999
 for _,run in ipairs(self.db.runs) do
  self:ResolveTimer(run)
  local blob=(run.dungeon..' '..self:PartyText(run)..' '..self:AffixText(run)..' '..(run.date or '')):lower()
  local matches=true;for word in needle:gmatch('%S+') do if not blob:find(word,1,true) then matches=false;break end end
  if self:RunInScope(run) and run.status=='completed' and (not self.filterAffix or self:HasAffix(run,self.filterAffix)) and matches and (not self.filterDungeon or self.filterDungeon==run.mapID) and run.level>=lo and run.level<=hi then result[#result+1]=run end
 end
 table.sort(result,function(a,b)
  local av,bv
  if self.sort=='level' then av,bv=a.level,b.level
  elseif self.sort=='time' then av,bv=a.duration or math.huge,b.duration or math.huge
  else av,bv=a.endedAt or a.startedAt or 0,b.endedAt or b.startedAt or 0 end
  if av~=bv then if self.sortAscending then return av<bv else return av>bv end end
  local at,bt=a.endedAt or a.startedAt or 0,b.endedAt or b.startedAt or 0
  if at~=bt then return at>bt end
  return tostring(a.id)<tostring(b.id)
 end)
 return result
end
function H:ShowDetails(run)
 -- Details remain available in the row tooltip.
end

function H:Refresh()
 if not self.frame then return end
 self.partyClasses={}
 for _,r in ipairs(self.db.runs) do for _,m in ipairs(r.members or {}) do if m.guid and m.class then self.partyClasses[m.guid]=m.class end end end
 if self.BackfillImportedRoles then self:BackfillImportedRoles() end
 self.partyHeader:SetShown(not self.filterDungeon)
 local list=self:FilteredRuns();local pages=math.max(1,math.ceil(#list/PAGE_SIZE));self.page=math.min(self.page or 1,pages)
 self.summary:SetText((self.accountView and 'Account' or (UnitName('player') or 'Character'))..'  |  '..#list..' completed runs  |  '..(self.filterDungeon and self.selectedDungeonName or 'All Legion dungeons')..(self.filterAffix and (' / '..self.affixes[self.filterAffix]) or ''))
 for key,header in pairs(self.sortHeaders) do
  local active=(self.sort or 'date')==key
  header.label:SetText(header.title..(active and (self.sortAscending and ' ^' or ' v') or ''))
  header.label:SetTextColor(active and .29 or .85,active and .86 or .9,active and .78 or .93)
 end

 for i,row in ipairs(self.rows) do
  local run=list[(self.page-1)*PAGE_SIZE+i];row.run=run
  if run then
   local roles={tank={},healer={},dps={}}
   local members={};for _,m in ipairs(run.members or {}) do members[#members+1]=m end
   table.sort(members,function(a,b) return (a.name or '')<(b.name or '') end)
   for _,m in ipairs(members) do local list=roles[self:MemberRole(m)];list[#list+1]=self:ColoredName(m,self.partyClasses) end
   local values={run.dungeon,self:RunKeyText(run),self:Clock(run.duration),#(run.affixes or {})==0 and 'Unknown' or '',
    table.concat(roles.tank,'  '),table.concat(roles.healer,'  '),table.concat(roles.dps,'  '),(run.date or '?'):sub(1,16)}
   for _,affixButton in ipairs(row.affixButtons) do affixButton:Hide() end
   for slot,affixID in ipairs(run.affixes or {}) do
    local affixButton=row.affixButtons[slot]
    if affixButton then
     local name,description,texture
     if C_ChallengeMode.GetAffixInfo then name,description,texture=C_ChallengeMode.GetAffixInfo(affixID) end
     affixButton.title=name or H.affixes[affixID] or ('Affix '..affixID);affixButton.description=description
     affixButton.image:SetTexture(texture or 'Interface\\Icons\\INV_Misc_QuestionMark');affixButton:Show()
    end
   end
   if #(run.affixes or {})==0 then row.cols[4]:SetText('Unknown') end
   row.icon:SetTexture(self:DungeonIcon(run.mapID))
   row.icon:SetShown(not self.filterDungeon);row.cols[1]:SetShown(not self.filterDungeon)
   row:SetBackdropBorderColor(self.selected==run and .29 or .10,self.selected==run and .86 or .15,self.selected==run and .78 or .20)
   for j,v in ipairs(values) do row.cols[j]:SetText(v) end
   row:Show()
  else row:Hide() end
 end
 self.empty:SetShown(#list==0)
 local visibleIcons=0
 for _,b in ipairs(self.dungeonButtons) do
  local visible=not H.laterDungeons[b.mapID] or H.settings.showLaterDungeons
  b:SetShown(not not visible)
  if visible then b:ClearAllPoints();b:SetPoint('TOPLEFT',22+visibleIcons*71,-76);visibleIcons=visibleIcons+1 end
  b:SetBackdropBorderColor(self.filterDungeon==b.mapID and .29 or .16,self.filterDungeon==b.mapID and .86 or .20,self.filterDungeon==b.mapID and .78 or .25) end
 self:RefreshHUD()
 if self.statsFrame and self.statsFrame:IsShown() then self:RefreshStats() end
end
function H:AttachHUD()
 if self.attached or not PVEFrame or not self.hud then return end
 self.attached=true
 self.hud:ClearAllPoints();self.hud:SetPoint('TOPLEFT',PVEFrame,'TOPRIGHT',8,0)
 PVEFrame:HookScript('OnShow',function() H:RefreshHUD() end)
 PVEFrame:HookScript('OnHide',function() H.hud:Hide() end)
end
-- Places the Personal Bests rank columns that are switched on, left to right after TOTAL IO.
function H:LayoutHUDColumns()
 local x=92
 for _,c in ipairs(self.hudColumns or {}) do
  local shown=self.settings[c.setting]~=false
  c.label:SetShown(shown);c.value:SetShown(shown)
  if shown then
   c.label:ClearAllPoints();c.label:SetPoint('TOPLEFT',x,-62)
   c.value:ClearAllPoints()
   if c.value==self.hudRoleRank then
    self.hudRoleIcon:ClearAllPoints();self.hudRoleIcon:SetPoint('TOPLEFT',x,-76);c.value:SetPoint('TOPLEFT',x+20,-78)
   else
    c.value:SetPoint('TOPLEFT',x,-78)
   end
   x=x+c.width
  end
 end
end
function H:RefreshHUD()
 if not self.hud then return end
 self:AttachHUD()
 self:LayoutHUDColumns()
 local mode=self.settings.bestMode or 'timed'
 if self.hudScore and self.PersonalScore then
  self.hudScore:SetText(string.format('|cff4adbc8%.1f IO|r',self:PersonalScore()))
  local p=self:PlayerScore(UnitName('player'))
  local overall=self:PlayerRank(p)
  self.hudOverallRank:SetText(overall and ('#'..overall) or '--')
  local specIndex=GetSpecialization and GetSpecialization()
  local specName=specIndex and GetSpecializationInfo and select(2,GetSpecializationInfo(specIndex))
  local spec=p and p.specs and p.specs[specName]
  self.hudSpecRank:SetText((specName or 'Spec')..' '..(spec and spec.rank and ('#'..spec.rank) or '--'))
  local className,classToken=UnitClass('player')
  local c=RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
  self.hudClassRank:SetText((className or 'Class')..' '..(p and p.classRank and ('#'..p.classRank) or '--'))
  self.hudClassRank:SetTextColor(c and c.r or .85,c and c.g or .9,c and c.b or .93)
  local role=specIndex and GetSpecializationRole and GetSpecializationRole(specIndex)
  local key=role=='DAMAGER' and 'dps' or role and role:lower()
  local entry=p and p.roles and p.roles[key]
  self.hudRoleRank:SetText(entry and ('#'..entry.rank) or '--')
  local atlas=role=='TANK' and 'groupfinder-icon-role-large-tank' or role=='HEALER' and 'groupfinder-icon-role-large-heal' or 'groupfinder-icon-role-large-dps'
  self.hudRoleIcon:SetAtlas(atlas);self.hudRoleIcon:SetShown(role~=nil and self.settings.hudRole)

 end
 self.hudModeLabel:SetText((mode=='timed' and 'BEST TIMED' or 'HIGHEST COMPLETED')..(self.accountView and ' | ACCOUNT' or ' | CHARACTER'))
 self.hudToggle.texture:SetTexture(mode=='timed' and 'Interface\\Icons\\INV_Misc_PocketWatch_01' or 'Interface\\Icons\\Achievement_ChallengeMode_Gold')
 local current={}
 if C_ChallengeMode.GetCurrentAffixes then
  local ok,affixes=pcall(C_ChallengeMode.GetCurrentAffixes)
  if ok and type(affixes)=='table' then for _,a in ipairs(affixes) do current[type(a)=='table' and a.id or a]=true end end
 end
 for affix,label in pairs(self.affixHeaders) do label:SetTextColor(current[affix] and .29 or .7,current[affix] and .86 or .77,current[affix] and .78 or .82) end
 local best={[10]=self:BestRuns(mode,10),[9]=self:BestRuns(mode,9)}
 local visibleRows=0
 for i,d in ipairs(self.dungeons) do
  local row=self.hudRows[i];local visible=not self.laterDungeons[d[1]] or self.settings.showLaterDungeons
  row:SetShown(not not visible)
  if visible then row:ClearAllPoints();row:SetPoint('TOPLEFT',12,-132-visibleRows*37);visibleRows=visibleRows+1 end
  for _,affix in ipairs({10,9}) do
   local cell=self.hudRows[i].cells[affix];local run=best[affix][d[1]];cell.run=run
   if run then
    cell.top:SetText(self:RunKeyText(run))
    cell.bottom:SetText(self:Clock(run.duration)..(run.timed==false and '  Over' or run.timed==nil and '  ?' or ''))
   else cell.top:SetText('|cff657080--|r');cell.bottom:SetText('') end
  end
 end
 self.hud:SetHeight(144+visibleRows*37)
 self.hud:SetShown(self.settings.hud and PVEFrame and PVEFrame:IsShown() or false)
end
local function icon(parent,texture,size,x,y)
 local t=parent:CreateTexture(nil,'ARTWORK');t:SetSize(size,size);t:SetPoint('TOPLEFT',x,y);t:SetTexture(texture);t:SetTexCoord(.08,.92,.08,.92);return t
end
local function panel(parent,w,h,x,y)
 local f=CreateFrame('Frame',nil,parent);f:SetSize(w,h);f:SetPoint('TOPLEFT',x,y);f:SetBackdrop(bg);f:SetBackdropColor(.06,.08,.105,1);f:SetBackdropBorderColor(.10,.15,.20);return f
end
function H:CreateUI()
 if self.frame then return end
 local f=CreateFrame('Frame','LegionKeyHistoryFrame',UIParent);self.frame=f
 f:SetSize(1040,560);f:SetPoint('CENTER');f:SetFrameStrata('DIALOG');f:SetBackdrop(bg);f:SetBackdropColor(.025,.035,.05,1);f:SetBackdropBorderColor(.17,.30,.34)
 f:SetScale(math.min(1,(UIParent:GetHeight()-60)/560,(UIParent:GetWidth()-40)/1040));f:SetClampedToScreen(true)
 f:EnableMouse(true);f:SetMovable(true);f:RegisterForDrag('LeftButton');f:SetScript('OnDragStart',f.StartMoving);f:SetScript('OnDragStop',f.StopMovingOrSizing)
 f:HookScript('OnShow',function() H:Front(f) end);f:HookScript('OnMouseDown',function() H:Front(f) end)
 table.insert(UISpecialFrames,'LegionKeyHistoryFrame');f:Hide()
 text(f,23,22,-18,'|cff4adbc8MYTHIC+|r  Your completed runs');self.summary=text(f,11,23,-49)
 scopeButton(f,790,-47)
 button(f,'X',24,994,-20,function() f:Hide() end)
 -- Import from file, the minimap icon and Personal Bests live on the settings page.
 button(f,'Leaderboard',105,581,-20,function() H:OpenLeaderboard() end)
 button(f,'Sync',65,698,-20,function() H:OpenSync() end)
 button(f,'Stats',85,775,-20,function() H:OpenStats() end)
 self.settingsButton=button(f,'Settings',95,872,-20,function() H:OpenSettings() end)
 self.dungeonButtons={}
 local abbreviations={'BRH','COEN','COS','DHT','EOA','HOV','MOS','NL','LOWR','UPPR','SEAT','ARC','VOTW'}
 for i=0,#self.dungeons do
  local d=self.dungeons[i];local mapID=d and d[1] or nil;local name=d and d[2] or 'All Legion dungeons'
  local b=CreateFrame('Button',nil,f);b:SetSize(64,66);b:SetPoint('TOPLEFT',22+i*71,-76);b:SetBackdrop(bg);b:SetBackdropColor(.06,.085,.11,1)
  b.mapID=mapID
  icon(b,d and self:DungeonIcon(mapID) or 'Interface\\Icons\\INV_Misc_Map_01',42,11,-5)
  local label=text(b,9,0,-51,d and abbreviations[i] or 'ALL');label:SetWidth(64);label:SetJustifyH('CENTER')
  b:SetHighlightTexture('Interface\\Buttons\\ButtonHilight-Square','ADD')
  b:SetScript('OnClick',function() H.filterDungeon=mapID;H.filterAffix=nil;H.selectedDungeonName=name;H.selected=nil;H:ShowDetails();H.page=1;H:Refresh() end)
  b:SetScript('OnEnter',function(self) GameTooltip:SetOwner(self,'ANCHOR_TOP');GameTooltip:SetText(name);GameTooltip:AddLine('Click to filter completed runs',.6,.8,.8);GameTooltip:Show() end)
  b:SetScript('OnLeave',function() GameTooltip:Hide() end);self.dungeonButtons[#self.dungeonButtons+1]=b
 end
 text(f,10,24,-154,'FIND A PLAYER, AFFIX OR DATE');self.search=edit(f,475,27,-171)
 text(f,10,533,-154,'KEY LEVEL');self.minLevel=edit(f,45,538,-171);self.maxLevel=edit(f,45,607,-171);text(f,11,590,-175,'-')
 button(f,'Clear',65,675,-169,function() H.search:SetText('');H.minLevel:SetText('');H.maxLevel:SetText('');H.filterDungeon=nil;H.filterAffix=nil;H.page=1;H:Refresh() end)
 text(f,10,826,-178,'Click a column to sort')
 -- Same columns as the website's run list: key with stars, then tank / healer / DPS.
 local xs={46,206,282,350,452,572,692,862};local widths={156,72,64,98,118,118,166,130};local headers={'DUNGEON','KEY','TIME','AFFIXES','TANK','HEALER','DPS','DATE'}
 self.sortHeaders={}
 for i,v in ipairs(headers) do
  local key=i==2 and 'level' or i==3 and 'time' or i==8 and 'date' or nil
  if key then
   local h=CreateFrame('Button',nil,f);h:SetSize(widths[i],23);h:SetPoint('TOPLEFT',22+xs[i],-200);h.label=text(h,10,0,-6,v);h.title=v
   h:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight','ADD')
   h:SetScript('OnClick',function()
    if (H.sort or 'date')==key then H.sortAscending=not H.sortAscending else H.sort=key;H.sortAscending=key=='time' end
    H.page=1;H:Refresh()
   end);self.sortHeaders[key]=h
  else local label=text(f,10,22+xs[i],-206,v);if i==1 then self.partyHeader=label end end
 end
 self.rows={}
 for i=1,PAGE_SIZE do
  local row=CreateFrame('Button',nil,f);row:SetSize(996,36);row:SetPoint('TOPLEFT',22,-223-(i-1)*38);row:SetBackdrop(bg);row:SetBackdropColor(.06,.085,.11,1);row:SetBackdropBorderColor(.10,.15,.20)
  row:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight','ADD');row.cols={};row.icon=icon(row,nil,28,4,-4)
  for j,x in ipairs(xs) do local col=text(row,j==2 and 15 or 11,x,-11);col:SetWidth(widths[j]);col:SetHeight(18);row.cols[j]=col end
  row.affixButtons={}
  for slot=1,8 do
   local affixButton=CreateFrame('Button',nil,row);affixButton:SetSize(26,26);affixButton:SetPoint('TOPLEFT',350+(slot-1)*30,-5)
   affixButton.image=icon(affixButton,nil,24,1,-1)
   affixButton:SetScript('OnEnter',function(self) GameTooltip:SetOwner(self,'ANCHOR_TOP');GameTooltip:SetText(self.title or 'Affix');if self.description then GameTooltip:AddLine(self.description,1,1,1,true) end;GameTooltip:Show() end)
   affixButton:SetScript('OnLeave',function() GameTooltip:Hide() end)
   affixButton:SetScript('OnClick',function() if row.run then H.selected=row.run;H:ShowDetails(row.run);H:Refresh() end end)
   row.affixButtons[slot]=affixButton
  end
  row:SetScript('OnClick',function(self) H.selected=self.run;H:ShowDetails(self.run);H:Refresh() end)
  row:SetScript('OnEnter',function(self) if self.run then GameTooltip:SetOwner(self,'ANCHOR_CURSOR');GameTooltip:SetText(self.run.dungeon..' +'..self.run.level);GameTooltip:AddLine(H:ColoredPartyText(self.run),1,1,1,true);GameTooltip:AddLine(H:AffixText(self.run),.7,.8,.9,true);GameTooltip:AddLine('Keystone upgrade: '..H:UpgradeText(self.run),1,1,1);GameTooltip:Show() end end)
  row:SetScript('OnLeave',function() GameTooltip:Hide() end);self.rows[i]=row
 end
 self.empty=text(f,14,160,-345,'No completed runs match these filters. Try clearing the search or selecting ALL.')
 button(f,'<',30,943,-528,function() H.page=math.max(1,(H.page or 1)-1);H:Refresh() end)
 button(f,'>',30,976,-528,function() H.page=(H.page or 1)+1;H:Refresh() end)
 f:EnableMouseWheel(true);f:SetScript('OnMouseWheel',function(_,delta) H.page=math.max(1,(H.page or 1)-delta);H:Refresh() end)
 local hud=CreateFrame('Frame','LegionKeyHistoryHUD',UIParent);self.hud=hud;hud:SetSize(424,590);hud:SetFrameStrata('DIALOG');hud:SetBackdrop(bg);hud:SetBackdropColor(.025,.035,.05,1);hud:SetBackdropBorderColor(.17,.30,.34);hud:SetClampedToScreen(true);hud:Hide()
 hud:EnableMouse(true);hud:HookScript('OnMouseDown',function() H:Front(hud) end)
 text(hud,17,14,-15,'|cff4adbc8PERSONAL BESTS|r');self.hudModeLabel=text(hud,10,14,-40)
 text(hud,9,14,-62,'TOTAL IO')
 self.hudScore=text(hud,13,14,-78);self.hudScore:SetWidth(76)
 -- Rank columns after TOTAL IO; LayoutHUDColumns places the ones switched on in settings.
 self.hudColumns={}
 local function column(setting,label,width)
  local c={setting=setting,width=width,label=text(hud,9,0,-62,label),value=text(hud,11,0,-78)}
  c.value:SetWidth(width-2);self.hudColumns[#self.hudColumns+1]=c;return c.value
 end
 self.hudOverallRank=column('hudOverall','OVERALL',54)
 self.hudSpecRank=column('hudSpec','SPEC RANK',104)
 self.hudClassRank=column('hudClass','CLASS RANK',94)
 self.hudRoleRank=column('hudRole','ROLE RANK',66)
 self.hudRoleIcon=hud:CreateTexture(nil,'ARTWORK');self.hudRoleIcon:SetSize(16,16)
 self.hudJournalButton=button(hud,'Journal',65,277,-13,function() H:OpenJournal() end)
 local toggle=CreateFrame('Button',nil,hud);self.hudToggle=toggle;toggle:SetSize(26,26);toggle:SetPoint('TOPLEFT',352,-12);toggle.texture=icon(toggle,nil,22,2,-2);toggle:SetHighlightTexture('Interface\\Buttons\\ButtonHilight-Square','ADD')
 toggle:SetScript('OnClick',function() H.settings.bestMode=H.settings.bestMode=='completed' and 'timed' or 'completed';H:RefreshHUD();GameTooltip:Hide() end)
 toggle:SetScript('OnEnter',function(self) GameTooltip:SetOwner(self,'ANCHOR_TOP');GameTooltip:SetText(H.settings.bestMode=='completed' and 'Highest completed' or 'Best timed');GameTooltip:AddLine('Click to switch timed / completed records.',1,1,1,true);GameTooltip:AddLine('Highest key first; timed wins ties, then fastest time.',.7,.8,.9,true);GameTooltip:Show() end)
 toggle:SetScript('OnLeave',function() GameTooltip:Hide() end)
 button(hud,'x',24,386,-13,function() H.settings.hud=false;hud:Hide() end)
 text(hud,10,14,-111,'DUNGEON')
 self.affixHeaders={}
 for i,affix in ipairs({10,9}) do
  local texture=affix==10 and 'Interface\\Icons\\Ability_Toughness' or 'Interface\\Icons\\Achievement_Boss_Archimonde'
  if C_ChallengeMode.GetAffixInfo then local _,_,t=C_ChallengeMode.GetAffixInfo(affix);texture=t or texture end
  icon(hud,texture,16,207+(i-1)*103,-106);self.affixHeaders[affix]=text(hud,10,227+(i-1)*103,-111,affix==10 and 'FORT' or 'TYRA')
 end
 self.hudRows={}
 for i,d in ipairs(self.dungeons) do
  local row=panel(hud,400,36,12,-132-(i-1)*37);row.cells={}
  icon(row,self:DungeonIcon(d[1]),28,4,-4);row.label=text(row,10,39,-11);row.label:SetWidth(151);row.label:SetHeight(15);row.label:SetText(d[2])
  for column,affix in ipairs({10,9}) do
   local cell=CreateFrame('Button',nil,row);cell:SetSize(100,36);cell:SetPoint('TOPLEFT',194+(column-1)*103,0)
   cell.top=text(cell,13,5,-3);cell.bottom=text(cell,9,5,-21);cell.bottom:SetTextColor(.65,.73,.80)
   cell:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight','ADD')
   cell:SetScript('OnClick',function(self) H:OpenJournal();H.filterDungeon=d[1];H.filterAffix=affix;H.selectedDungeonName=d[2];H.search:SetText('');H.minLevel:SetText('');H.maxLevel:SetText('');H.page=1;H.selected=self.run;H:ShowDetails(self.run);H:Refresh() end)
   cell:SetScript('OnEnter',function(self)
    GameTooltip:SetOwner(self,'ANCHOR_LEFT');GameTooltip:SetText(d[2]..' - '..H.affixes[affix])
    if self.run then
     GameTooltip:AddLine('Key '..self.run.level..'  '..H:CompletionBadge(self.run),1,1,1)
     GameTooltip:AddLine(H:Clock(self.run.duration)..'  |  '..(self.run.date or ''),.8,.85,.9)
     if H.RunScore then
      local score=H:RunScore(self.run)
      if score then
       GameTooltip:AddLine(string.format('Run score: %.1f IO (unofficial)',score),.29,.86,.78)
       local _,bests=H:PersonalScore()
       local ids={[197]='eoa',[198]='dht',[199]='brh',[200]='hov',[206]='nl',[207]='votw',[208]='mos',[209]='arc',[210]='cos'}
       local best=bests[ids[d[1]]] or 0
       if score<best then GameTooltip:AddLine(string.format('Best for this dungeon: %.1f IO. This run adds no IO.',best),1,.8,.4,true)
       else GameTooltip:AddLine('This is a best-scoring run for this dungeon.',.29,.86,.78,true) end
       GameTooltip:AddLine('Fortified and Tyrannical share one best score.',.7,.8,.85,true)
      end
     end
     GameTooltip:AddLine(H:AffixText(self.run),.8,.85,.9,true);GameTooltip:AddLine(H:ColoredPartyText(self.run),1,1,1,true)
    else GameTooltip:AddLine('No matching recorded run.',.7,.7,.7) end
    local other=H:BestRuns(H.settings.bestMode=='completed' and 'timed' or 'completed',affix)[d[1]]
    if other then GameTooltip:AddLine((H.settings.bestMode=='completed' and 'Best timed: ' or 'Highest completed: ')..other.level..'  '..H:Clock(other.duration)..'  '..H:CompletionBadge(other),.8,.85,.9,true) end
    GameTooltip:AddLine('Click to browse this dungeon and affix.',.4,.8,.75);GameTooltip:Show()
   end)
   cell:SetScript('OnLeave',function() GameTooltip:Hide() end);row.cells[affix]=cell
  end
  self.hudRows[i]=row
 end
 local imp=CreateFrame('Frame',nil,f);self.importFrame=imp;imp:SetSize(540,215);imp:SetPoint('CENTER');imp:SetFrameStrata('FULLSCREEN_DIALOG');imp:SetBackdrop(bg);imp:SetBackdropColor(.045,.065,.09,1);imp:Hide();imp:EnableMouse(true)
 text(imp,17,18,-18,'Import from file')
 local desc=text(imp,12,18,-53,'Imports available runs for your current character from the downloaded snapshot. Existing runs are skipped. Refresh the file outside WoW, then /reload to load it.');desc:SetWidth(505);desc:SetHeight(125)
 button(imp,'Close',70,450,-180,function() imp:Hide() end)
 for _,e in ipairs({self.search,self.minLevel,self.maxLevel}) do e:SetScript('OnTextChanged',function() H.page=1;H:Refresh() end) end
 self:CreateMinimapButton();self:ApplyFont(self.frame);self:ApplyFont(self.hud)
 self:Refresh()
end
local attach=CreateFrame('Frame');attach:RegisterEvent('ADDON_LOADED');attach:SetScript('OnEvent',function() if H.hud then H:AttachHUD() end end)

function H:OpenStats()
 if not self.statsFrame then
  local f=CreateFrame('Frame','LegionKeyHistoryStats',self.frame);self.statsFrame=f
  f:SetSize(1040,650);f:SetPoint('CENTER',self.frame,'CENTER');f:SetFrameStrata('FULLSCREEN_DIALOG');f:SetBackdrop(bg);f:SetBackdropColor(.025,.035,.05,1);f:SetBackdropBorderColor(.17,.30,.34);f:EnableMouse(true)
  text(f,24,24,-22,'|cff4adbc8YOUR KEY STORIES|r');text(f,11,25,-54,'Completed runs in the selected view, from your recorded history');scopeButton(f,640,-22)
  button(f,'Days',85,800,-22,function() H:OpenDays() end)
  button(f,'Back to runs',115,900,-22,function() f:Hide() end)
  self.statsCards={}
  local labels={'KEYS COMPLETED','TIMED','THREE-CHEST RUNS','HIGHEST COMPLETED','DAYS WITH KEYS','RECORDED KEY TIME'}
  for i,label in ipairs(labels) do
   local card=panel(f,157,76,24+(i-1)*167,-86)
   local value=text(card,25,12,-11);text(card,9,12,-51,label);self.statsCards[i]=value
  end
  text(f,16,25,-187,'Your dungeon crew');text(f,16,548,-187,'Favourite dungeons')
  text(f,10,25,-216,'PLAYER');text(f,10,295,-216,'KEYS');text(f,10,359,-216,'TIMED');text(f,10,435,-216,'BEST')
  text(f,10,548,-216,'DUNGEON');text(f,10,829,-216,'KEYS');text(f,10,889,-216,'TIMED');text(f,10,963,-216,'BEST')
  self.statsPeople={};self.statsDungeons={}
  for i=1,11 do
   local row=panel(f,482,28,24,-237-(i-1)*30);row.name=text(row,12,8,-7);row.name:SetWidth(255);row.name:SetHeight(16)
   row.count=text(row,12,277,-7);row.timed=text(row,12,342,-7);row.highest=text(row,12,414,-7);self.statsPeople[i]=row
   local d=panel(f,468,28,548,-237-(i-1)*30);d.icon=icon(d,nil,22,4,-3);d.name=text(d,10,33,-8);d.name:SetWidth(241);d.name:SetHeight(15)
   d.count=text(d,12,286,-7);d.timed=text(d,12,348,-7);d.highest=text(d,12,418,-7);self.statsDungeons[i]=d
  end
  self.statsPages=text(f,11,25,-588)
  button(f,'<',30,427,-579,function() H.statsPage=math.max(1,(H.statsPage or 1)-1);H:RefreshStats() end)
  button(f,'>',30,462,-579,function() H.statsPage=(H.statsPage or 1)+1;H:RefreshStats() end)
  self.statsDungeonPages=text(f,11,548,-588)
  button(f,'<',30,938,-579,function() H.statsDungeonPage=math.max(1,(H.statsDungeonPage or 1)-1);H:RefreshStats() end)
  button(f,'>',30,973,-579,function() H.statsDungeonPage=(H.statsDungeonPage or 1)+1;H:RefreshStats() end)
  text(f,10,25,-625,'Days = dates with recorded completions. Key time includes timer penalties; it is not total character /played.')
 end
 self.statsFrame:Show();self:Front(self.statsFrame);self:RefreshStats()
end
function H:RefreshStats()
 local stats=self:BuildStats();local hours=math.floor(stats.seconds/3600);local minutes=math.floor(stats.seconds%3600/60)
 local values={tostring(stats.total),stats.total>0 and string.format('%d (%d%%)',stats.timed,math.floor(stats.timed/stats.total*100+.5)) or '0',tostring(stats.triples),'+'..stats.highest,tostring(stats.days),hours..'h '..minutes..'m'}
 for i,v in ipairs(values) do self.statsCards[i]:SetText(v) end
 local pages=math.max(1,math.ceil(#stats.people/11));self.statsPage=math.min(self.statsPage or 1,pages)
 local dpages=math.max(1,math.ceil(#stats.dungeons/11));self.statsDungeonPage=math.min(self.statsDungeonPage or 1,dpages)
 self.statsPages:SetText(#stats.people..' teammates  /  Page '..self.statsPage..' of '..pages)
 self.statsDungeonPages:SetText(#stats.dungeons..' dungeons  /  Page '..self.statsDungeonPage..' of '..dpages)
 for i=1,11 do
  local row=self.statsPeople[i];local person=stats.people[(self.statsPage-1)*11+i]
  row:SetShown(person~=nil)
  if person then row.name:SetText(self:ColoredName(person,stats.classes));row.count:SetText(person.count);row.timed:SetText(person.timed);row.highest:SetText('+'..person.highest) end
  local d=self.statsDungeons[i];local dungeon=stats.dungeons[(self.statsDungeonPage-1)*11+i];d:SetShown(dungeon~=nil)
  if dungeon then d.icon:SetTexture(self:DungeonIcon(dungeon.mapID));d.name:SetText(dungeon.name);d.count:SetText(dungeon.count);d.timed:SetText(dungeon.timed);d.highest:SetText('+'..dungeon.highest) end
 end
end

function H:CreateMinimapButton()
 if self.minimapButton or not Minimap then return end
 local b=CreateFrame('Button','LegionKeyHistoryMinimapButton',Minimap);self.minimapButton=b
 b:SetSize(32,32);b:SetFrameStrata('MEDIUM');b:SetFrameLevel(Minimap:GetFrameLevel()+8)
 b:RegisterForClicks('LeftButtonUp','RightButtonUp');b:RegisterForDrag('LeftButton');b:EnableMouse(true)
 local image=b:CreateTexture(nil,'ARTWORK');image:SetTexture('Interface\\Icons\\Achievement_ChallengeMode_Gold');image:SetSize(20,20);image:SetPoint('CENTER');image:SetTexCoord(.08,.92,.08,.92)
 local border=b:CreateTexture(nil,'OVERLAY');border:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder');border:SetSize(54,54);border:SetPoint('TOPLEFT')
 b:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight','ADD')
 local function position()
  local angle=math.rad(H.settings.minimapAngle or 220);local x,y=math.cos(angle),math.sin(angle)
  if GetMinimapShape and GetMinimapShape()=='SQUARE' then local n=math.max(math.abs(x),math.abs(y));x=x/n;y=y/n end
  b:ClearAllPoints();b:SetPoint('CENTER',Minimap,'CENTER',x*(Minimap:GetWidth()/2+4),y*(Minimap:GetHeight()/2+4))
 end
 b:SetScript('OnClick',function(_,which)
  if b.wasDragged then b.wasDragged=nil;return end
  if which=='RightButton' then H:MinimapMenu()
  else H:OpenJournal() end
 end)
 b:SetScript('OnEnter',function(self) GameTooltip:SetOwner(self,'ANCHOR_LEFT');GameTooltip:SetText('Legion Key History');GameTooltip:AddLine('Left-click: open the journal',1,1,1);GameTooltip:AddLine('Right-click: Stats / Days / Leaderboard / Settings / hide icon',1,1,1);GameTooltip:AddLine('Drag: move around the minimap',.6,.8,.8);GameTooltip:Show() end)
 b:SetScript('OnLeave',function() GameTooltip:Hide() end)
 b:SetScript('OnDragStart',function(self)
  self.wasDragged=true;GameTooltip:Hide()
  self:SetScript('OnUpdate',function()
   local x,y=GetCursorPosition();local scale=Minimap:GetEffectiveScale();local cx,cy=Minimap:GetCenter()
   H.settings.minimapAngle=math.deg(math.atan2(y/scale-cy,x/scale-cx));position()
  end)
 end)
 b:SetScript('OnDragStop',function(self) self:SetScript('OnUpdate',nil);C_Timer.After(0,function() self.wasDragged=nil end) end)
 position();self:SetMinimapHidden(self.settings.minimapHidden)
end

function H:OpenDays()
 if not self.daysFrame then
  local f=CreateFrame('Frame',nil,self.statsFrame);self.daysFrame=f;f:SetAllPoints(self.statsFrame);f:SetFrameStrata('FULLSCREEN_DIALOG');f:SetFrameLevel(self.statsFrame:GetFrameLevel()+10);f:SetBackdrop(bg);f:SetBackdropColor(.025,.035,.05,1);f:EnableMouse(true)
  text(f,24,24,-22,'|cff4adbc8DAYS IN KEYS|r');self.daysSummary=text(f,11,25,-55)
  button(f,'Back to stats',115,900,-22,function() f:Hide() end)
  scopeButton(f,620,-22)
  self.chartToggle=button(f,'Chart: line',110,777,-22,function() H.settings.dayChart=H.settings.dayChart=='bar' and 'line' or 'bar';H:RefreshDays() end)
  button(f,'< Older',85,24,-83,function() H.dayWindow=(H.dayWindow or 0)+1;H.dayTablePage=1;H:RefreshDays() end)
  button(f,'Newer >',85,120,-83,function() H.dayWindow=math.max(0,(H.dayWindow or 0)-1);H.dayTablePage=1;H:RefreshDays() end)
  self.dayRange=text(f,12,230,-89)
  local graph=panel(f,984,227,28,-121);self.dayGraph=graph;self.dayMarks={};self.dayLines={};self.dayTicks={}
  for i=0,4 do
   local grid=graph:CreateTexture(nil,'BACKGROUND');grid:SetTexture('Interface\\Buttons\\WHITE8X8');grid:SetVertexColor(.15,.20,.25,.7);grid:SetSize(910,1);grid:SetPoint('BOTTOMLEFT',48,30+i*44)
   local label=text(graph,10,5,-(188-i*44));self.dayTicks[i+1]=label
  end
  for i=1,30 do
   local point=CreateFrame('Button',nil,graph);point.texture=point:CreateTexture(nil,'ARTWORK');point.texture:SetAllPoints(point);point.texture:SetTexture('Interface\\Buttons\\WHITE8X8');point.texture:SetVertexColor(.29,.86,.78,1)
   point:SetScript('OnEnter',function(self) if self.data then GameTooltip:SetOwner(self,'ANCHOR_TOP');GameTooltip:SetText(self.data.day);GameTooltip:AddLine(self.data.count..' completed / '..self.data.timed..' timed',1,1,1);if self.total then GameTooltip:AddLine(self.total..' total in this date range',.29,.86,.78) end;GameTooltip:Show() end end)
   point:SetScript('OnLeave',function() GameTooltip:Hide() end);self.dayMarks[i]=point
   local line=graph:CreateTexture(nil,'ARTWORK');line:SetTexture('Interface\\Buttons\\WHITE8X8');line:SetVertexColor(.29,.86,.78,.8);self.dayLines[i]=line
  end
  self.dayFirst=text(graph,10,48,-207);self.dayLast=text(graph,10,860,-207)
  local xs={0,275,450,640,825};local titles={'DATE','COMPLETED','TIMED','HIGHEST KEY','KEY TIME'}
  for i,t in ipairs(titles) do text(f,10,32+xs[i],-371,t) end
  self.dayRows={}
  for i=1,8 do
   local row=panel(f,976,24,32,-389-(i-1)*26);row.labels={}
   for j,x in ipairs(xs) do row.labels[j]=text(row,11,x+4,-6) end
   self.dayRows[i]=row
  end
  self.dayPageText=text(f,11,32,-614)
  button(f,'<',30,939,-608,function() H.dayTablePage=math.max(1,(H.dayTablePage or 1)-1);H:RefreshDays() end)
  button(f,'>',30,976,-608,function() H.dayTablePage=(H.dayTablePage or 1)+1;H:RefreshDays() end)
 end
 self.daysFrame:Show();self:Front(self.daysFrame);self:RefreshDays()
end
function H:RefreshDays()
 local days=self:DailyStats();local windows=math.max(1,math.ceil(#days/30));self.dayWindow=math.min(self.dayWindow or 0,windows-1)
 local last=#days-self.dayWindow*30;local first=math.max(1,last-29);local n=math.max(0,last-first+1)
 local maximum,total=1,0
 for i=first,last do maximum=math.max(maximum,days[i].count);total=total+days[i].count end
 local bar=self.settings.dayChart=='bar'
 if not bar then maximum=total end
 maximum=math.max(4,math.ceil(maximum/4)*4)
 self.chartToggle:SetText(bar and 'Chart: bars' or 'Chart: line')
 self.daysSummary:SetText((bar and 'Daily completions' or 'Cumulative completions, starting at zero')..'  |  '..total..' keys in this date range')
 self.dayRange:SetText(n>0 and (days[first].day..'  to  '..days[last].day) or 'No completed runs recorded')
 for i,label in ipairs(self.dayTicks) do label:SetText((i-1)*maximum/4) end
 for i=1,30 do self.dayMarks[i]:Hide() end
 for _,line in ipairs(self.dayLines) do line:Hide() end
 local previousX,previousY=48,30
 local cumulative,segment=0,0
 for slot=1,n do
  local d=days[first+slot-1];cumulative=cumulative+d.count
  local x=48+(bar and slot-.5 or slot)*910/math.max(n,1);local y=30+(bar and d.count or cumulative)/maximum*176
  local mark=self.dayMarks[slot];mark.data=d;mark.total=not bar and cumulative or nil;mark:ClearAllPoints()
  if bar then mark:SetSize(math.min(30,910/math.max(n,1)-5),math.max(2,y-30));mark:SetPoint('BOTTOM',self.dayGraph,'BOTTOMLEFT',x,30)
  else mark:SetSize(7,7);mark:SetPoint('CENTER',self.dayGraph,'BOTTOMLEFT',x,y) end
  mark:Show()
  if not bar and previousX then
   -- Draw a connected stroke with small filled rectangles. Rotating a solid
   -- WHITE8X8 texture rotates its sampling, not the rectangle on this client.
   local dx,dy=x-previousX,y-previousY;local steps=math.max(1,math.ceil(math.max(math.abs(dx),math.abs(dy))/2))
   for step=1,steps do
    segment=segment+1;local line=self.dayLines[segment]
    if not line then line=self.dayGraph:CreateTexture(nil,'ARTWORK');line:SetTexture('Interface\\Buttons\\WHITE8X8');line:SetVertexColor(.29,.86,.78,1);self.dayLines[segment]=line end
    line:ClearAllPoints();line:SetSize(math.abs(dx)/steps+1.5,math.abs(dy)/steps+1.5)
    line:SetPoint('CENTER',self.dayGraph,'BOTTOMLEFT',previousX+dx*(step-.5)/steps,previousY+dy*(step-.5)/steps);line:Show()
   end
  end
  previousX,previousY=x,y
 end
 self.dayFirst:SetText(n>0 and days[first].day or '');self.dayLast:SetText(n>0 and days[last].day or '')
 local pages=math.max(1,math.ceil(n/8));self.dayTablePage=math.min(self.dayTablePage or 1,pages)
 self.dayPageText:SetText('Newest first  |  Page '..self.dayTablePage..' / '..pages)
 for i,row in ipairs(self.dayRows) do
  local index=last-(self.dayTablePage-1)*8-i+1;local d=index>=first and days[index] or nil;row:SetShown(d~=nil)
  if d then
   local values={d.day,tostring(d.count),tostring(d.timed),d.highest>0 and ('+'..d.highest) or '--',math.floor(d.seconds/3600)..'h '..math.floor(d.seconds%3600/60)..'m'}
   for j,v in ipairs(values) do row.labels[j]:SetText(v) end
  end
 end
end
