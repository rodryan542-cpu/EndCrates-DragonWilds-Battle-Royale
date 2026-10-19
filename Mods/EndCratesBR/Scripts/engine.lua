-- Match rules: no Unreal objects, file I/O, or world/asset scans.
local G=require('geometry')
local Ring=require('ring')
local Engine={}; Engine.__index=Engine
function Engine.new(config,driver)
    G.validate(config,false)
    return setmetatable({config=config,driver=driver,peers={},queue={},matches={},next_match=1,
        zone_cursor=0,spawn_cursor=0,paused=false,recent={},metrics={ticks=0,spawn_requests=0,wins=0,draws=0}},Engine)
end
function Engine:call(method,...)
    local fn=self.driver[method]
    if type(fn)~='function' then return false,'Missing adapter method: '..method end
    local ok,a,b=pcall(fn,self.driver,...)
    if not ok then return false,tostring(a) end
    return a,b
end
function Engine:tell(id,message,options) self:call('message',id,message,options) end
function Engine:announce(match,message,options)
    for _,id in ipairs(match.order) do self:tell(id,message,options) end
end
function Engine:count_matches(phase)
    local n=0; for _,m in pairs(self.matches) do if not phase or m.phase==phase then n=n+1 end end
    return n
end
function Engine:readiness()
    if not self.config.enabled then return false,'BR is disabled. An admin must configure and enable it.' end
    if self.paused then return false,'New matches are paused.' end
    if not self.validated_geometry then
        local ok,why=pcall(G.validate,self.config,true)
        if not ok then return false,tostring(why) end
        self.validated_geometry=true
    end
    return true
end
function Engine:register(id,name,token,now)
    assert(type(id)=='string' and id~='','A stable player ID is required')
    local p=self.peers[id]
    if p then
        p.name=name
        if p.token~=token and (p.match or p.state=='queued') then self:eliminate(id,'character reloaded',now) end
        p.token=token
        if not p.connected then
            p.connected=true
            if self.config.enabled and G.point(self.config.lobby) then self:return_to_lobby(id,now) end
        end
        return p
    end
    p={id=id,name=name,token=token,state='unmanaged',connected=true,last_seen=now,stats={rounds=0,wins=0,top3=0}}
    self.peers[id]=p
    if self.config.enabled and G.point(self.config.lobby) then self:return_to_lobby(id,now) end
    return p
end
function Engine:disconnect(id,now)
    local p=self.peers[id]; if not p then return end
    p.connected=false; p.last_seen=now
    self:call('cancel_teleport',id)
    self:eliminate(id,'disconnected',now)
end
function Engine:remove_queued(id)
    for i=#self.queue,1,-1 do if self.queue[i]==id then table.remove(self.queue,i) end end
end
function Engine:return_to_lobby(id,now)
    local p=self.peers[id]; if not p then return end
    p.match=nil; p.target=G.copy(self.config.lobby); p.state='returning'
    p.return_deadline=now+self.config.return_timeout; p.retry_at=now
    p.outside_since=nil
    if p.connected then
        if not self:call('mode',id,'lobby') then
            p.state='return_failed';self:tell(id,'Lobby protection failed. Ask an admin to check BR diagnostics.');return
        end
        local ok=self:call('teleport',id,p.target)
        if not ok then self:tell(id,'Lobby teleport was refused; it will be retried.') end
        p.retry_at=now+self.config.return_retry_seconds
    end
end
function Engine:enqueue(id,now)
    local ready,why=self:readiness(); if not ready then return false,why end
    local p=self.peers[id]
    if not p or not p.connected then return false,'Character is not ready.' end
    if p.state=='queued' then return false,'You are already queued.' end
    if p.state~='lobby' then return false,'Reach the kit lobby before joining the queue.' end
    if p.kit_loading then return false,'Wait for your kit top-up to finish before queuing.' end
    local snapshot=self:call('snapshot',id)
    if not snapshot or not snapshot.ready or not G.inside(snapshot,self.config.lobby,self.config.lobby.radius) then
        return false,'Stand inside the kit lobby to queue.'
    end
    p.state='queued'; self.queue[#self.queue+1]=id
    self:tell(id,'Queued: '..#self.queue..' waiting; '..self.config.players_per_match..' needed for a match.')
    return true
end
function Engine:leave(id,now)
    local p=self.peers[id]; if not p then return false,'You are not in BR.' end
    p.autoqueue=false;p.requeue=nil
    if p.state=='queued' then self:remove_queued(id); p.state='lobby'; return true end
    if p.match then self:eliminate(id,'left the match',now); return true end
    return false,'You are not queued or playing.'
end
function Engine:eliminate(id,reason,now,placement)
    local p=self.peers[id]; if not p then return end
    self:remove_queued(id)
    local m=p.match and self.matches[p.match]
    if m then
        if m.phase~='active' then self:cancel(m.id,'A player left before the start.',now,true,id); return end
        if m.alive[id] then
            self:call('clear_notices',id,m.id)
            m.results[id]={id=id,name=p.name,place=placement or m.alive_count,reason=reason}
            m.alive[id]=nil; m.alive_count=m.alive_count-1
            self:tell(id,'Eliminated: '..reason..'. Placement #'..m.results[id].place..'.',{priority=true})
            m.feed[#m.feed+1]=p.name
            p.requeue=p.autoqueue or nil
        end
    end
    if G.point(self.config.lobby) then self:return_to_lobby(id,now) else p.state='unmanaged';p.match=nil end
end
function Engine:eliminate_batch(entries,now)
    local counts={}
    for _,entry in ipairs(entries) do
        local p=self.peers[entry.id];local m=p and p.match and self.matches[p.match]
        if m and m.phase=='active' and m.alive[entry.id] and not counts[entry.id] then
            counts[entry.id]=true;counts[m]= (counts[m] or 0)+1
        end
    end
    local places={}
    for m,n in pairs(counts) do if type(m)=='table' then places[m.id]=m.alive_count-n+1 end end
    local processed={}
    for _,entry in ipairs(entries) do
        if not processed[entry.id] then
            processed[entry.id]=true
            local p=self.peers[entry.id];self:eliminate(entry.id,entry.reason,now,p and places[p.match])
        end
    end
end
function Engine:queue_position(id)
    for i,pid in ipairs(self.queue) do if pid==id then return i end end
end
function Engine:standings(m)
    local rows={};for _,row in pairs(m.results) do rows[#rows+1]=row end
    table.sort(rows,function(a,b)if a.place~=b.place then return a.place<b.place end;return a.id<b.id end)
    return rows
end
function Engine:flush_feed(m)
    if #m.feed==0 then return end
    local names={};for i=1,math.min(3,#m.feed) do names[i]=m.feed[i] end
    local text=table.concat(names,', ')..(#m.feed>3 and ' + '..(#m.feed-3)..' more' or '')
    self:announce(m,'Out: '..text..'. '..m.alive_count..' remain.');m.feed={}
end
function Engine:can_damage(attacker,victim)
    local a,b=self.peers[attacker],self.peers[victim]
    if a and a.state=='unmanaged' then a=nil end
    if b and b.state=='unmanaged' then b=nil end
    if not a and not b then return nil end
    if not a or not b or not a.match or a.match~=b.match then return false end
    local m=self.matches[a.match]
    return m and m.phase=='active' and m.alive[attacker]==true and m.alive[victim]==true or false
end
function Engine:free_zone()
    local busy={}; for _,m in pairs(self.matches) do busy[m.zone.id]=true end
    for offset=1,#self.config.zones do
        local i=(self.zone_cursor+offset-1)%#self.config.zones+1
        if not busy[self.config.zones[i].id] then self.zone_cursor=i; return self.config.zones[i] end
    end
end
function Engine:admit(now)
    if #self.queue<self.config.players_per_match or not self.config.enabled or self.paused then return end
    if self:count_matches()>=self.config.max_active_matches or self:count_matches('loading')>=self.config.max_loading_matches then return end
    if not self:readiness() then return end
    local zone=self:free_zone(); if not zone then return end
    local order={}
    while #order<self.config.players_per_match and #self.queue>0 do
        local id=table.remove(self.queue,1); local p=self.peers[id]
        if p and p.connected and p.state=='queued' then order[#order+1]=id end
    end
    if #order<self.config.players_per_match then
        for i=#order,1,-1 do table.insert(self.queue,1,order[i]) end
        return
    end
    local id=self.next_match; self.next_match=id+1
    local m={id=id,zone=zone,order=order,alive={},alive_count=#order,phase='loading',next_spawn=1,
        deadline=now+self.config.loading_timeout,targets={},results={},feed={}}
    self.matches[id]=m
    local slots={}; for i=1,#zone.spawns do slots[i]=i end
    -- Shuffle the recorded, checked spawn points; never guess terrain heights.
    for i=#slots,2,-1 do
        local j=self.driver.random and self.driver:random(i) or math.random(i)
        assert(type(j)=='number' and j%1==0 and j>=1 and j<=i,'Invalid random source')
        slots[i],slots[j]=slots[j],slots[i]
    end
    for i,pid in ipairs(order) do
        local p=self.peers[pid]; p.match=id;p.state='loading';m.alive[pid]=true
        m.targets[pid]=G.copy(zone.spawns[slots[i]])
    end
    self:announce(m,'Match '..id..' assigned to '..zone.id..'. Loading the arena.')
end
function Engine:cancel(id,reason,now,requeue,exclude)
    local m=self.matches[id]; if not m then return end
    self.matches[id]=nil
    for _,pid in ipairs(m.order) do
        local p=self.peers[pid]
        if p and p.match==id then
            self:call('clear_notices',pid,id)
            p.requeue=requeue and p.connected and pid~=exclude or nil
            self:return_to_lobby(pid,now)
            self:tell(pid,'Match cancelled: '..reason,{priority=true})
        end
    end
end
function Engine:finish(m,now,timeout)
    for _,id in ipairs(m.order) do self:call('clear_notices',id,m.id) end
    local winner=nil
    if not timeout and m.alive_count==1 then for id in pairs(m.alive) do winner=id end end
    if winner then
        m.results[winner]={id=winner,name=self.peers[winner].name,place=1,reason='victor'}
        self.metrics.wins=self.metrics.wins+1
        self:announce(m,'VICTOR: '..self.peers[winner].name..' wins '..m.zone.id..'!')
    else self.metrics.draws=self.metrics.draws+1;self:announce(m,timeout and 'Time limit reached: draw.' or 'No survivors: draw.',{priority=true}) end
    for id in pairs(m.alive) do
        if not m.results[id] then m.results[id]={id=id,name=self.peers[id].name,place=1,reason='draw'} end
    end
    local result={id=m.id,zone=m.zone.id,ended_at=now,winner=winner,rows=self:standings(m),draw=not winner}
    self.recent[#self.recent+1]=result
    if #self.recent>self.config.result_history then table.remove(self.recent,1) end
    for _,row in ipairs(result.rows) do
        local p=self.peers[row.id]
        if p then
            p.last_result=result
            local s=p.stats;s.rounds=s.rounds+1;s.wins=s.wins+(row.id==winner and 1 or 0)
            s.top3=s.top3+(row.place<=3 and 1 or 0);s.best=math.min(s.best or row.place,row.place);s.last=row.place
        end
    end
    self.matches[m.id]=nil
    for _,id in ipairs(m.order) do local p=self.peers[id];if p and p.match==m.id then p.requeue=p.autoqueue or nil;self:return_to_lobby(id,now) end end
end
function Engine:spawn_work(now)
    local loading={};for id,m in pairs(self.matches) do if m.phase=='loading' and m.next_spawn<=#m.order then loading[#loading+1]=id end end
    table.sort(loading)
    if #loading==0 then return end
    for _=1,self.config.spawn_budget_per_tick do
        self.spawn_cursor=self.spawn_cursor%#loading+1
        local m=self.matches[loading[self.spawn_cursor]]
        if m and m.next_spawn<=#m.order then
            local id=m.order[m.next_spawn];m.next_spawn=m.next_spawn+1
            self.metrics.spawn_requests=self.metrics.spawn_requests+1
            local protected=self:call('mode',id,'staging')
            local teleported=protected and self:call('teleport',id,m.targets[id])
            if not teleported then self:cancel(m.id,'Arena teleport or protection failed.',now,false) end
        end
    end
end
function Engine:tick(now,external_eliminations)
    assert(G.finite(now),'Invalid clock')
    now=math.max(now,self.last_now or now);self.last_now=now
    self.metrics.ticks=self.metrics.ticks+1
    local pending_deaths={}
    for _,entry in ipairs(external_eliminations or {}) do
        local p=self.peers[entry.id];local m=p and p.match and self.matches[p.match]
        if m then
            if m.phase=='active' then pending_deaths[#pending_deaths+1]=entry
            else self:eliminate(entry.id,entry.reason,now) end
        end
    end
    -- Finish returning players before admitting queued groups.
    local evict={}
    for id,p in pairs(self.peers) do
        if p.connected and p.state=='returning' then
            local s=self:call('snapshot',id)
            if s and s.ready and G.inside(s,self.config.lobby,self.config.lobby.radius) then
                p.state='lobby';p.target=nil
                self:tell(id,'Kit lobby: !items <search>, !give <item> [count], then !ffa. !brhelp lists all commands.')
                if p.requeue then p.requeue=nil;self:enqueue(id,now) end
            elseif now>=p.return_deadline then
                p.state='return_failed';self:tell(id,'Lobby return timed out. Use !lobby to retry; queuing and item grants are locked.')
            elseif now>=p.retry_at then self:call('mode',id,'lobby');self:call('teleport',id,p.target);p.retry_at=now+self.config.return_retry_seconds end
        elseif not p.connected and not p.match and now-p.last_seen>self.config.idle_peer_retention then evict[#evict+1]=id end
    end
    for _,id in ipairs(evict) do self.peers[id]=nil end
    self:admit(now);self:spawn_work(now)
    local cancelled={}
    for _,m in pairs(self.matches) do
        if m.phase=='loading' then
            local arrived=m.next_spawn>#m.order
            if arrived then
                for _,id in ipairs(m.order) do
                    local s=self:call('snapshot',id)
                    if not s or not s.ready or not G.point(s) or G.distance3(s,m.targets[id])>self.config.arrival_tolerance^2 then arrived=false;break end
                end
            end
            if arrived then
                m.phase='countdown';m.starts_at=now+self.config.countdown_seconds
                for _,id in ipairs(m.order) do self.peers[id].state='countdown' end
                self:announce(m,'All '..#m.order..' players arrived. Fight starts in '..self.config.countdown_seconds..' seconds.',{priority=true,key='phase:'..m.id,ttl=self.config.countdown_seconds})
            elseif now>=m.deadline then cancelled[#cancelled+1]=m.id end
        elseif m.phase=='countdown' and now<m.starts_at then
            local seconds=math.ceil(m.starts_at-now)
            if seconds<=5 and not m.last_countdown then
                m.last_countdown=seconds;self:announce(m,'Fight in '..seconds..'...', {priority=true,key='phase:'..m.id,ttl=seconds})
            end
        elseif m.phase=='countdown' and now>=m.starts_at then
            local ok=true
            for _,id in ipairs(m.order) do if not self:call('mode',id,'active') then ok=false end end
            if ok then
                m.phase='active';m.started_at=now
                local r=Ring.at(self.config,m.zone,0);m.ring_key=r.stage..':'..r.phase
                for _,id in ipairs(m.order) do self.peers[id].state='active' end
                self:announce(m,'FIGHT! Last player standing wins. '..(self.config.ring_enabled and 'The circle will shrink. Use !ring to check it.' or 'Stay inside '..m.zone.id..'.'),{priority=true,key='phase:'..m.id,ttl=15})
            else cancelled[#cancelled+1]=m.id end
        end
    end
    for _,id in ipairs(cancelled) do self:cancel(id,'Loading or combat setup failed.',now,false) end
    -- Resolve the entire sample before awarding a win: simultaneous knockouts are a draw.
    local eliminations=pending_deaths
    for _,m in pairs(self.matches) do
        if m.phase=='active' and now>=(m.next_check or 0) then
            m.next_check=now+self.config.combat_sample_seconds
            m.ring=Ring.at(self.config,m.zone,now-m.started_at)
            local key=m.ring.stage..':'..m.ring.phase
            if self.config.ring_enabled and key~=m.ring_key then
                m.ring_key=key
                self:announce(m,m.ring.phase=='holding' and ('Circle '..m.ring.stage..' closes in '..m.ring.remaining..'s. !ring for center and radius.')
                    or m.ring.phase=='closing' and ('Circle '..m.ring.stage..' is closing! Reach the center; !ring for coordinates.')
                    or 'Final circle reached. Finish the fight!',{priority=true,key='ring:'..m.id,ttl=15})
            end
            for _,id in ipairs(m.order) do
                if m.alive[id] then
                    local p=self.peers[id];local s=self:call('snapshot',id)
                    local reason=nil
                    if not p.connected or not s then reason='disconnected'
                    elseif s.token~=p.token then reason='character reloaded'
                    elseif not s.ready then reason='character unavailable'
                    elseif not G.finite(s.health) then reason='health unavailable'
                    elseif not G.point(s) then reason='position unavailable'
                    elseif s.health<=self.config.knockout_health then reason='knocked out'
                    elseif not G.inside(s,m.zone.center,m.ring.radius) then
                        if not p.outside_since then p.outside_since=now;self:tell(id,'Outside the safe circle! Return within '..self.config.boundary_grace_seconds..' seconds. !ring shows its center.',{priority=true,key='boundary:'..m.id,ttl=self.config.boundary_grace_seconds}) end
                        if now-p.outside_since>=self.config.boundary_grace_seconds then reason='left the arena' end
                    else p.outside_since=nil end
                    if reason then eliminations[#eliminations+1]={id=id,reason=reason} end
                end
            end
        end
    end
    self:eliminate_batch(eliminations,now)
    for _,m in pairs(self.matches) do if m.phase=='active' then self:flush_feed(m) end end
    local finished={}
    for id,m in pairs(self.matches) do
        local timeout=m.phase=='active' and self.config.match_timeout>0 and now-m.started_at>=self.config.match_timeout
        if m.phase=='active' and (m.alive_count<=1 or timeout) then finished[#finished+1]={id=id,timeout=timeout} end
    end
    for _,f in ipairs(finished) do local m=self.matches[f.id];if m then self:finish(m,now,f.timeout) end end
end
function Engine:shutdown(now)
    self.paused=true
    local ids={};for id in pairs(self.matches) do ids[#ids+1]=id end
    for _,id in ipairs(ids) do self:cancel(id,'BR stopped.',now,false) end
    self.queue={}
    for id,p in pairs(self.peers) do p.match=nil;p.state='unmanaged';p.requeue=nil;p.autoqueue=false;self:call('release',id) end
    self:call('cancel_work')
end
return Engine
