NATIVE_MOCKS = '''
hooks,console_commands,delivered,logs,controllers,assets={}, {}, {}, {}, {}, {}
function object(name)
    return {IsValid=function()return true end,GetFullName=function()return name end,
        GetFName=function()return {ToString=function()return name end}end}
end
function print(message) logs[#logs+1]=message end
function FName(s)return s end
function RegisterHook(name,pre,post) hooks[name]={pre=pre,post=post};return 1,2 end
function RegisterConsoleCommandHandler(name,fn) console_commands[name]=fn end
function LoopAsync(_,fn) loop=fn end
function ExecuteInGameThread(fn) fn() end
function StaticFindObject(path)
    if path==missing_function then return nil end
    return assets[path] or (path:find('^/Script/') and object(path)) or nil
end
function LoadAsset(path) load_count=(load_count or 0)+1 end
game_state=object('LiveGameState');game_state.WorldInfo={WorldId={A=10,B=20,C=30,D=40}}
game_state.bIsDedicatedServer=true
function game_state:HasAuthority()return true end
session=object('LiveSession');session.MaxPlayers=100
settings=object('ServerSettings');settings.OwnerId='owner2'
function FindFirstOf(name)
    if name=='DominionGameStateBase' then return game_state end
    if name=='DominionGameSession' then return session end
    if name=='DedicatedServerSettings' then return settings end
end
function FindAllOf(name)
    if name=='DominionPlayerController' then return controllers end
    if name=='ItemData' then return {} end
    return {}
end
function make_pc(n)
    local pc=object('PC_'..n);pc.owner='owner'..n;pc.authority=true
    pc.PlayerState=object('State_'..n);pc.PlayerState.PlayerId=n;pc.PlayerState.UniqueId={id=n}
    function pc.PlayerState:GetOwnerGuid()return {GuidData=pc.owner} end
    function pc.PlayerState:GetPlayerName()return 'Player '..n end
    function pc:HasAuthority()return self.authority end
    function pc:IsLocalController()return false end
    function pc:IsPlayerReady()return self.ready~=false end
    function pc:GetCharacterGuid()return {InnerGuid={A=n,B=2,C=3,D=4}} end
    local pawn=object('Pawn_'..n);pc.Pawn=pawn;pawn.location={X=0,Y=0,Z=500}
    function pawn:GetOwner()return pc end
    function pawn:HasAuthority()return pc.authority end
    function pawn:K2_GetActorLocation()return self.location end
    function pawn:K2_GetActorRotation()return {Pitch=0,Yaw=0,Roll=0} end
    function pawn:IsTeleporting()return self.teleporting==true end
    function pawn:BP_TriggerDelayedTeleport(params)
        self.teleport_calls=(self.teleport_calls or 0)+1
        if self.refuse_teleport then return false end
        self.location=params.TargetLocation;return true
    end
    local health=object('Health_'..n);pawn.health=health;health.value=100
    function health:GetOwner()return pawn end
    function health:GetAuthoritativeHealth()return self.value end
    function health:GetMaxHealth()return 100 end
    function health:IsDead()return self.value<=0 and not self.immortal end
    function health:SetIsImmortal(enabled,locker)self.immortal=enabled;self.locker=locker;return enabled end
    function health:SetHealth(value)self.value=value end
    function pawn:GetHealthComponent()return health end
    local damage=object('Damage_'..n);damage.bIsPvpEnabled=false;pawn.damage=damage
    function damage:GetOwner()return pawn end
    function damage:SetIsInvulnerable(enabled,locker)self.invulnerable=enabled;return enabled end
    function damage:OnRep_bIsPvpEnabled()end
    function pawn:GetPlayerDamageComponent()return damage end
    local chat=object('Chat_'..n)
    function chat:GetOwner()return pc end
    function chat:Client_ReceiveChatMessage(data)delivered[#delivered+1]={owner=pc.owner,data=data} end
    pc.chat=chat;function pc:GetPlayerChatComponent()return chat end
    pc.BP_Components_Inventory=object('Inventory_'..n);pc.BP_Components_Inventory.count=0
    function pc.BP_Components_Inventory:GetNumItemsByData()return self.count end
    function pc.BP_Components_Inventory:AddItemByData(_,count)self.count=self.count+count;return true end
    controllers[#controllers+1]=pc;return pc
end
pc1=make_pc(1);pc2=make_pc(2)
function ref(value)return {get=function()return value end} end
function chat_command(pc,line,sender)
    packet={MessageBody=line,SenderData=sender or {}}
    hooks['/Script/JagexChatBackend.PlayerChatComponent:Server_SendChatMessage'].pre(ref(pc.chat),ref(packet),ref({}))
end
'''
