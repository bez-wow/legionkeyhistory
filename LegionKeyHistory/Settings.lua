-- Settings and profiles, and the "Legion Key History" page in Interface > AddOns.
-- Every character uses the account-wide "Default" profile unless it picks another one.
local H=LegionKeyHistory

H.defaultSettings={
 minimapHidden=false,minimapAngle=220,
 -- Personal Bests
 hud=true,bestMode='timed',hudOverall=true,hudSpec=true,hudClass=true,hudRole=true,
 -- Scores in the game's own windows: next to the name, and details on hover
 scoreFriends=true,hoverFriends=true,scoreApplicants=true,hoverApplicants=true,scoreSearch=true,hoverSearch=true,scoreTarget=true,hoverUnit=true,
 scoreDecimals=false,scoreSuffix=true,scoreColor='4adbc8',
 -- Score tooltip
 tipRanks=true,tipBestRun=true,tipDungeons=true,tipWeekSplit=false,
 -- Sync: 'ask' every time, accept anyone in the 'party', or 'never'
 syncMode='ask',syncAutoTrusted=false,
 -- Journal (not on the settings page)
 showLaterDungeons=false,dayChart='line'
}
local DEFAULT='Default'
local SYNC_MODES={ask='Ask every time',party='Accept anyone in my party',never='Never'}

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
  elseif key=='syncMode' and SYNC_MODES[value] then target[key]=value;count=count+1
  elseif key=='bestMode' and (value=='timed' or value=='completed') then target[key]=value;count=count+1
  elseif key=='dayChart' and (value=='line' or value=='bar') then target[key]=value;count=count+1
  elseif key=='scoreColor' and value:match('^%x%x%x%x%x%x$') then target[key]=value:lower();count=count+1 end
 end
 self:ApplySettings()
 return count
end

-- Puts every visible part of the addon in line with the current settings.
function H:ApplySettings()
 if self.SetMinimapHidden then self:SetMinimapHidden(self.settings.minimapHidden) end
 if self.RefreshHUD then self:RefreshHUD() end
 if self.frame and self.frame:IsShown() and self.Refresh then self:Refresh() end
 if self.leaderboardFrame and self.leaderboardFrame:IsShown() and self.RefreshLeaderboard then self:RefreshLeaderboard() end
 if FriendsFrame and FriendsFrame:IsShown() and FriendsList_Update then pcall(FriendsList_Update) end
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
  self.Message('Version '..latest..' is available (you have '..current..'). Run "LKH Updater.cmd" in the addon folder and choose "Update the addon".')
  return true
 end
 return false
end
function H:FormatScore(score)
 local text=score and string.format(self.settings.scoreDecimals and '%.1f' or '%.0f',score) or '--'
 return self.settings.scoreSuffix and (text..' IO') or text
end
-- The colour scores use next to names, as r,g,b (0-1) or as a |c code.
function H:ScoreColor()
 local hex=tostring(self.settings.scoreColor or ''):match('^%x%x%x%x%x%x$') or self.defaultSettings.scoreColor
 return tonumber(hex:sub(1,2),16)/255,tonumber(hex:sub(3,4),16)/255,tonumber(hex:sub(5,6),16)/255,'|cff'..hex
end
function H:SetScoreColor(r,g,b)
 self.settings.scoreColor=string.format('%02x%02x%02x',math.floor(r*255+.5),math.floor(g*255+.5),math.floor(b*255+.5))
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

-- The settings page --------------------------------------------------------------------------

local function menu(owner,items)
 if not H.settingsMenu then H.settingsMenu=CreateFrame('Frame','LKHSettingsMenu',UIParent,'UIDropDownMenuTemplate') end
 EasyMenu(items,H.settingsMenu,owner,0,0,'MENU')
end

local function confirm(text,onAccept)
 StaticPopupDialogs.LKH_CONFIRM=StaticPopupDialogs.LKH_CONFIRM or {button1=YES,button2=NO,timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3}
 StaticPopupDialogs.LKH_CONFIRM.text=text
 StaticPopupDialogs.LKH_CONFIRM.OnAccept=onAccept
 StaticPopup_Show('LKH_CONFIRM')
end

function H:CreateSettingsPanel()
 if self.settingsPanel then return self.settingsPanel end
 local panel=CreateFrame('Frame','LegionKeyHistorySettings',UIParent);panel.name='Legion Key History';panel:Hide()
 self.settingsPanel=panel
 local scroll=CreateFrame('ScrollFrame','LegionKeyHistorySettingsScroll',panel,'UIPanelScrollFrameTemplate')
 scroll:SetPoint('TOPLEFT',4,-4);scroll:SetPoint('BOTTOMRIGHT',-28,4)
 local body=CreateFrame('Frame',nil,scroll);body:SetSize(560,1240);scroll:SetScrollChild(body)
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
 local function check(label,key,tooltip)
  local cb=CreateFrame('CheckButton',nil,body,'InterfaceOptionsCheckButtonTemplate');cb:SetPoint('TOPLEFT',16,y)
  cb.Text:SetText(label);cb.label=label
  cb:SetScript('OnClick',function(s) H.settings[key]=s:GetChecked() and true or false;H:ApplySettings() end)
  refreshers[#refreshers+1]=function() cb:SetChecked(H.settings[key]==true) end
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

 local title=body:CreateFontString(nil,'ARTWORK','GameFontNormalHuge');title:SetPoint('TOPLEFT',14,y);title:SetText('|cff4adbc8Legion Key History|r');y=y-34

 heading('General')
 local minimap=check('Show the minimap icon','minimapHidden')
 minimap:SetScript('OnClick',function(s) H.settings.minimapHidden=not s:GetChecked();H:ApplySettings() end)
 refreshers[#refreshers+1]=function() minimap:SetChecked(not H.settings.minimapHidden) end

 heading('Scores in the game')
 -- One row per place, with separate switches for the score next to the name and the details on hover.
 local function gridHeader(text,x)
  local t=body:CreateFontString(nil,'ARTWORK','GameFontNormalSmall');t:SetPoint('TOPLEFT',x,y);t:SetText(text)
 end
 gridHeader('Score next to name',250);gridHeader('Details on hover',390);y=y-18
 local function gridRow(label,scoreKey,hoverKey)
  local t=body:CreateFontString(nil,'ARTWORK','GameFontHighlight');t:SetPoint('TOPLEFT',22,y-6);t:SetText(label)
  for column,key in ipairs({scoreKey or false,hoverKey}) do
   if key then
    local cb=CreateFrame('CheckButton',nil,body,'InterfaceOptionsCheckButtonTemplate');cb:SetPoint('TOPLEFT',column==1 and 290 or 425,y)
    cb.Text:SetText('');cb.label=label..(column==1 and ': score next to name' or ': details on hover')
    cb:SetScript('OnClick',function(s) H.settings[key]=s:GetChecked() and true or false;H:ApplySettings() end)
    refreshers[#refreshers+1]=function() cb:SetChecked(H.settings[key]==true) end
   end
  end
  y=y-28
 end
 gridRow('Friends list','scoreFriends','hoverFriends')
 gridRow('Group finder applicants','scoreApplicants','hoverApplicants')
 gridRow('Group finder search results','scoreSearch','hoverSearch')
 gridRow('Target frame',nil,'scoreTarget')
 gridRow('Player tooltip (mouseover)',nil,'hoverUnit')
 y=y-4
 local styles={{false,true},{true,true},{false,false},{true,false}}
 choice('Score style',150,function() return H:FormatScore(1674.34) end,function()
  local items={}
  for _,style in ipairs(styles) do
   local decimals,suffix=style[1],style[2]
   items[#items+1]={text=(decimals and '1674.3' or '1674')..(suffix and ' IO' or ''),
    checked=H.settings.scoreDecimals==decimals and H.settings.scoreSuffix==suffix,
    func=function() H.settings.scoreDecimals=decimals;H.settings.scoreSuffix=suffix;H:ApplySettings() end}
  end
  return items
 end)
 -- Colour of the score next to names (friends list, applicants, search results).
 local colorLabel=body:CreateFontString(nil,'ARTWORK','GameFontHighlight');colorLabel:SetPoint('TOPLEFT',22,y-5);colorLabel:SetText('Score colour')
 local swatch=CreateFrame('Button',nil,body);swatch:SetSize(22,22);swatch:SetPoint('TOPLEFT',230,y)
 swatch.texture=swatch:CreateTexture(nil,'ARTWORK');swatch.texture:SetAllPoints(swatch);swatch.texture:SetTexture('Interface\\Buttons\\WHITE8X8')
 local sample=body:CreateFontString(nil,'ARTWORK','GameFontNormal');sample:SetPoint('TOPLEFT',262,y-4)
 refreshers[#refreshers+1]=function()
  local r,g,b=H:ScoreColor();swatch.texture:SetVertexColor(r,g,b);sample:SetText(H:FormatScore(1674.34));sample:SetTextColor(r,g,b)
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
 action('Default colour',110,340,function() H.settings.scoreColor=nil;H:ApplySettings() end)
 y=y-32

 heading('Score tooltip shows')
 check('Overall, spec and class rank','tipRanks')
 check('Best run','tipBestRun')
 check('Best key per dungeon','tipDungeons')
 check('Best Fortified / Tyrannical key per dungeon','tipWeekSplit')

 heading('Personal Bests')
 check('Show next to Mythic Dungeons in the Dungeon Finder','hud')
 choice('Records',150,function() return H.settings.bestMode=='completed' and 'Highest completed' or 'Best timed' end,function()
  return {{text='Best timed',checked=H.settings.bestMode~='completed',func=function() H.settings.bestMode='timed';H:ApplySettings() end},
   {text='Highest completed',checked=H.settings.bestMode=='completed',func=function() H.settings.bestMode='completed';H:ApplySettings() end}}
 end)
 check('Overall rank column','hudOverall')
 check('Spec rank column','hudSpec')
 check('Class rank column','hudClass')
 check('Role rank column','hudRole')

 heading('Sync')
 choice('Sync requests',190,function() return SYNC_MODES[H.settings.syncMode] or SYNC_MODES.ask end,function()
  local items={}
  for _,mode in ipairs({'ask','party','never'}) do
   items[#items+1]={text=SYNC_MODES[mode],checked=H.settings.syncMode==mode,func=function() H.settings.syncMode=mode;H:ApplySettings() end}
  end
  return items
 end)
 check('When asking: approve friends and guild members automatically','syncAutoTrusted')

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
 panel:SetScript('OnShow',function(s) s:Refresh() end)
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
