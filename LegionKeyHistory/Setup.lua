-- First-run setup (/lkh setup) and "new feature" callouts.
-- Setup: a short guided tour of the settings, one topic per page, with the settings page's live
-- previews beside it (real leaderboard players and your own tooltip where possible). It opens by
-- itself only on a fresh install; upgrading players never see it unless they type /lkh setup.
-- Callouts: a small note beside a new feature the first time it shows up, saying what it is and
-- how to move or turn it off. "Got it" (or turning it off) hides it for good.
local H=LegionKeyHistory
local ACCENT={.29,.86,.78}
local W,HGT=560,410
local backdrop={bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1}

local function font(fs,size,flags) fs:SetFont(H:FontPath(),size,flags or '');return fs end
local function label(parent,size,x,y,w,text,r,g,b)
 local t=font(parent:CreateFontString(nil,'OVERLAY'),size);t:SetPoint('TOPLEFT',x,y)
 if w then t:SetWidth(w) end
 t:SetJustifyH('LEFT');t:SetTextColor(r or .85,g or .9,b or .93);t:SetText(text or '');return t
end
local function flatButton(parent,w,h,text,onClick)
 local b=CreateFrame('Button',nil,parent);b:SetSize(w,h);b:SetBackdrop(backdrop)
 b:SetBackdropColor(.06,.08,.105,1);b:SetBackdropBorderColor(.17,.30,.34)
 b.text=font(b:CreateFontString(nil,'OVERLAY'),12);b.text:SetPoint('CENTER');b.text:SetText(text);b.text:SetTextColor(.85,.9,.93)
 b:SetScript('OnEnter',function(s) if not s.selected then s:SetBackdropBorderColor(.29,.55,.52) end end)
 b:SetScript('OnLeave',function(s) if not s.selected then s:SetBackdropBorderColor(.17,.30,.34) end end)
 b:SetScript('OnClick',onClick)
 function b:SetSelected(on)
  self.selected=on
  self:SetBackdropBorderColor(on and ACCENT[1] or .17,on and ACCENT[2] or .30,on and ACCENT[3] or .34)
  self.text:SetTextColor(on and ACCENT[1] or .85,on and ACCENT[2] or .9,on and ACCENT[3] or .93)
 end
 return b
end

-- ---------------------------------------------------------------------------------------------------------
-- Feature callouts.

-- since: the version that brought the feature. Players updating from that version or later have
-- had it already and get no callout (see SettleFeatureNotes).
H.FEATURES={
 partyKeys={
  since='2.0.0',
  -- Before versions were saved (2.0.0): a position or lock means they already used the window.
  used=function(profile) return profile.partyKeysPoint~=nil or profile.partyKeysLocked~=nil end,
  title='Party keys',
  text=function(anchor)
   return 'Each group member\'s keystone: sent by their LKH, or picked up when they link it in party chat (!keys).\n\n'
    ..'Shows only in dungeons, before the key starts and after it ends.\n\n'
    ..(H.settings.partyKeysLocked and 'Type /lkh keys to move it.' or 'Drag it by the icon, then click the lock.')
  end,
  off=function() H.settings.partyKeys=false;H:ApplySettings() end,
 },
}

-- Once per version change, at load: features the player already had count as seen, so only new
-- ones get a callout. A fresh install gets the setup instead and keeps every callout (setup marks
-- the ones it shows). Then the current version is saved for next time.
function H:SettleFeatureNotes(fresh)
 local db=self.db;db.seenFeatures=db.seenFeatures or {}
 local current=GetAddOnMetadata and GetAddOnMetadata('LegionKeyHistory','Version')
 local previous=db.lastVersion
 if not fresh and previous~=current then
  for id,feature in pairs(self.FEATURES) do
   local had=previous and not self:VersionNewer(feature.since,previous)
   if not previous and feature.used then
    for _,profile in pairs(db.profiles or {}) do if feature.used(profile) then had=true end end
   end
   if had then db.seenFeatures[id]=true end
  end
 end
 db.lastVersion=current or previous
end

function H:MarkFeatureSeen(id)
 self.db.seenFeatures=self.db.seenFeatures or {}
 self.db.seenFeatures[id]=true
 if self.calloutFrame and self.calloutFrame.id==id then self.calloutFrame:Hide() end
end

-- Shows the callout for feature `id` beside `anchor` (once it is on screen), unless seen.
function H:FeatureCallout(id,anchor)
 local feature=self.FEATURES[id]
 if not feature or not anchor or not anchor:IsShown() or (self.db.seenFeatures or {})[id] then return end
 local f=self.calloutFrame
 if not f then
  f=CreateFrame('Frame','LegionKeyHistoryCallout',UIParent);self.calloutFrame=f
  f:SetWidth(250);f:SetFrameStrata('HIGH');f:SetBackdrop(backdrop);f:EnableMouse(true);f:SetClampedToScreen(true)
  f:SetBackdropColor(.025,.035,.05,.96);f:SetBackdropBorderColor(unpack(ACCENT))
  local badge=CreateFrame('Frame',nil,f);badge:SetSize(36,15);badge:SetPoint('TOPLEFT',10,-10);badge:SetBackdrop(backdrop)
  badge:SetBackdropColor(ACCENT[1],ACCENT[2],ACCENT[3],.9);badge:SetBackdropBorderColor(ACCENT[1],ACCENT[2],ACCENT[3],.9)
  local new=font(badge:CreateFontString(nil,'OVERLAY'),10);new:SetPoint('CENTER',0,0);new:SetText('NEW');new:SetTextColor(.02,.05,.06)
  f.title=label(f,14,52,-10,190,'',1,1,1)
  f.text=label(f,11,10,-34,230)
  f.got=flatButton(f,80,20,'Got it',function() H:MarkFeatureSeen(f.id) end)
  f.got:SetPoint('BOTTOMRIGHT',-10,10)
  f.off=flatButton(f,90,20,'Turn it off',function()
   local id=f.id;H:MarkFeatureSeen(id);H.FEATURES[id].off()
   H.Message(H.FEATURES[id].title..' turned off. /lkh config (Windows) turns it back on.')
  end)
  f.off:SetPoint('RIGHT',f.got,'LEFT',-6,0)
 end
 f.id=id;f.anchor=anchor
 f.title:SetText(feature.title)
 f.text:SetText(type(feature.text)=='function' and feature.text(anchor) or feature.text)
 f.off:SetShown(feature.off~=nil)
 f:SetHeight(f.text:GetStringHeight()+78)
 -- Beside the feature, on the side with more room.
 f:ClearAllPoints()
 local x=anchor:GetCenter()
 if x and x*anchor:GetEffectiveScale()>UIParent:GetWidth()*UIParent:GetEffectiveScale()/2 then f:SetPoint('TOPRIGHT',anchor,'TOPLEFT',-10,0)
 else f:SetPoint('TOPLEFT',anchor,'TOPRIGHT',10,0) end
 -- Gone with the feature (until it shows again).
 if not anchor.lkhCalloutHooked then
  anchor.lkhCalloutHooked=true
  anchor:HookScript('OnHide',function(s) if f.anchor==s then f:Hide() end end)
 end
 f:Show()
end

-- ---------------------------------------------------------------------------------------------------------
-- Setup.

local wizard
local pages={}
local current=1

-- The settings page's previews, beside the setup window.
local function preview(kind)
 if not H.ShowSettingsPreview then H:CreateSettingsPanel() end
 H.previewAnchor=wizard
 wizard.previewKind=kind
 H.ShowSettingsPreview(kind)
end

-- Controls: each changes one setting, applies it, and redraws the preview.
local function changed() H:ApplySettings();preview(wizard.previewKind) end
-- The preview follows the control nearest the mouse (the page's own preview for controls without
-- one): moving between two buttons of the same option keeps it, and heading for another option
-- switches as soon as the mouse is closer to it. Outside the window it stays as it is.
local building
local function hoverable(frame,kind)
 local list=building.controls;list[#list+1]={frame=frame,kind=kind or false}
 frame:HookScript('OnEnter',function() local k=kind or pages[current].preview;if k~=wizard.previewKind then preview(k) end end)
end
local function toggle(parent,x,y,text,get,set,kind)
 local cb=CreateFrame('CheckButton',nil,parent,'InterfaceOptionsCheckButtonTemplate');cb:SetPoint('TOPLEFT',x,y)
 cb.Text:SetText(text);cb.label=text
 cb:SetScript('OnClick',function(s) set(s:GetChecked() and true or false);changed() end)
 hoverable(cb,kind)
 cb.refresh=function() cb:SetChecked(get() and true or false) end
 return cb
end
local function setting(key) return function() return H.settings[key] end,function(v) H.settings[key]=v end end
-- A row (or column) of buttons, one per option; the chosen one is highlighted.
local function pills(parent,x,y,options,get,set,kind,vertical,width)
 local list={}
 for i,o in ipairs(options) do
  local b=flatButton(parent,width or 110,22,o.text,function() set(o.value);changed();for _,p in ipairs(list) do p.refresh() end end)
  if vertical then b:SetPoint('TOPLEFT',x,y-(i-1)*26) else b:SetPoint('TOPLEFT',x+(i-1)*((width or 110)+6),y) end
  b.refresh=function() b:SetSelected(get()==o.value) end
  hoverable(b,kind);list[i]=b
 end
 return list
end
local function section(parent,x,y,text) return label(parent,12,x,y,nil,text,1,.82,0) end

local function page(def) pages[#pages+1]=def end

-- 1. Welcome, with your own score from the leaderboard.
page({title='Welcome to Legion Key History',text='Raider.IO-style Mythic+ scores for Tauri, right in your game. Pick what you want to see; each step shows a live preview beside this window. Everything can be changed later in /lkh config.',
 preview='tooltip',
 build=function(c)
  c.you=label(c,13,0,-4,500)
  c.file=label(c,12,0,-30,500)
  c.updater=label(c,12,0,-54,500,'',1,.6,.2)
  c.skip=flatButton(c,200,24,'Skip, keep the defaults',function() wizard:Hide() end);c.skip:SetPoint('TOPLEFT',0,-100)
 end,
 show=function(c)
  local name=UnitName('player')
  local p=H.PlayerScore and H:PlayerScore(name)
  if p and p.score then
   local _,_,_,hex=H:ScoreColor(p.score)
   c.you:SetText('You: '..name..'  '..hex..string.format('%.1f',p.score)..'|r'..(H:PlayerRank(p) and ('  |cff9d9d9d(rank #'..H:PlayerRank(p)..')|r') or ''))
  else
   c.you:SetText('You: '..(name or '?')..'  |cff9d9d9dnot on the leaderboard yet: time a key and you will be.|r')
  end
  local data=LegionKeyHistoryLeaderboard
  local ago=data and data.downloaded and H.DownloadedAgo and H:DownloadedAgo(data.downloaded) or ''
  c.file:SetText(data and data.downloaded and ('Leaderboard file from '..data.downloaded..ago) or 'No leaderboard file loaded.')
  -- An old file: the hourly updater isn't running.
  local old=ago:find('days ago') or ago:find('%d%d h ago')
  c.updater:SetText(old and 'To keep it fresh, run "LKH Updater.cmd" in the addon folder and press 2.' or '')
 end})

-- 2. The score next to names: where, how it reads, what colour.
page({title='Scores next to names',text='A player\'s score beside their name, so you can tell at a glance who you are grouping with.',
 preview='friends',
 build=function(c)
  c.items={}
  section(c,0,-2,'Show it in')
  c.items[#c.items+1]=toggle(c,0,-20,'The friends list',function() return H.settings.scoreFriends end,function(v) H.settings.scoreFriends=v end,'friends')
  c.items[#c.items+1]=toggle(c,0,-48,'Group finder applicants',function() return H.settings.scoreApplicants end,function(v) H.settings.scoreApplicants=v end,'applicants')
  section(c,0,-86,'Style')
  local style=function() return (H.settings.scoreDecimals and 'd' or '')..(H.settings.scoreSuffix and 's' or '') end
  for _,b in ipairs(pills(c,0,-104,{{value='',text='1674'},{value='d',text='1674.3'},{value='s',text='1674 IO'},{value='ds',text='1674.3 IO'}},style,
   function(v) H.settings.scoreDecimals=v:find('d')~=nil;H.settings.scoreSuffix=v:find('s')~=nil end,'look',false,90)) do c.items[#c.items+1]=b end
  section(c,0,-142,'Colour')
  for _,b in ipairs(pills(c,0,-160,{{value='rio',text='Raider.IO style'},{value='custom',text='One colour'}},function() return H.settings.scoreColorMode end,
   function(v) H.settings.scoreColorMode=v end,'look',false,130)) do c.items[#c.items+1]=b end
  label(c,11,0,-190,500,'Raider.IO style: green to gold by where the score stands on this leaderboard.',.6,.6,.6)
 end})

-- 3. The score tooltip: where it appears and what it shows (your own as the preview).
-- Two columns of switches, then the key to hold on players across the bottom.
page({title='Score tooltip',text='Hovering a player adds their score, ranks and best keys to the tooltip. The preview is your own.',
 preview='tooltip',
 build=function(c)
  c.items={}
  local ROW=28
  section(c,0,-2,'Show it on')
  c.items[#c.items+1]=toggle(c,0,-20,'Friends list',function() return H.settings.hoverFriends end,function(v) H.settings.hoverFriends=v end,'friends')
  c.items[#c.items+1]=toggle(c,0,-20-ROW,'Group finder',function() return H.settings.hoverApplicants or H.settings.hoverSearch end,
   function(v) H.settings.hoverApplicants=v;H.settings.hoverSearch=v end,'search')
  c.items[#c.items+1]=toggle(c,0,-20-2*ROW,'Players in the world',function() return H.settings.hoverUnit end,function(v) H.settings.hoverUnit=v end,'unit')
  section(c,260,-2,'It shows')
  for i,o in ipairs({{'Ranks','tipRanks'},{'Best run','tipBestRun'},{'Timed runs by level','tipTimedRuns'},{'Best key per dungeon','tipDungeons'},{'Fortified / Tyrannical split','tipWeekSplit'}}) do
   c.items[#c.items+1]=toggle(c,260,-20-(i-1)*ROW,o[1],setting(o[2]))
  end
  -- Below both columns (the right one is five rows tall).
  section(c,0,-20-5*ROW-8,'On players, show it')
  for _,b in ipairs(pills(c,0,-20-5*ROW-26,{{value='always',text='Always'},{value='shift',text='Hold Shift'},{value='ctrl',text='Hold Ctrl'},{value='alt',text='Hold Alt'}},
   function() return H.settings.hoverModifier end,function(v) H.settings.hoverModifier=v end,'unit',false,96)) do c.items[#c.items+1]=b end
 end})

-- 4. Group finder search results.
page({title='Group finder',text='How each group reads in the group finder\'s search results.',
 preview='search',
 build=function(c)
  c.items=pills(c,0,-4,{{value='leaderTop',text='Leader and score on top'},{value='dungeonTop',text='Dungeon on top, leader below'},{value='plain',text='As the game shows it'}},
   function() return H.settings.searchStyle end,function(v) H.settings.searchStyle=v end,'search',true,260)
 end})

-- 5. The windows that come up around keys: party keys (shown for real) and Personal Bests.
page({title='In dungeons',text='Two small windows. The party keys preview is on your screen now: drag it where you want it.',
 build=function(c)
  c.items={}
  c.items[#c.items+1]=toggle(c,0,-2,'Party keys',function() return H.settings.partyKeys end,function(v) H.settings.partyKeys=v;H:PreviewPartyKeys(v and 'setup') end)
  label(c,11,28,-26,470,'Each group member\'s keystone, before the key starts and after it ends. From their LKH, or when they link it in party chat (!keys).',.6,.6,.6)
  c.items[#c.items+1]=toggle(c,0,-66,'Personal Bests',function() return H.settings.hud end,function(v) H.settings.hud=v end,'hud')
  label(c,11,28,-90,470,'Your best key in each dungeon, beside the Dungeon Finder. Point at it to see yours.',.6,.6,.6)
 end,
 show=function()
  -- Explained here, so no callout later.
  H:MarkFeatureSeen('partyKeys')
  if H.settings.partyKeys then H:PreviewPartyKeys('setup') end
 end,
 hide=function()
  H:PreviewPartyKeys(false)
  if H.LockPartyKeys then H:LockPartyKeys() end
 end})

-- 6. Friends' keys.
page({title='Friends in keys',text='Friends and guildmates with LKH show their key live, and you show yours.',
 preview='friendkeys',
 build=function(c)
  c.items={}
  c.items[#c.items+1]=toggle(c,0,-2,'Share my key with friends, guild and group',setting('shareKeyStatus'))
  c.items[#c.items+1]=toggle(c,0,-30,'Their key in the friends list tooltip',setting('friendKeyStatus'))
  c.items[#c.items+1]=toggle(c,0,-58,'Their key in place of their zone ("Maw of Souls +11")',setting('friendKeyList'))
 end})

-- 7. Done.
page({title='All set',text='You can change any of this in /lkh config, or run this again with /lkh setup.',
 build=function(c)
  c.items={}
  c.items[#c.items+1]=toggle(c,0,-2,'Minimap icon',function() return not H.settings.minimapHidden end,function(v) H.settings.minimapHidden=not v end)
  section(c,0,-42,'Commands')
  label(c,12,0,-62,500,'/lkh  your journal\n/lkh lb  the leaderboard\n/lkh party  your group side by side\n/lkh config  settings')
  c.updater=label(c,12,0,-140,500,'',1,.6,.2)
 end,
 show=function(c)
  local data=LegionKeyHistoryLeaderboard
  local ago=data and data.downloaded and H.DownloadedAgo and H:DownloadedAgo(data.downloaded) or ''
  c.updater:SetText((ago:find('days ago') or ago:find('%d%d h ago')) and 'Your leaderboard file is old: run "LKH Updater.cmd" in the addon folder and press 2 for hourly updates.' or '')
 end})

local function showPage(i)
 local old=pages[current]
 if old and old.content and old.content:IsShown() and old.hide then old.hide(old.content) end
 current=i;local p=pages[i]
 for _,q in ipairs(pages) do if q.content then q.content:Hide() end end
 if not p.content then
  p.content=CreateFrame('Frame',nil,wizard);p.content:SetPoint('TOPLEFT',22,-136);p.content:SetPoint('BOTTOMRIGHT',-22,52)
  p.content.controls={};building=p.content
  p.build(p.content)
 end
 wizard.title:SetText(p.title);wizard.text:SetText(p.text)
 wizard.step:SetText(i..' / '..#pages)
 wizard.fill:SetWidth(math.max(1,(W-44)*i/#pages))
 wizard.back:SetShown(i>1)
 wizard.next.text:SetText(i==#pages and 'Finish' or i==1 and 'Start' or 'Next')
 for _,item in ipairs(p.content.items or {}) do item.refresh() end
 p.content:Show()
 if p.show then p.show(p.content) end
 preview(p.preview)
end

local function create()
 wizard=CreateFrame('Frame','LegionKeyHistorySetup',UIParent)
 wizard:SetSize(W,HGT);wizard:SetPoint('CENTER',-150,40);wizard:SetFrameStrata('HIGH');wizard:SetClampedToScreen(true)
 wizard:SetBackdrop(backdrop);wizard:SetBackdropColor(.025,.035,.05,.98);wizard:SetBackdropBorderColor(.17,.30,.34)
 wizard:EnableMouse(true);wizard:SetMovable(true);wizard:RegisterForDrag('LeftButton')
 wizard:SetScript('OnDragStart',wizard.StartMoving);wizard:SetScript('OnDragStop',function(s) s:StopMovingOrSizing();preview(s.previewKind) end)
 local wait=0
 wizard:SetScript('OnUpdate',function(s,elapsed)
  wait=wait+(elapsed or 1);if wait<.05 then return end;wait=0
  local p=pages[current]
  if not (p and p.content and s:IsMouseOver()) then return end
  local k,distance=H.NearestPreview(p.content.controls)
  if distance then
   k=k or p.preview
   if k~=s.previewKind then preview(k) end
  end
 end)
 label(wizard,15,22,-16,nil,'|cff4adbc8MYTHIC+|r  Legion Key History setup',1,1,1)
 wizard.step=label(wizard,12,W-90,-18,40,'',.6,.6,.6);wizard.step:SetJustifyH('RIGHT')
 local close=flatButton(wizard,22,22,'X',function() wizard:Hide() end);close:SetPoint('TOPRIGHT',-10,-12)
 local track=wizard:CreateTexture(nil,'ARTWORK');track:SetPoint('TOPLEFT',22,-44);track:SetSize(W-44,3);track:SetColorTexture(.10,.15,.20,1)
 wizard.fill=wizard:CreateTexture(nil,'OVERLAY');wizard.fill:SetPoint('TOPLEFT',22,-44);wizard.fill:SetSize(1,3);wizard.fill:SetColorTexture(unpack(ACCENT))
 wizard.title=label(wizard,20,22,-60,W-44,'',1,1,1)
 wizard.text=label(wizard,12,22,-90,W-44,'',.7,.75,.8)
 wizard.next=flatButton(wizard,100,26,'Next',function() if current<#pages then showPage(current+1) else wizard:Hide() end end)
 wizard.next:SetPoint('BOTTOMRIGHT',-22,16);wizard.next:SetSelected(true)
 wizard.back=flatButton(wizard,100,26,'Back',function() if current>1 then showPage(current-1) end end)
 wizard.back:SetPoint('RIGHT',wizard.next,'LEFT',-8,0)
 table.insert(UISpecialFrames,'LegionKeyHistorySetup')
 -- Closed in any way (Finish, X, Escape, skip): done, so it never opens by itself again.
 -- Hidden with the whole UI (Alt+Z, a cutscene) is not closed: it comes back with the UI.
 wizard:SetScript('OnHide',function()
  if not UIParent:IsShown() then return end
  local p=pages[current];if p and p.hide and p.content then p.hide(p.content) end
  H.db.setupDone=true
  if H.ShowSettingsPreview then H.ShowSettingsPreview(nil) end
  H.previewAnchor=nil
  if H.hudPreview then H:PreviewHUD(false) end
 end)
end

function H:OpenSetup()
 if not self.settingsPanel then self:CreateSettingsPanel() end
 if not wizard then create() end
 wizard:Show();showPage(1)
end

-- A fresh install: open setup a few seconds after logging in, once out of combat.
function H:MaybeOpenSetup()
 if self.db.setupDone then return end
 if InCombatLockdown and InCombatLockdown() then
  local f=CreateFrame('Frame');f:RegisterEvent('PLAYER_REGEN_ENABLED')
  f:SetScript('OnEvent',function(s) s:UnregisterAllEvents();C_Timer.After(2,function() H:MaybeOpenSetup() end) end)
  return
 end
 self:OpenSetup()
end
