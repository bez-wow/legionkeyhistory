-- Versioned, bounded, acknowledged party messages. No executable serialized Lua.
local H=LegionKeyHistory
local PREFIX='LKHsync2'
local function name(unit)
 local n,r=UnitName(unit);return n and (n..'-'..((r and r~='') and r or GetRealmName()))
end
local function canonical(n) return H:IdentityKey(n) or '' end
local function peer(sender)
 for _,u in ipairs({'party1','party2','party3','party4'}) do
  if UnitGUID(u) and canonical(name(u))==canonical(sender) then return {name=name(u),guid=UnitGUID(u)} end
 end
end
local function split(s,sep)
 local t={};for v in (s..sep):gmatch('(.-)'..sep) do t[#t+1]=v end;return t
end
local function escape(v) return tostring(v==nil and '' or v):gsub('[%%|\t\r\n]',function(c) return string.format('%%%02X',c:byte()) end) end
local function unescape(v) return (v:gsub('%%(%x%x)',function(x) return string.char(tonumber(x,16)) end)) end
local fields={'id','mapID','level','startedAt','endedAt','duration','timeLimit','timed','upgrades','date','owner','ownerGUID','partial'}
function H:SyncContains(run,p)
 for _,m in ipairs(run.members or {}) do
  if m.guid and m.guid~='' then if m.guid==p.guid then return true end
  elseif canonical(m.name)==canonical(p.name) then return true end
 end
 return false
end
function H:SyncEncode(run)
 local t={};for _,k in ipairs(fields) do t[#t+1]=escape(run[k]) end
 local aff={};for _,a in ipairs(run.affixes or {}) do aff[#aff+1]=tostring(a) end;t[#t+1]=table.concat(aff,',')
 for _,m in ipairs(run.members or {}) do for _,k in ipairs({'guid','name','class','role'}) do t[#t+1]=escape(m[k]) end end
 return table.concat(t,'|')
end
function H:SyncDecode(payload)
 local t=split(payload,'|');if #t<18 or #t>174 or (#t-14)%4~=0 then return end
 local r={members={},affixes={},status='completed',source='sync'}
 for i,k in ipairs(fields) do r[k]=unescape(t[i]);if r[k]=='' then r[k]=nil end end
 for _,k in ipairs({'mapID','level','startedAt','endedAt','duration','timeLimit','upgrades'}) do
  local v=r[k];r[k]=tonumber(v);if v and (not r[k] or r[k]~=r[k] or math.abs(r[k])>1e12) then return end
 end
 if not r.id or #r.id>180 or not r.mapID or not r.level or r.level<1 or r.level>1000 or not r.duration or r.duration<=0 or r.duration>86400 then return end
 r.timed=r.timed=='true' and true or (r.timed=='false' and false or nil)
 -- Lua's and/or idiom cannot preserve false.
 if t[8]=='false' then r.timed=false end
 r.partial=r.partial=='true'
 for a in t[14]:gmatch('[^,]+') do local n=tonumber(a);if not n or n<1 or n>1000 or #r.affixes>=10 then return end;r.affixes[#r.affixes+1]=n end
 for i=15,#t,4 do r.members[#r.members+1]={guid=unescape(t[i]),name=unescape(t[i+1]),class=unescape(t[i+2]),role=unescape(t[i+3])} end
 for _,m in ipairs(r.members) do for _,k in ipairs({'guid','class','role'}) do if m[k]=='' then m[k]=nil end end end
 self:NormalizeRun(r);r.dungeon=r.dungeon or ('Dungeon '..r.mapID);return r
end
function H:SyncStatus(s)
 self.syncStatus=s;if self.syncText then self.syncText:SetText(s) end
end
function H:SyncTrace(text)
 if not self.db then return end
 self.db.syncDebug=self.db.syncDebug or {};local log=self.db.syncDebug
 log[#log+1]=date('%H:%M:%S')..' '..text
 while #log>200 do table.remove(log,1) end
end
local function send(target,message)
 local fn=C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
 local p=peer(target);if not p then H:SyncTrace('SEND failed: peer no longer in party');return end
 local packet=p.guid..'\t'..message
 local channel='PARTY'
 if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and not IsInGroup(LE_PARTY_CATEGORY_HOME) then channel='INSTANCE_CHAT' end
 if not fn or #packet>250 then H:SyncTrace('SEND failed: unavailable API or oversized packet');return end
 local ok,err=pcall(fn,PREFIX,packet,channel)
 if not ok then H:SyncTrace('SEND error: '..tostring(err));return end
 H.syncCounters=H.syncCounters or {tx=0,rx=0};H.syncCounters.tx=H.syncCounters.tx+1
 local kind=message:match('^[^\t]+');if kind~='DATA' and kind~='ACK' then H:SyncTrace('TX '..kind..' to '..target..' via '..channel) end
end
local function emit(target,kind,id,body) send(target,kind..'\t'..id..'\t'..(body or '')) end
function H:CancelSync()
 local s=self.syncIn or self.syncOut or self.syncOffer
 if s then emit(s.peer,'CANCEL',s.id) end
 self.syncIn=nil;self.syncOut=nil;self.syncOffer=nil
 self:SyncStatus('Sync cancelled. You can request again.');self:SyncTrace('Cancelled locally')
 if self.Refresh then self:Refresh() end
end
function H:SyncTransport(prefix,packet,channel,sender)
 if prefix~=PREFIX or (channel~='PARTY' and channel~='INSTANCE_CHAT') then return end
 local target,message=packet:match('^([^\t]+)\t(.*)$')
 if target~=UnitGUID('player') then return end
 if not peer(sender) then self:SyncTrace('RX rejected: unknown party sender '..tostring(sender));return end
 self.syncCounters=self.syncCounters or {tx=0,rx=0};self.syncCounters.rx=self.syncCounters.rx+1
 self:SyncReceive(message,sender)
end
-- Friends list, Battle.net friends on WoW, or your guild.
function H:IsTrusted(p)
 local key=canonical(p.name)
 for u in pairs({party1=1,party2=1,party3=1,party4=1}) do
  if UnitGUID(u)==p.guid and UnitIsInMyGuild and UnitIsInMyGuild(u) then return true end
 end
 for i=1,(GetNumFriends and GetNumFriends() or 0) do
  local n=GetFriendInfo(i);if n and canonical(n)==key then return true end
 end
 for i=1,(BNGetNumFriends and BNGetNumFriends() or 0) do
  for j=1,(BNGetNumFriendGameAccounts and BNGetNumFriendGameAccounts(i) or 0) do
   local _,n,client,realm=BNGetFriendGameAccountInfo(i,j)
   if client=='WoW' and n and canonical(n..'-'..(realm or ''))==key then return true end
  end
 end
 return false
end
function H:RequestSync(target)
 if self.syncIn or self.syncOut then self.Message('Sync already running: '..(self.syncStatus or '')..' Use Cancel sync to retry.');return end
 local p=peer(target);if not p then self:SyncStatus('Join a party with that player first.');return end
 local id=tostring(time())..'-'..tostring(math.random(100000,999999))
 self.syncIn={id=id,peer=p.name,deadline=GetTime()+12,received=0,added=0,awaitingReply=true}
 emit(p.name,'REQ',id);self:SyncStatus('Waiting for '..p.name..' to approve…')
end
function H:AcceptSync()
 local request=self.syncOffer;self.syncOffer=nil;if not request or not peer(request.peer) then return end
 if self.syncIn or self.syncOut then return end
 self:SyncTrace('Approved '..#request.runs..' runs for '..request.peer)
 self.syncOut={id=request.id,peer=request.peer,runs=request.runs,index=1,retries=0,position=1}
 self:SyncStatus('Sending '..#request.runs..' shared runs to '..request.peer)
end
local function ack(s,index) emit(s.peer,'ACK',s.id,tostring(index)) end
function H:SyncReceive(message,sender)
 if #message>250 or not self.db then return end
 local p=peer(sender);if not p then return end
 local t=split(message,'\t');local kind,id=t[1],t[2];if not id or #id>40 or not id:match('^[%d%-]+$') then return end
 if kind~='DATA' and kind~='ACK' then self:SyncTrace('RX '..kind..' from '..sender) end
 if kind=='CANCEL' then
  for _,key in ipairs({'syncIn','syncOut','syncOffer'}) do local active=self[key];if active and active.id==id and canonical(active.peer)==canonical(sender) then self[key]=nil;self:SyncStatus('The other player cancelled. You can request again.') end end
  return
 end
 if kind=='REQ' then
  if self.syncIn or self.syncOut or self.syncOffer then self:SyncTrace('REQ ignored: already busy');return end
  self.syncRequests=self.syncRequests or {};local last=self.syncRequests[p.guid] or -100
  if GetTime()-last<15 then return end;self.syncRequests[p.guid]=GetTime()
  local runs={};for _,r in ipairs(self.db.runs) do
   if r.status=='completed' and r.duration and self:SyncContains(r,p) and #runs<1000 then
    local encoded=self:SyncEncode(r);if #encoded<=8000 then runs[#runs+1]=encoded end
   end
  end
  local mode=self.settings.syncMode
  if mode=='never' then
   self:SyncTrace('REQ declined: sync requests are turned off in settings')
   emit(p.name,'CANCEL',id);return
  end
  self.syncOffer={id=id,peer=p.name,runs=runs,expires=GetTime()+80}
  emit(p.name,'READY',id,tostring(#runs))
  if mode=='party' or (self.settings.syncAutoTrusted and self:IsTrusted(p)) then
   self:SyncTrace('Auto-approved '..p.name..' ('..(mode=='party' and 'party' or 'friend or guild')..')')
   self:OpenSync();self:AcceptSync();return
  end
  self:OpenSync();self:SyncStatus(p.name..' requests their history: '..#runs..' completed runs. Click Send shared runs to approve.')
  return
 end
 local o=self.syncOut
 if kind=='ACK' and o and o.id==id and canonical(sender)==canonical(o.peer) and tonumber(t[3])==o.index then
  o.index=o.index+1;o.position=1;o.retries=0;o.wait=nil;o.chunks=nil
  if o.index>#o.runs then emit(o.peer,'END',o.id,tostring(#o.runs));self.syncOut=nil;self:SyncStatus('Sync sent successfully.') end
  return
 end
 local s=self.syncIn;if not s or s.id~=id or canonical(sender)~=canonical(s.peer) then return end
 s.deadline=GetTime()+30
 if kind=='READY' then
  s.awaitingReply=nil;s.deadline=GetTime()+90;self:SyncStatus(s.peer..' received your request. Waiting for them to click Send shared runs ('..tostring(tonumber(t[3]) or 0)..' runs).')
 elseif kind=='BEGIN' then
  local n=tonumber(t[3]);if not n or n<0 or n>1000 or n%1~=0 then return end
  if s.total and s.total~=n then return end;s.total=n;self:SyncStatus('Receiving '..s.received..' / '..n..' runs…')
 elseif kind=='DATA' and s.total then
  local index,part,count=tonumber(t[3]),tonumber(t[4]),tonumber(t[5])
  if not index or not part or not count or index%1~=0 or part%1~=0 or count%1~=0 or count<1 or count>54 or part<1 or part>count then return end
  if index<=s.received then ack(s,index);return end
  if index~=s.received+1 or index>s.total then return end
  s.parts=s.parts or {};if s.count and s.count~=count then return end;s.count=count;s.parts[part]=t[6] or ''
  for i=1,count do if not s.parts[i] then return end end
  local r=self:SyncDecode(table.concat(s.parts));if not r or not self:SyncContains(r,{name=name('player'),guid=UnitGUID('player')}) then
   self:SyncTrace('Rejected run '..index..': invalid payload or requester absent');self.syncIn=nil;self:SyncStatus('Sync stopped: invalid run or your character is not in its roster.');return
  end
  r.originalOwner=r.owner;r.originalOwnerGUID=r.ownerGUID;r.owner=name('player');r.ownerGUID=UnitGUID('player');r.syncedFrom=s.peer
  local duplicate=self.index[r.id]~=nil
  for _,old in ipairs(self.db.runs) do
   if old.status=='completed' and old.mapID==r.mapID and old.level==r.level and old.duration and old.endedAt and r.endedAt
    and math.abs(old.duration-r.duration)<1 and math.abs(old.endedAt-r.endedAt)<15 then duplicate=true;break end
  end
  if not duplicate and self:AddRun(r) then s.added=s.added+1 end
  if index==1 or index%10==0 or index==s.total then self:SyncTrace('Received run '..index..'/'..s.total..'; new='..s.added) end
  s.received=index;s.parts=nil;s.count=nil;ack(s,index)
  self:SyncStatus('Received '..index..' / '..s.total..' runs ('..s.added..' new).')
 elseif kind=='END' and s.total and tonumber(t[3])==s.total and s.received==s.total then
  self:SyncTrace('Complete: received='..s.received..' added='..s.added);self.syncIn=nil;self:SyncStatus('Sync complete: '..s.added..' new runs; '..(s.received-s.added)..' duplicates skipped.')
  if self.Refresh then self:Refresh() end
 end
end
function H:SyncTick()
 local now=GetTime()
 if self.syncOffer and now>self.syncOffer.expires then self.syncOffer=nil;self:SyncStatus('Request expired. Ask your friend to request again.') end
 local s=self.syncIn;if s and (now>s.deadline or not peer(s.peer)) then self.syncIn=nil;self:SyncStatus(s.awaitingReply and 'No reply. Both players need LKH 1.1.5; verify party and /reload, then retry.' or 'Sync interrupted. Request again to resume; received runs are kept.');self:SyncTrace('Receive timeout or peer left');if self.Refresh then self:Refresh() end end
 local o=self.syncOut;if not o then return end
 if not peer(o.peer) then self.syncOut=nil;self:SyncStatus('Sync stopped: player left the party.');return end
 if not o.began then emit(o.peer,'BEGIN',o.id,tostring(#o.runs));o.began=true;return end
 if #o.runs==0 then emit(o.peer,'END',o.id,'0');self.syncOut=nil;self:SyncStatus('No shared completed runs to send.');return end
 if o.wait then
  if now-o.wait<5 then return end
  o.retries=o.retries+1;self:SyncTrace('Retry run '..o.index..' attempt '..o.retries);if o.retries>3 then self.syncOut=nil;self:SyncStatus('Transfer timed out. Your friend can request again.');return end
  o.wait=nil;o.position=1;emit(o.peer,'BEGIN',o.id,tostring(#o.runs));return
 end
 local data=o.runs[o.index];local count=math.ceil(#data/150);local part=o.position
 emit(o.peer,'DATA',o.id,table.concat({o.index,part,count,data:sub((part-1)*150+1,part*150)},'\t'))
 o.position=part+1;if part==count then o.wait=now end
end
function H:OpenSync()
 if not self.syncFrame then
  local f=CreateFrame('Frame','LegionKeyHistorySync',UIParent);self.syncFrame=f
  f:SetSize(510,330);f:SetPoint('CENTER');f:SetFrameStrata('FULLSCREEN_DIALOG');f:SetFrameLevel(100);f:EnableMouse(true)
  f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1});f:SetBackdropColor(.025,.035,.05,1)
  table.insert(UISpecialFrames,'LegionKeyHistorySync')
  local title=f:CreateFontString(nil,'OVERLAY','GameFontNormalLarge');title:SetPoint('TOPLEFT',18,-18);title:SetText('Sync shared key history')
  local description=f:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');description:SetPoint('TOPLEFT',18,-48);description:SetText('Request your completed runs from a party member with LKH 1.1.5.')
  self.syncText=f:CreateFontString(nil,'OVERLAY','GameFontHighlight');self.syncText:SetPoint('TOPLEFT',18,-198);self.syncText:SetWidth(470);self.syncText:SetJustifyH('LEFT')
  local function button(label,x,y,fn)
   local b=CreateFrame('Button',nil,f,'UIPanelButtonTemplate');b:SetSize(225,25);b:SetPoint('TOPLEFT',x,y);b:SetText(label);b:SetScript('OnClick',fn);return b
  end
  self.syncPeers={};for i=1,4 do local n=i;self.syncPeers[i]=button('',18,-65-i*29,function() local p=name('party'..n);if p then H:RequestSync(p) end end) end
  button('Send shared runs (approve)',18,-270,function() H:AcceptSync() end)
  button('Copy debug report',18,-235,function() H:OpenSyncDebug() end)
  button('Cancel sync',260,-235,function() H:CancelSync() end)
  button('Close',260,-270,function() f:Hide() end)
 end
 for i,b in ipairs(self.syncPeers) do b:SetWidth(470);local n=name('party'..i);b:SetText(n and ('Request from '..n) or 'No party member');b:SetShown(n~=nil) end
 self.syncText:SetText(self.syncStatus or 'Join a party with your friend. Only runs including the requester are shared.');self.syncFrame:Show();if self.Front then self:Front(self.syncFrame) end
end
function H:SyncDebugReport()
 local lines={'Legion Key History 1.1.5 / '..PREFIX,'Player: '..tostring(name('player'))..' / '..tostring(UnitGUID('player')),
  'Status: '..(self.syncStatus or 'Idle'),'Transport: PARTY / INSTANCE_CHAT; recipient GUID envelope'}
 for i=1,4 do local p=name('party'..i);if p then lines[#lines+1]='Party: '..p..' / '..tostring(UnitGUID('party'..i)) end end
 local c=self.syncCounters or {};lines[#lines+1]='This session: TX='..(c.tx or 0)..' RX='..(c.rx or 0)
 for _,key in ipairs({'syncIn','syncOut','syncOffer'}) do
  local v=self[key];if v then lines[#lines+1]=key..': id='..v.id..' peer='..v.peer..' received='..(v.received or 0)..' total='..(v.total or (v.runs and #v.runs) or 0)..' sending='..(v.index or 0) end
 end
 lines[#lines+1]='Recent diagnostics (saved across reloads):'
 for _,line in ipairs((self.db and self.db.syncDebug) or {}) do lines[#lines+1]=line end
 return table.concat(lines,'\n')
end
function H:OpenSyncDebug()
 if not self.syncDebugFrame then
  local f=CreateFrame('Frame','LegionKeyHistorySyncDebug',UIParent);self.syncDebugFrame=f
  f:SetSize(650,450);f:SetPoint('CENTER');f:SetFrameStrata('FULLSCREEN_DIALOG');f:SetFrameLevel(110);f:EnableMouse(true)
  f:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8',edgeFile='Interface\\Buttons\\WHITE8X8',edgeSize=1});f:SetBackdropColor(.025,.035,.05,1)
  table.insert(UISpecialFrames,'LegionKeyHistorySyncDebug')
  local title=f:CreateFontString(nil,'OVERLAY','GameFontNormalLarge');title:SetPoint('TOPLEFT',15,-15);title:SetText('Sync diagnostics - Ctrl+A, Ctrl+C to copy')
  local scroll=CreateFrame('ScrollFrame',nil,f,'UIPanelScrollFrameTemplate');scroll:SetPoint('TOPLEFT',15,-45);scroll:SetPoint('BOTTOMRIGHT',-35,45)
  local box=CreateFrame('EditBox',nil,scroll);box:SetMultiLine(true);box:SetAutoFocus(false);box:SetFontObject(ChatFontNormal);box:SetWidth(590);box:SetHeight(340)
  box:SetScript('OnEscapePressed',function() f:Hide() end);scroll:SetScrollChild(box);self.syncDebugBox=box
  local close=CreateFrame('Button',nil,f,'UIPanelButtonTemplate');close:SetSize(90,25);close:SetPoint('BOTTOM',0,10);close:SetText('Close');close:SetScript('OnClick',function() f:Hide() end)
 end
 self.syncDebugBox:SetText(self:SyncDebugReport());self.syncDebugFrame:Show();if self.Front then self:Front(self.syncDebugFrame) end;self.syncDebugBox:SetFocus();self.syncDebugBox:HighlightText()
end
local f=CreateFrame('Frame');f:RegisterEvent('CHAT_MSG_ADDON');f:RegisterEvent('PLAYER_LOGIN')
f:SetScript('OnEvent',function(_,event,prefix,message,channel,sender)
 if event=='PLAYER_LOGIN' then local fn=C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix;if fn then local ok,result=pcall(fn,PREFIX);H:SyncTrace('Register '..PREFIX..': '..tostring(ok and result));else H:SyncTrace('No prefix registration API') end
 else H:SyncTransport(prefix,message,channel,sender) end
end)
local elapsed=0;f:SetScript('OnUpdate',function(_,dt) elapsed=elapsed+dt;if elapsed>=.12 then elapsed=0;H:SyncTick() end end)
