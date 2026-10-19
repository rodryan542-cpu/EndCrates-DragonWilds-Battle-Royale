local Config=require('config')
local Engine=require('engine')
local Adapter=require('adapter')
local Commands=require('commands')
local Catalogue=require('catalogue')
local Persistence=require('persistence')
local function log(message) print('[EndCratesBR] '..tostring(message)..'\n') end
local function valid(o) local ok,v=pcall(function()return o and o:IsValid()end);return ok and v==true end
local requested_start=Config.enabled;Config.enabled=false
local loaded,load_error=pcall(Persistence.load,Config)
if not loaded then log('Arena data could not be read: '..tostring(load_error)) end
local adapter=Adapter.new(Config,log)
local engine=Engine.new(Config,adapter)
local catalogue=Catalogue.new()
local commands=Commands.new(engine,adapter,catalogue)
local inbox,deaths={},{}
local pending,healthy=false,true
local world,next_refresh=nil,0
local function stop()
    Config.enabled=false;engine:shutdown(os.time());inbox={};deaths={}
end
local function enable()
    require('geometry').validate(Config,true)
    local ok,why=adapter:preflight();assert(ok,why)
    Config.enabled=true;engine.paused=false
end
local function refresh(now)
    local current=FindFirstOf('DominionGameStateBase')
    if not valid(current) or not current:HasAuthority() then
        if world then
            stop();world=nil
            adapter=Adapter.new(Config,log);engine=Engine.new(Config,adapter)
            commands=Commands.new(engine,adapter,catalogue)
        end
        return false
    end
    if world and world~=current:GetAddress() then
        stop()
        adapter=Adapter.new(Config,log);engine=Engine.new(Config,adapter)
        commands=Commands.new(engine,adapter,catalogue)
        log('World changed. BR is disabled until the new world is checked.')
    end
    world=current:GetAddress()
    if requested_start then
        requested_start=false;local ok,why=pcall(enable)
        if not ok then log('Automatic start refused: '..tostring(why)) end
    end
    local seen=adapter:refresh()
    for id,p in pairs(seen) do
        local peer=engine:register(id,p.name:gsub('[<>&]',''):sub(1,64),p.token,now)
        if Config.enabled and peer.state=='unmanaged' then engine:return_to_lobby(id,now) end
    end
    for id,p in pairs(engine.peers) do if p.connected and not seen[id] then engine:disconnect(id,now) end end
    for id in pairs(adapter.peers) do if not engine.peers[id] then adapter:forget(id);commands:forget(id) end end
    return true
end
local function update()
    if not healthy then return end
    local now=os.time()
    if now>=next_refresh then next_refresh=now+Config.roster_refresh_seconds;refresh(now) end
    if not world then return end
    for _=1,Config.command_budget_per_tick do
        local entry=table.remove(inbox,1);if not entry then break end
        local peer=engine.peers[entry.id]
        if peer and peer.connected and peer.token==entry.token then commands:run(entry.id,entry.line,now) end
    end
    for id in pairs(deaths) do
        local p=engine.peers[id]
        if p and p.match then engine:eliminate(id,'native death',now) end
    end
    deaths={}
    adapter:pump_teleports()
    if Config.enabled then engine:tick(now) end
    adapter:flush_messages()
end
local required={
    '/Script/JagexChatBackend.PlayerChatComponent:Server_SendChatMessage',
    '/Script/JagexChatBackend.PlayerChatComponent:Client_ReceiveChatMessage',
    '/Script/Dominion.DamageComponent:CanBeDamagedBy',
    '/Script/Dominion.HealthComponent:OnDeathEvent',
    '/Script/Dominion.HealthComponent:SetIsImmortal',
    '/Script/Dominion.DamageComponent:SetIsInvulnerable',
    '/Script/Dominion.DominionPlayerCharacter:BP_TriggerDelayedTeleport',
    '/Script/Dominion.DominionPlayerCharacter:IsTeleporting',
    '/Script/Dominion.DominionPlayerController:IsPlayerReady',
    '/Script/Engine.Actor:AddComponentByClass',
    '/Script/Engine.ActorComponent:SetComponentTickEnabled',
    '/Script/Engine.TimelineComponent',
}
for _,path in ipairs(required) do
    if not valid(StaticFindObject(path)) then healthy=false;log('Required API is missing: '..path) end
end
local function hook(path,pre,post)
    local ok,why=pcall(RegisterHook,path,pre,post)
    if not ok then healthy=false;log('Hook registration failed: '..path..': '..tostring(why)) end
end
if healthy then
    hook(required[1],function(context,data)
        if not healthy then return end
        local ok,why=pcall(function()
            local component=context:get();local owner=component:GetOwner()
            if not valid(owner) or not owner:HasAuthority() then return end
            local message=data:get();local body=message.MessageBody
            local line=type(body)=='string' and body or body:ToString()
            if not commands:handles(line) then return end
            local id=adapter:actor_id(owner);local peer=id and engine.peers[id]
            if not peer or not peer.connected then return end
            -- Derive identity from the RPC owner, never the caller's SenderData.
            message.MessageBody=''
            if #line>1000 or not commands:allowed(id,os.time()) then return end
            if #inbox>=Config.command_inbox_limit then return end
            inbox[#inbox+1]={id=id,line=line,token=peer.token}
        end)
        if not ok then log('Chat input rejected: '..tostring(why)) end
    end,function() end)
    hook(required[3],function()end,function(context,instigator)
        if not healthy or not Config.enabled then return end
        local ok,allowed=pcall(function()
            local component=context:get();local owner=component:GetOwner()
            if not valid(owner) or not owner:HasAuthority() then return nil end
            return engine:can_damage(adapter:actor_id(instigator:get()),adapter:component_id(component))
        end)
        if not ok then log('Damage permission check failed; denying damage.');return false end
        if allowed==false then return false end
        -- A BR match never grants damage the native game itself refuses.
    end)
    hook(required[4],function(context)
        if not healthy or not Config.enabled then return end
        local ok,id=pcall(adapter.component_id,adapter,context:get())
        if ok and id then deaths[id]=true end
    end,function()end)
end
RegisterConsoleCommandHandler('br_stop',function()
    stop();log('BR stopped. Protection locks released.');return true
end)
RegisterConsoleCommandHandler('br_status',function()
    local d=adapter:diagnostics()
    log('Enabled='..tostring(Config.enabled)..'; authority='..tostring(d.authority)..'; session slots='..tostring(d.slots)
        ..'; active matches='..engine:count_matches()..'; queued='..#engine.queue..'; teleports sent='..adapter.teleports_sent
        ..'; dropped old messages='..adapter.dropped_messages)
    return true
end)
LoopAsync(Config.tick_ms,function()
    if pending or not healthy then return end
    pending=true
    ExecuteInGameThread(function()
        local ok,why=pcall(update);pending=false
        if not ok then
            healthy=false;pcall(stop)
            log('BR stopped after a runtime failure: '..tostring(why))
        end
    end)
end)
log(healthy and 'Loaded in setup mode. No arena or player is modified until BR is enabled.' or 'Unavailable for this build; no matches will start.')
