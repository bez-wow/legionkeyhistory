-- Party keys: a small window, only inside a dungeon, with the keystone each group member has.
-- Keys whose dungeon is the one you're in are on top, in green. Group members with LKH send theirs
-- (a hidden addon message to the group); keystones linked in party chat (answers to !keys) count too.
-- Drag the window by its icon, then click the lock (top right). /lkh keys unlocks it again.
local H=LegionKeyHistory
local PREFIX='LKHK'
local KEYSTONE_ITEM=138019
local ROW_H,WIDTH,FONT=19,280,14
local ACCENT='4adbc8'
if RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(PREFIX) end

local keys={}   -- short name -> {mapID=,level=} (level 0: no key)
local function short(name) return name and (name:match('^([^%-]+)') or name):lower() end

-- Your keystone from the bags: "|Hkeystone:200:12:..." (Halls of Valor +12).
function H:OwnKeystone()
 for bag=0,NUM_BAG_SLOTS do
  for slot=1,GetContainerNumSlots(bag) do
   if GetContainerItemID(bag,slot)==KEYSTONE_ITEM then
    local link=GetContainerItemLink(bag,slot) or ''
    local mapID,level=link:match('keystone:(%d+):(%d+)')
    if not mapID then mapID,level=link:match('item:'..KEYSTONE_ITEM..'[%d:]-:(%d+):(%d+):%d+:%d+:%d+') end
    if mapID then return tonumber(mapID),tonumber(level) end
   end
  end
 end
end

local function groupChannel()
 if IsInGroup(LE_PARTY_CATEGORY_HOME) then return 'PARTY' end
 if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return 'INSTANCE_CHAT' end
end

local lastSent,lastAsk=0,0
local function send(ask)
 local channel=groupChannel()
 if not channel or not SendAddonMessage then return end
 if ask then
  if GetTime()-lastAsk<3 then return end
  lastAsk=GetTime();SendAddonMessage(PREFIX,'?',channel)
 end
 if GetTime()-lastSent<2 then return end
 lastSent=GetTime()
 local mapID,level=H:OwnKeystone()
 SendAddonMessage(PREFIX,'K|'..(mapID or 0)..'|'..(level or 0),channel)
end

-- ---------------------------------------------------------------------------------------------------------
-- The window.

local frame
local function inDungeon()
 local _,kind=GetInstanceInfo()
 return kind=='party' and not C_ChallengeMode.IsChallengeModeActive()
end

local function mapName(mapID)
 return (mapID and C_ChallengeMode.GetMapInfo(mapID)) or ('Dungeon '..tostring(mapID))
end

-- /lkh keystest: a made-up group in Halls of Valor, to see the window anywhere.
local PREVIEW={
 {name='Pretz',class='MONK',key={mapID=200,level=12}},{name='Cenas',class='DRUID',key={mapID=197,level=15}},
 {name='Treesus',class='SHAMAN',key={mapID=200,level=9}},{name='Hunterdinho',class='HUNTER',key={level=0}},
}

-- Everyone in the group with what we know of their key; this dungeon's keys first.
function H:PartyKeyRows()
 local here=(GetInstanceInfo() or ''):lower()
 local rows={}
 if self.partyKeysPreview then
  here='halls of valor'
  local _,class=UnitClass('player')
  rows[1]={name=UnitName('player'),class=class}
  for i,row in ipairs(PREVIEW) do rows[i+1]={name=row.name,class=row.class,key=row.key} end
 end
 for _,unit in ipairs(self.partyKeysPreview and {} or {'player','party1','party2','party3','party4'}) do
  local name=UnitName(unit)
  if name and name~=UNKNOWNOBJECT then
   local key
   if unit=='player' then
    local mapID,level=self:OwnKeystone();key={mapID=mapID,level=level or 0}
   else
    key=keys[short(name)]
   end
   local _,class=UnitClass(unit)
   local row={name=name,class=class,key=key}
   rows[#rows+1]=row
  end
 end
 -- "Return to Karazhan: Lower" is a key for the "Return to Karazhan" instance.
 for _,row in ipairs(rows) do
  if self.partyKeysPreview and row.key==nil and row.name==UnitName('player') then local mapID,level=self:OwnKeystone();row.key={mapID=mapID,level=level or 0} end
  row.here=row.key and row.key.level>0 and here~='' and mapName(row.key.mapID):lower():sub(1,#here)==here or false
 end
 table.sort(rows,function(a,b)
  if a.here~=b.here then return a.here end
  local la,lb=a.key and a.key.level or -1,b.key and b.key.level or -1
  if la~=lb then return la>lb end
  return a.name<b.name
 end)
 return rows
end

local function setLocked(locked)
 H.settings.partyKeysLocked=locked
 frame:EnableMouse(not locked)
 frame.mover:SetShown(not locked);frame.lock:SetShown(not locked)
 -- Locked: a faint background, no border.
 frame:SetBackdropColor(0,0,0,locked and .25 or .55)
 frame:SetBackdropBorderColor(.29,.86,.78,locked and 0 or 1)
end

local function create()
 frame=CreateFrame('Frame','LegionKeyHistoryPartyKeys',UIParent)
 frame:SetSize(WIDTH,40);frame:SetFrameStrata('MEDIUM');frame:SetClampedToScreen(true);frame:SetMovable(true)
 frame:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1})
 frame:SetBackdropColor(0,0,0,.55)
 frame:RegisterForDrag('LeftButton')
 frame:SetScript('OnDragStart',frame.StartMoving)
 frame:SetScript('OnDragStop',function(f)
  f:StopMovingOrSizing()
  local point,_,relative,x,y=f:GetPoint()
  H.settings.partyKeysPoint={point,relative,x,y}
 end)
 local p=H.settings.partyKeysPoint
 if p then frame:SetPoint(p[1],UIParent,p[2],p[3],p[4]) else frame:SetPoint('BOTTOM',UIParent,'BOTTOM',392,249) end  -- right of the action bars
 frame.title=frame:CreateFontString(nil,'OVERLAY');frame.title:SetFont(H:FontPath(),FONT,'OUTLINE')
 frame.title:SetPoint('TOPLEFT',26,-5);frame.title:SetText('|cff'..ACCENT..'Party keys|r')
 -- The drag icon (top left) and the lock (top right), only while unlocked.
 local mover=frame:CreateTexture(nil,'OVERLAY');mover:SetSize(18,18);mover:SetPoint('TOPLEFT',4,-3)
 mover:SetTexture('Interface\\CURSOR\\UI-Cursor-Move');frame.mover=mover
 local lock=CreateFrame('Button',nil,frame);lock:SetSize(18,18);lock:SetPoint('TOPRIGHT',-3,-2)
 lock:SetNormalTexture('Interface\\Buttons\\LockButton-Unlocked-Up');lock:SetPushedTexture('Interface\\Buttons\\LockButton-Locked-Down')
 lock:SetHighlightTexture('Interface\\Buttons\\UI-Common-MouseHilight','ADD')
 lock:SetScript('OnClick',function() setLocked(true);H.Message('Party keys locked. /lkh keys to move it again.') end)
 lock:SetScript('OnEnter',function(s) GameTooltip:SetOwner(s,'ANCHOR_RIGHT');GameTooltip:SetText('Lock');GameTooltip:AddLine('/lkh keys unlocks it again.',1,1,1);GameTooltip:Show() end)
 lock:SetScript('OnLeave',function() GameTooltip:Hide() end)
 frame.lock=lock
 frame.lines={}
 setLocked(H.settings.partyKeysLocked)
 frame:Hide()
end

function H:RefreshPartyKeys()
 if not self.settings then return end
 local unlocked=frame and not self.settings.partyKeysLocked
 local show=self.partyKeysPreview or self.settings.partyKeys and (inDungeon() or (unlocked and frame:IsShown()))
 if not show then if frame then frame:Hide() end return end
 if not frame then create() end
 local rows=self:PartyKeyRows()
 for i,row in ipairs(rows) do
  local line=frame.lines[i]
  if not line then
   line=frame:CreateFontString(nil,'OVERLAY');line:SetFont(H:FontPath(),FONT,'OUTLINE')
   line:SetPoint('TOPLEFT',8,-8-i*ROW_H);line:SetWidth(WIDTH-16);line:SetJustifyH('LEFT');line:SetWordWrap(false)
   frame.lines[i]=line
  end
  local c=RAID_CLASS_COLORS and RAID_CLASS_COLORS[row.class]
  local name=c and string.format('|cff%02x%02x%02x%s|r',c.r*255+.5,c.g*255+.5,c.b*255+.5,row.name) or row.name
  local key
  if not row.key then key='|cff7a7a7a?|r'
  elseif row.key.level==0 then key='|cff7a7a7ano key|r'
  else key=(row.here and '|cff20ff20' or '|cffffffff')..mapName(row.key.mapID)..' +'..row.key.level..'|r' end
  line:SetText(name..'  '..key);line:Show()
 end
 for i=#rows+1,#frame.lines do frame.lines[i]:Hide() end
 frame:SetHeight(14+(#rows+1)*ROW_H)
 -- Not placed yet (first time in a dungeon): say how, once per session.
 if not self.settings.partyKeysLocked and not frame:IsShown() and not self.partyKeysHinted then
  self.partyKeysHinted=true
  self.Message('Party keys: drag the window by its icon to where you want it, then click the lock (top right).')
 end
 frame:Show()
end

-- /lkh keystest: the window with a made-up group for 30 seconds, wherever you are.
function H:PreviewPartyKeys()
 self.partyKeysPreview=true;self:RefreshPartyKeys()
 self.Message('Party keys preview for 30 seconds (made-up group in Halls of Valor). /lkh keys to move it.')
 C_Timer.After(30,function() self.partyKeysPreview=nil;self:RefreshPartyKeys() end)
end

-- /lkh keys: unlock to move it (shown even outside a dungeon), or lock it again.
function H:TogglePartyKeysLock()
 if not frame then create() end
 if self.settings.partyKeysLocked then
  setLocked(false);frame:Show();self.settings.partyKeys=true;self:RefreshPartyKeys()
  self.Message('Party keys unlocked: drag the icon, then click the lock (top right).')
 else
  setLocked(true);self:RefreshPartyKeys()
 end
end

-- ---------------------------------------------------------------------------------------------------------
-- Events.

local pending
local function refreshSoon()
 if pending then return end
 pending=true
 C_Timer.After(.3,function() pending=nil;H:RefreshPartyKeys() end)
end

local CHAT={CHAT_MSG_PARTY=true,CHAT_MSG_PARTY_LEADER=true,CHAT_MSG_INSTANCE_CHAT=true,CHAT_MSG_INSTANCE_CHAT_LEADER=true}
local events=CreateFrame('Frame')
for _,event in ipairs({'CHAT_MSG_ADDON','PLAYER_ENTERING_WORLD','GROUP_ROSTER_UPDATE','BAG_UPDATE_DELAYED',
 'CHALLENGE_MODE_START','CHALLENGE_MODE_COMPLETED','CHALLENGE_MODE_RESET','CHAT_MSG_PARTY','CHAT_MSG_PARTY_LEADER',
 'CHAT_MSG_INSTANCE_CHAT','CHAT_MSG_INSTANCE_CHAT_LEADER'}) do events:RegisterEvent(event) end
local ownKey
events:SetScript('OnEvent',function(_,event,...)
 if not H.settings then return end
 if event=='CHAT_MSG_ADDON' then
  local prefix,msg,_,sender=...
  if prefix~=PREFIX or short(sender)==short(UnitName('player')) then return end
  if msg=='?' then send(false);return end
  local mapID,level=msg:match('^K|(%d+)|(%d+)')
  if mapID then keys[short(sender)]={mapID=tonumber(mapID),level=tonumber(level)};refreshSoon() end
 elseif CHAT[event] then
  -- A keystone linked in party chat (someone answering !keys): theirs.
  local msg,sender=...
  local mapID,level=msg:match('|Hkeystone:(%d+):(%d+)')
  if mapID and short(sender)~=short(UnitName('player')) then keys[short(sender)]={mapID=tonumber(mapID),level=tonumber(level)};refreshSoon() end
 elseif event=='BAG_UPDATE_DELAYED' then
  -- A new key (after a run, or a depleted one): tell the group.
  local mapID,level=H:OwnKeystone();local now=(mapID or 0)..':'..(level or 0)
  if now~=ownKey then local first=ownKey==nil;ownKey=now;if not first then lastSent=0;send(false) end end
  refreshSoon()
 elseif event=='PLAYER_ENTERING_WORLD' or event=='GROUP_ROSTER_UPDATE' then
  -- Entering a dungeon or someone joining: ask everyone and send ours.
  if inDungeon() or event=='GROUP_ROSTER_UPDATE' then C_Timer.After(2,function() send(true) end) end
  refreshSoon()
 else
  refreshSoon()
 end
end)
