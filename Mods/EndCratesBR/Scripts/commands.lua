local Parse=require('parse')
local G=require('geometry')
local Ring=require('ring')
local Persistence=require('persistence')
local Commands={};Commands.__index=Commands
function Commands.new(engine,adapter,catalogue)
    return setmetatable({engine=engine,adapter=adapter,catalogue=catalogue,limits={},pages={},last_catalogue_refresh=-math.huge},Commands)
end
function Commands:handles(line)
    local name=type(line)=='string' and line:match('^%s*!([%w_]+)')
    return name and ({ffa=true,leave=true,lobby=true,items=true,give=true,more=true,br=true,brhelp=true,brstatus=true,
        queue=true,autoqueue=true,matches=true,ring=true,stats=true,top=true,results=true,kit=true})[name:lower()] or false
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
    assert(s and s.ready and G.inside(s,e.config.lobby,e.config.lobby.radius),'Stand inside the kit lobby first.')
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
            return self:reply(id,'!ffa; !queue; !autoqueue on|off; !leave; !lobby; !matches [page]; !ring; !stats; !top; !results [page]; !items <words>; !give <item> [count]; !more; !kit add|remove|show|load|clear. Equip through the normal inventory menu.')
        elseif name=='brstatus' then
            return self:reply(id,'Your state='..p.state..'; waiting='..#e.queue..'; matches='..e:count_matches()..'/'..e.config.max_active_matches..'; 20 players per match.')
        elseif name=='ffa' then
            local accepted,message=e:enqueue(id,now);if not accepted then self:reply(id,message) end
        elseif name=='queue' then
            local position=e:queue_position(id)
            return self:reply(id,(position and ('Position '..position..' of '..#e.queue..'; '..math.floor((position-1)/20)..' full groups ahead.') or ('You are not queued; '..#e.queue..' waiting.'))..(e.paused and ' Admissions paused.' or ''))
        elseif name=='autoqueue' then
            assert(args[1]=='on' or args[1]=='off','Use !autoqueue on or !autoqueue off.')
            p.autoqueue=args[1]=='on';if not p.autoqueue then p.requeue=nil end
            return self:reply(id,p.autoqueue and 'Automatic requeue enabled after your next lobby return. !leave or !lobby turns it off.' or 'Automatic requeue disabled.')
        elseif name=='matches' then
            local rows={};for _,m in pairs(e.matches) do rows[#rows+1]=m end
            table.sort(rows,function(a,b)return a.id<b.id end)
            local page=Parse.number(args[1] or 1,1,100,true,'Page');local parts={}
            for i=(page-1)*10+1,math.min(page*10,#rows) do
                local m=rows[i];parts[#parts+1]='#'..m.id..' '..m.zone.id..': '..m.phase..', '..m.alive_count..'/20'
            end
            return self:reply(id,#parts>0 and (table.concat(parts,'; ')..' (page '..page..'/'..math.ceil(#rows/10)..')') or 'No matches on this page.')
        elseif name=='ring' then
            local m=p.match and e.matches[p.match];assert(m and m.phase=='active','Join an active match to check its circle.')
            local r=Ring.at(e.config,m.zone,math.max(now,e.last_now or now)-m.started_at)
            local s=self.adapter:snapshot(id);local distance=G.point(s) and math.sqrt(G.distance2(s,m.zone.center)) or nil
            return self:reply(id,string.format('Circle %d: %s. Center X=%.0f Y=%.0f; radius=%.0f units%s%s.',r.stage,r.phase,
                m.zone.center.x,m.zone.center.y,r.radius,distance and string.format('; you are %.0f units from center',distance) or '',r.remaining>0 and '; '..r.remaining..'s to next phase' or ''))
        elseif name=='stats' then
            local s=p.stats;return self:reply(id,'Session: '..s.rounds..' rounds; '..s.wins..' wins; '..s.top3..' top-three finishes; best='..(s.best or '-')..'; last='..(s.last or '-')..'.')
        elseif name=='top' then
            local rows={};for _,peer in pairs(e.peers) do if peer.stats.rounds>0 then rows[#rows+1]=peer end end
            table.sort(rows,function(a,b)
                if a.stats.wins~=b.stats.wins then return a.stats.wins>b.stats.wins end
                if a.stats.top3~=b.stats.top3 then return a.stats.top3>b.stats.top3 end
                return a.id<b.id
            end)
            local parts={};for i=1,math.min(10,#rows) do local row=rows[i];parts[#parts+1]=i..'. '..row.name..' ('..row.stats.wins..' wins, '..row.stats.rounds..' rounds)' end
            return self:reply(id,#parts>0 and table.concat(parts,'; ') or 'No completed rounds yet.')
        elseif name=='results' then
            local result=p.last_result;assert(result,'You have no completed round yet.')
            local page=Parse.number(args[1] or 1,1,2,true,'Page');local parts={}
            for i=(page-1)*10+1,math.min(page*10,#result.rows) do
                local row=result.rows[i];parts[#parts+1]='#'..row.place..' '..row.name..(row.reason=='draw' and ' (draw)' or '')
            end
            return self:reply(id,'Match '..result.id..' / '..result.zone..(result.draw and ' / DRAW' or '')..': '..table.concat(parts,'; ')..' (page '..page..'/2)')
        elseif name=='kit' then return self:kit(id,args)
        elseif name=='leave' then
            local left,message=e:leave(id,now);self:reply(id,left and 'You left the queue/match.' or message)
        elseif name=='lobby' then
            assert(e.config.enabled and G.point(e.config.lobby),'The kit lobby is not configured.')
            p.autoqueue=false;p.requeue=nil
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
function Commands:kit(id,args)
    local p=self.engine.peers[id];p.kit=p.kit or {};local sub=args[1] or 'show'
    if sub=='show' then
        local parts={};for _,row in ipairs(p.kit) do parts[#parts+1]=row.name..' x'..row.count end
        return self:reply(id,#parts>0 and table.concat(parts,'; ') or 'Kit is empty. !kit add <exact item> [count] saves an entry; !kit load tops it up in the lobby.')
    end
    self:lobby_access(id)
    assert(not self.kit_jobs or not self.kit_jobs[id],'Your kit is still loading.')
    if sub=='clear' then p.kit={};return self:reply(id,'Saved kit cleared. Inventory unchanged.') end
    if sub=='load' then
        assert(#p.kit>0,'Add some items to your kit first.')
        assert(p.state=='lobby','Leave the queue before loading a saved kit.')
        self.kit_jobs=self.kit_jobs or {};self.kit_order=self.kit_order or {}
        local rows={};for i,row in ipairs(p.kit) do rows[i]={name=row.name,count=row.count} end
        self.kit_jobs[id]={rows=rows,next=1,token=p.token};self.kit_order[#self.kit_order+1]=id;p.kit_loading=true
        return self:reply(id,'Kit top-up queued. Stay in the lobby until it finishes; existing inventory is counted.')
    end
    assert(sub=='add' or sub=='remove','Use !kit add <item> [count], remove <item>, show, load, or clear.')
    local rest={};for i=2,#args do rest[#rest+1]=args[i] end
    local query,count=Parse.search_count(rest,1)
    local row=self.catalogue:unique(query)
    if sub=='add' then
        count=Parse.number(count,1,self.engine.config.max_give_count,true,'Count')
        for _,entry in ipairs(p.kit) do if entry.name==row.name then entry.count=count;return self:reply(id,'Updated '..row.name..' x'..count..'.') end end
        assert(#p.kit<12,'A kit can contain at most 12 different items.')
        p.kit[#p.kit+1]={name=row.name,count=count};self:reply(id,'Saved '..row.name..' x'..count..'.')
    else
        for i,entry in ipairs(p.kit) do if entry.name==row.name then table.remove(p.kit,i);return self:reply(id,'Removed '..row.name..' from the saved kit.') end end
        error('That item is not in your saved kit.',0)
    end
end
function Commands:pump_kits()
    if not self.kit_order or #self.kit_order==0 then return end
    -- One item grant globally per update; rotate players between grants.
    local id=table.remove(self.kit_order,1);local job=self.kit_jobs[id]
    if not job then return end
    local ok,why=pcall(function()
        local p=self.engine.peers[id];assert(p and p.connected and p.token==job.token,'Character changed.')
        self:lobby_access(id)
        local row=job.rows[job.next]
        local actual,name,missing=self.catalogue:topup(self.adapter,id,row.name,row.count)
        if actual<missing then self:reply(id,name..': added '..actual..'/'..missing..'; inventory capacity reached.') end
    end)
    if not ok then
        self.kit_jobs[id]=nil;local p=self.engine.peers[id];if p then p.kit_loading=nil end
        self:reply(id,'Kit loading stopped: '..tostring(why):gsub('^.-:%d+: ',''));return
    end
    job.next=job.next+1
    if job.next>#job.rows then self.kit_jobs[id]=nil;self.engine.peers[id].kit_loading=nil;self:reply(id,'Kit top-up finished. Equip your items, then !ffa.')
    else self.kit_order[#self.kit_order+1]=id end
end
function Commands:admin(id,args,now)
    assert(self.adapter:is_admin(id),'This command is restricted to the server owner/admin allowlist.')
    local sub=args[1] or 'help';local e=self.engine;local c=e.config
    if sub=='help' then
        return self:reply(id,'Setup: !br lobby [radius]; !br zone <id> <radius>; !br spawn <id> (record 20); !br arenas [page]; !br removespawn <id> [index]; !br removezone <id>; !br save; !br enable. Management: !br diagnose; pause; resume; cancel <match>; disable; whoami.')
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
    elseif sub=='arenas' then
        local page=Parse.number(args[2] or 1,1,13,true,'Page');local parts={}
        for i=(page-1)*10+1,math.min(page*10,#c.zones) do local z=c.zones[i];parts[#parts+1]=z.id..' (radius '..z.radius..', '..#z.spawns..'/20 spawns)' end
        return self:reply(id,#parts>0 and table.concat(parts,'; ') or 'No arenas on this page.')
    end
    assert(not c.enabled and e:count_matches()==0,'Disable BR before changing arena geometry.')
    e.validated_geometry=false
    if sub=='removezone' or sub=='removespawn' then
        for i,z in ipairs(c.zones) do
            if z.id==args[2] then
                if sub=='removezone' then table.remove(c.zones,i);return self:reply(id,'Removed arena '..z.id..'. Use !br save after editing.') end
                local index=Parse.number(args[3] or #z.spawns,1,#z.spawns,true,'Spawn index')
                table.remove(z.spawns,index);return self:reply(id,'Removed spawn '..index..' from '..z.id..'. Use !br save after editing.')
            end
        end
        error('Arena not found.',0)
    end
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
