local Parse=require('parse')
local G=require('geometry')
local Persistence=require('persistence')
local Commands={};Commands.__index=Commands
function Commands.new(engine,adapter,catalogue)
    return setmetatable({engine=engine,adapter=adapter,catalogue=catalogue,limits={},pages={},last_catalogue_refresh=-math.huge},Commands)
end
function Commands:handles(line)
    local name=type(line)=='string' and line:match('^%s*!([%w_]+)')
    return name and ({ffa=true,leave=true,lobby=true,items=true,give=true,more=true,br=true,brhelp=true,brstatus=true})[name:lower()] or false
end
function Commands:allowed(id,now)
    local s=self.limits[id]
    if not s or now>=s.reset then s={reset=now+2,count=0};self.limits[id]=s end
    s.count=s.count+1;return s.count<=3
end
function Commands:forget(id) self.limits[id]=nil;self.pages[id]=nil end
function Commands:reply(id,message) self.adapter:message(id,message) end
function Commands:lobby_access(id)
    local e=self.engine;local p=e.peers[id]
    assert(e.config.enabled and p and (p.state=='lobby' or p.state=='queued'),'Item grants are only available in the kit lobby.')
    local s=self.adapter:snapshot(id)
    assert(s.ready and G.inside(s,e.config.lobby,e.config.lobby.radius),'Stand inside the kit lobby first.')
end
function Commands:page(id,rows,start)
    local names={};local finish=math.min(#rows,start+self.engine.config.item_page_size-1)
    for i=start,finish do names[#names+1]=rows[i].name end
    self.pages[id]={rows=rows,next=finish+1}
    self:reply(id,#names==0 and 'End of list.' or (table.concat(names,'; ')..(finish<#rows and ' — !more for more.' or '')))
end
function Commands:run(id,line,now)
    local ok,why=pcall(function()
        local parsed,reason=Parse.parse(line);assert(parsed,reason)
        local name,args=parsed.name,parsed.args
        local e=self.engine;local p=e.peers[id];assert(p and p.connected,'Character is not ready.')
        if name=='brhelp' then
            return self:reply(id,'!ffa: queue for 20; !leave: leave/forfeit; !lobby: return; !items <words>; !give <exact item> [count]; !more; !brstatus. Equip your kit through the normal inventory menu.')
        elseif name=='brstatus' then
            return self:reply(id,'Your state='..p.state..'; waiting='..#e.queue..'; matches='..e:count_matches()..'/'..e.config.max_active_matches..'; 20 players per match.')
        elseif name=='ffa' then
            local accepted,message=e:enqueue(id,now);if not accepted then self:reply(id,message) end
        elseif name=='leave' then
            local left,message=e:leave(id,now);self:reply(id,left and 'You left the queue/match.' or message)
        elseif name=='lobby' then
            assert(e.config.enabled and G.point(e.config.lobby),'The kit lobby is not configured.')
            if p.match then e:eliminate(id,'returned to lobby',now) else e:remove_queued(id);e:return_to_lobby(id,now) end
        elseif name=='items' then
            if now-self.last_catalogue_refresh>=60 then self.catalogue:refresh_loaded();self.last_catalogue_refresh=now end
            local rows=self.catalogue:find(Parse.join(args))
            self:reply(id,#rows..' items matched.');self:page(id,rows,1)
        elseif name=='more' then
            local page=self.pages[id];assert(page,'Use !items first.');self:page(id,page.rows,page.next)
        elseif name=='give' then
            self:lobby_access(id)
            local query,count=Parse.search_count(args,1)
            count=Parse.number(count,1,e.config.max_give_count,true,'Count')
            local actual,item=self.catalogue:give(self.adapter,id,query,count)
            self:reply(id,'Added '..actual..' '..item..(actual<count and ' (inventory capacity reached).' or '.'))
        elseif name=='br' then return self:admin(id,args,now)
        end
    end)
    if not ok then self:reply(id,tostring(why):gsub('^.-:%d+: ','')) end
end
function Commands:admin(id,args,now)
    assert(self.adapter:is_admin(id),'This command is restricted to the server owner/admin allowlist.')
    local sub=args[1] or 'help';local e=self.engine;local c=e.config
    if sub=='help' then
        return self:reply(id,'Setup: !br lobby [radius]; !br zone <id> <radius>; !br spawn <id> (record 20); !br save; !br enable. Management: !br diagnose; !br pause; !br resume; !br cancel <match>; !br disable; !br whoami.')
    elseif sub=='whoami' then return self:reply(id,'Your authenticated owner ID: '..self.adapter.peers[id].owner)
    elseif sub=='diagnose' then
        local d=self.adapter:diagnostics();local ok,why=self.adapter:preflight()
        return self:reply(id,'Server authority='..tostring(d.authority)..'; GameSession slots='..tostring(d.slots)..'; arenas='..#c.zones..'; preflight='..tostring(ok)..(why and ': '..why or ''))
    elseif sub=='enable' then
        G.validate(c,true);local ok,why=self.adapter:preflight();assert(ok,why)
        c.enabled=true;e.paused=false;e.validated_geometry=true
        for pid,p in pairs(e.peers) do if p.connected and p.state=='unmanaged' then e:return_to_lobby(pid,now) end end
        return self:reply(id,'BR enabled. Players enter the kit lobby and queue with !ffa.')
    elseif sub=='disable' then e:shutdown(now);c.enabled=false;return self:reply(id,'BR disabled; match protection locks released.')
    elseif sub=='pause' then e.paused=true;return self:reply(id,'New matches paused; existing matches continue.')
    elseif sub=='resume' then e.paused=false;return self:reply(id,'New matches resumed.')
    elseif sub=='cancel' then
        local match=Parse.number(args[2],1,2147483647,true,'Match ID')
        assert(e.matches[match],'Match not found.');e:cancel(match,'Admin cancellation.',now,false);return
    end
    assert(not c.enabled and e:count_matches()==0,'Disable BR before changing arena geometry.')
    e.validated_geometry=false
    local s=self.adapter:snapshot(id);assert(s.ready,'Stand at a fully loaded, safe position first.')
    if sub=='lobby' then
        local radius=Parse.number(args[2] or 1500,100,10000,true,'Lobby radius')
        c.lobby={x=s.x,y=s.y,z=s.z,radius=radius};c.world_id=self.adapter:world_id()
        assert(c.world_id,'The world identifier is unavailable.')
        self:reply(id,'Lobby recorded. Save after recording the arena spawns.')
    elseif sub=='zone' then
        local zid=args[2];assert(zid and zid:match('^[%w_-]+$') and #zid<=40,'Use a short arena ID with letters, numbers, _ or -.')
        for _,z in ipairs(c.zones) do assert(z.id~=zid,'That arena exists already.') end
        assert(#c.zones<128,'Arena count limit reached.')
        local radius=Parse.number(args[3],1000,100000,true,'Arena radius')
        c.zones[#c.zones+1]={id=zid,center=G.copy(s),radius=radius,spawns={}}
        self:reply(id,'Arena '..zid..' recorded. Walk to safe spawn positions and use !br spawn '..zid..'.')
    elseif sub=='spawn' then
        local found=nil;for _,z in ipairs(c.zones) do if z.id==args[2] then found=z end end
        assert(found,'Arena not found.');assert(#found.spawns<128,'Spawn count limit reached.')
        assert(G.inside(s,found.center,found.radius-c.arrival_tolerance),'Spawn is outside the arena.')
        for _,p in ipairs(found.spawns) do assert(G.distance3(s,p)>=c.minimum_spawn_spacing^2,'Too close to another spawn.') end
        found.spawns[#found.spawns+1]=G.copy(s);self:reply(id,'Recorded spawn '..#found.spawns..' for '..found.id..'.')
    elseif sub=='save' then
        G.validate(c,true);local saved,why=Persistence.save(c);assert(saved,'Could not save arena_state.lua: '..tostring(why))
        self:reply(id,'Arena geometry saved. BR stays disabled until !br enable.')
    else error('Unknown admin command. Use !br help.',0) end
end
return Commands
