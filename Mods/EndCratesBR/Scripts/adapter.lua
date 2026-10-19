-- Native bridge for the inspected CL 251392 API. Requires live-server validation.
local G=require('geometry')
local Adapter={};Adapter.__index=Adapter
local function valid(o)
    local ok,result=pcall(function() return o and o:IsValid() end)
    return ok and result==true
end
local function same_object(a,b) return valid(a) and valid(b) and a:GetAddress()==b:GetAddress() end
local function str(v)
    if type(v)=='string' then return v end
    local ok,s=pcall(function() return v:ToString() end);return ok and s or tostring(v)
end
local function guid(g)
    return string.format('%08X%08X%08X%08X',g.A & 0xffffffff,g.B & 0xffffffff,g.C & 0xffffffff,g.D & 0xffffffff)
end
function Adapter.new(config,log)
    return setmetatable({config=config,log=log,peers={},actors={},messages={},dropped_messages=0,
        teleport_order={},teleport_head=1,teleport_tail=0,teleport_pending={},teleports_sent=0},Adapter)
end
function Adapter:identify(pc)
    if not valid(pc) or not pc:HasAuthority() or not valid(pc.PlayerState) then return nil end
    local ps=pc.PlayerState;local owner=str(ps:GetOwnerGuid().GuidData)
    local character=guid(pc:GetCharacterGuid().InnerGuid)
    if owner=='' or owner=='None' or character==string.rep('0',32) then return nil end
    return owner..':'..character,owner,character
end
function Adapter:refresh()
    local seen={};self.actors={}
    for _,pc in ipairs(FindAllOf('DominionPlayerController') or {}) do
        local ok,id,owner,character=pcall(self.identify,self,pc)
        if ok and id then
            local previous=self.peers[id]
            if previous and not same_object(previous.pc,pc) then self:release(id);previous=nil end
            if previous and not same_object(previous.pawn,pc.Pawn) then self:release(id) end
            local p=previous or {id=id}
            p.pc=pc;p.owner=owner;p.character=character
            p.name=str(pc.PlayerState:GetPlayerName());p.pawn=pc.Pawn
            if valid(p.pawn) then
                self.actors[p.pawn:GetAddress()]=id
                p.token=p.pawn:GetFullName()
            else p.token='unpossessed' end
            self.actors[pc:GetAddress()]=id;self.peers[id]=p;seen[id]=p
        end
    end
    return seen
end
function Adapter:forget(id) self:release(id);self.teleport_pending[id]=nil;self.peers[id]=nil end
function Adapter:cancel_teleport(id) self.teleport_pending[id]=nil;return true end
function Adapter:cancel_work()
    self.teleport_pending={};self.teleport_order={};self.teleport_head=1;self.teleport_tail=0
    return true
end
function Adapter:peer(id)
    local p=self.peers[id]
    if not p or not valid(p.pc) or not p.pc:HasAuthority() or not valid(p.pc.Pawn) then error('Player is unavailable.',0) end
    return p,p.pc.Pawn
end
function Adapter:snapshot(id)
    local p,pawn=self:peer(id)
    local l=pawn:K2_GetActorLocation();local h=pawn:GetHealthComponent()
    local s={x=l.X,y=l.Y,z=l.Z,token=pawn:GetFullName(),health=h:GetAuthoritativeHealth()}
    s.ready=G.point(s) and G.finite(s.health) and not h:IsDead() and p.pc:IsPlayerReady()
        and not pawn:IsTeleporting() and not self.teleport_pending[id] and not p.teleport_failed
    return s
end
function Adapter:mode(id,mode)
    local p,pawn=self:peer(id)
    local damage=pawn:GetPlayerDamageComponent();local health=pawn:GetHealthComponent()
    if not valid(damage) or not valid(health) then error('Missing player combat components.',0) end
    if not p.original or not same_object(p.original.pawn,pawn) then
        p.original={pawn=pawn,pvp=damage.bIsPvpEnabled}
    end
    local active=mode=='active'
    local locker=self:protection_locker()
    if health:SetIsImmortal(true,locker)~=true then error('Native immortality lock was refused.',0) end
    damage:SetIsInvulnerable(not active,locker)
    damage.bIsPvpEnabled=active
    damage:OnRep_bIsPvpEnabled()
    if damage.bIsPvpEnabled~=active then error('PvP flag did not persist.',0) end
    if not active then health:SetHealth(health:GetMaxHealth(),'EndCratesBR lobby') end
    p.mode=mode
    return true
end
function Adapter:protection_locker()
    if valid(self.locker) then return self.locker end
    local gs=FindFirstOf('DominionGameStateBase')
    assert(valid(gs) and gs:HasAuthority(),'No authoritative world for protection locks.')
    local class=StaticFindObject('/Script/Engine.TimelineComponent')
    assert(valid(class),'Protection component class is unavailable.')
    -- One inert, world-owned component gives BR a distinct GC-tracked locker.
    -- It is not a streaming source and is never replicated to clients.
    local locker=gs:AddComponentByClass(class,true,{
        Translation={X=0,Y=0,Z=0},Rotation={X=0,Y=0,Z=0,W=1},Scale3D={X=1,Y=1,Z=1},
    },false)
    assert(valid(locker),'Could not create a distinct protection locker.')
    locker:SetComponentTickEnabled(false)
    self.locker=locker
    return locker
end
function Adapter:release(id)
    local p=self.peers[id];if not p or not p.original then return true end
    local original=p.original
    if valid(original.pawn) and valid(p.pc) then
        local ok,why=pcall(function()
            local health=original.pawn:GetHealthComponent()
            if health:GetAuthoritativeHealth()<=self.config.knockout_health then health:SetHealth(health:GetMaxHealth(),'EndCratesBR stop') end
            assert(valid(self.locker),'BR protection locker is unavailable.')
            health:SetIsImmortal(false,self.locker)
            local damage=original.pawn:GetPlayerDamageComponent()
            damage:SetIsInvulnerable(false,self.locker)
            damage.bIsPvpEnabled=original.pvp;damage:OnRep_bIsPvpEnabled()
        end)
        if not ok then self.log('Protection cleanup failed: '..tostring(why));return false end
    end
    p.original=nil;p.mode=nil
    return true
end
function Adapter:teleport(id,location)
    assert(G.point(location),'Invalid teleport location')
    local p=self:peer(id);p.teleport_failed=nil
    if not self.teleport_pending[id] then
        self.teleport_tail=self.teleport_tail+1;self.teleport_order[self.teleport_tail]=id
    end
    self.teleport_pending[id]=G.copy(location)
    return true
end
function Adapter:perform_teleport(id,location)
    local _,pawn=self:peer(id)
    return pawn:BP_TriggerDelayedTeleport({LocationName=FName('None'),TargetLocation={X=location.x,Y=location.y,Z=location.z},
        TargetRotation=pawn:K2_GetActorRotation(),TeleportationType=0,TeleportBeginVFXDelayOverride=0,
        bShowLoadingScreen=true,bVFXOnTeleportStart=false,bVFXOnTeleportEnd=false,bNoCheck=false,
        bIsATest=false,bDropAnyLoadoutExclusiveEquipment=false})==true
end
function Adapter:pump_teleports()
    for _=1,self.config.spawn_budget_per_tick do
        if self.teleport_head>self.teleport_tail then break end
        local id=self.teleport_order[self.teleport_head];self.teleport_order[self.teleport_head]=nil
        self.teleport_head=self.teleport_head+1
        local location=self.teleport_pending[id];self.teleport_pending[id]=nil
        if location then
            local ok,accepted=pcall(self.perform_teleport,self,id,location)
            self.teleports_sent=self.teleports_sent+1
            if not ok or not accepted then
                if self.peers[id] then self.peers[id].teleport_failed=true end
                self.log('Teleport failed for a participant; arrival remains locked.')
            end
        end
    end
    if self.teleport_head>self.teleport_tail then self.teleport_order={};self.teleport_head=1;self.teleport_tail=0 end
end
function Adapter:actor_id(actor)
    for _=1,4 do
        if not valid(actor) then return nil end
        if self.actors[actor:GetAddress()] then return self.actors[actor:GetAddress()] end
        local ok,owner=pcall(function() return actor:GetOwner() end)
        if not ok or same_object(owner,actor) then return nil end
        actor=owner
    end
end
function Adapter:component_id(component)
    if not valid(component) then return nil end
    return self:actor_id(component:GetOwner())
end
function Adapter:is_admin(id)
    local p=self.peers[id];if not p or not valid(p.pc) or not p.pc:HasAuthority() then return false end
    if p.pc:IsLocalController() then return true end
    for _,owner in ipairs(self.config.admin_owner_ids) do if p.owner==owner then return true end end
    local settings=FindFirstOf('DedicatedServerSettings')
    return valid(settings) and str(settings.OwnerId)~='' and str(settings.OwnerId)==p.owner
end
function Adapter:message(id,message)
    message=tostring(message):sub(1,1500)
    local priority=message:find('VICTOR:',1,true)~=nil
    if #self.messages>=self.config.max_pending_messages then
        local discard=1
        for i,m in ipairs(self.messages) do if not m.priority then discard=i;break end end
        table.remove(self.messages,discard);self.dropped_messages=self.dropped_messages+1
    end
    self.messages[#self.messages+1]={id=id,text=message,priority=priority}
    return true
end
function Adapter:flush_messages()
    for _=1,self.config.message_budget_per_tick do
        local m=table.remove(self.messages,1);if not m then break end
        local ok,why=pcall(function()
            local p=self.peers[m.id];if not p or not valid(p.pc) or not valid(p.pc.PlayerState) then return end
            local g=p.pc:GetCharacterGuid().InnerGuid
            p.pc:GetPlayerChatComponent():Client_ReceiveChatMessage({MessageBody='[BR] '..m.text,
                SenderData={CharacterGuid={A=g.A,B=g.B,C=g.C,D=g.D},Color={R=255,G=190,B=60,A=255},
                    PlayerId=p.pc.PlayerState.PlayerId,PrimaryNetId=p.pc.PlayerState.UniqueId,
                    SecondaryNetId=p.pc.PlayerState.UniqueId}})
        end)
        if not ok then self.log('Chat delivery failed: '..tostring(why)) end
    end
end
function Adapter:diagnostics()
    local gs=FindFirstOf('DominionGameStateBase')
    local session=FindFirstOf('DominionGameSession')
    local slots=nil;pcall(function() if valid(session) then slots=session.MaxPlayers end end)
    local authority=valid(gs) and gs:HasAuthority()
    return {authority=authority,slots=slots,dedicated=valid(gs) and gs.bIsDedicatedServer==true}
end
function Adapter:world_id()
    local gs=FindFirstOf('DominionGameStateBase')
    if not valid(gs) or not gs:HasAuthority() then return nil end
    local id=guid(gs.WorldInfo.WorldId)
    return id~=string.rep('0',32) and id or nil
end
function Adapter:preflight()
    local d=self:diagnostics()
    if not d.authority then return false,'BR must run on the authoritative server.' end
    if type(d.slots)~='number' or d.slots<self.config.players_per_match then
        return false,'The live GameSession capacity is below '..self.config.players_per_match..' or cannot be read.'
    end
    if self.config.pvp_world_confirmed~=true then return false,'Set pvp_world_confirmed=true after enabling PvP in this dedicated arena world.' end
    if not self.config.world_id or self.config.world_id~=self:world_id() then return false,'Arena geometry belongs to another world or has not been recorded.' end
    return true
end
return Adapter
