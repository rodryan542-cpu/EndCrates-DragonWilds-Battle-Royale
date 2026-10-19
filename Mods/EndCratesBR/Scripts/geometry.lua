local G = {}
function G.finite(n) return type(n)=='number' and n==n and n~=math.huge and n~=-math.huge end
function G.point(p)
    return type(p)=='table' and G.finite(p.x) and G.finite(p.y) and G.finite(p.z)
        and math.abs(p.x)<=10000000 and math.abs(p.y)<=10000000 and math.abs(p.z)<=10000000
end
function G.distance2(a,b) return (a.x-b.x)^2+(a.y-b.y)^2 end
function G.distance3(a,b) return G.distance2(a,b)+(a.z-b.z)^2 end
function G.inside(p,center,radius) return G.point(p) and G.distance2(p,center)<=radius^2 end
function G.copy(p) return {x=p.x,y=p.y,z=p.z} end
local function integer(c,key,low,high)
    local n=c[key]
    assert(G.finite(n) and n%1==0 and n>=low and n<=high, 'Invalid config: '..key)
end
function G.validate(c,complete)
    integer(c,'players_per_match',20,20)
    integer(c,'max_active_matches',1,50)
    integer(c,'max_loading_matches',1,c.max_active_matches)
    integer(c,'spawn_budget_per_tick',1,20)
    for _,key in ipairs({'countdown_seconds','loading_timeout','arrival_tolerance','minimum_spawn_spacing',
        'zone_gap','boundary_grace_seconds','return_timeout','return_retry_seconds','idle_peer_retention',
        'tick_ms','combat_sample_seconds','roster_refresh_seconds','command_budget_per_tick','command_inbox_limit',
        'message_budget_per_tick','max_pending_messages','item_page_size','max_give_count'}) do
        integer(c,key,1,100000)
    end
    integer(c,'match_timeout',0,86400)
    integer(c,'result_history',1,100)
    assert(type(c.ring_enabled)=='boolean' and type(c.ring_stages)=='table','Invalid ring configuration')
    assert(#c.ring_stages>=1 and #c.ring_stages<=10,'Configure between one and ten ring stages')
    local previous=1
    for _,stage in ipairs(c.ring_stages) do
        integer(stage,'hold',0,3600);integer(stage,'shrink',1,3600)
        assert(G.finite(stage.factor) and stage.factor>0 and stage.factor<previous,'Ring stages must shrink to a positive, decreasing radius')
        previous=stage.factor
    end
    assert(G.finite(c.knockout_health) and c.knockout_health>=0,'Invalid knockout health')
    assert(type(c.zones)=='table' and type(c.admin_owner_ids)=='table','Invalid config lists')
    if not complete then return true end
    assert(G.point(c.lobby) and G.finite(c.lobby.radius) and c.lobby.radius>=100,'Record a valid lobby first.')
    assert(#c.zones>0,'Record at least one arena first.')
    local ids={}
    for i,z in ipairs(c.zones) do
        assert(type(z.id)=='string' and z.id:match('^[%w_-]+$') and not ids[z.id], 'Invalid or duplicate arena ID')
        ids[z.id]=true
        assert(G.point(z.center) and G.finite(z.radius) and z.radius>=1000 and z.radius<=100000,'Invalid arena bounds')
        assert(type(z.spawns)=='table' and #z.spawns>=c.players_per_match,'Arena '..z.id..' needs '..c.players_per_match..' recorded spawns.')
        assert(G.distance2(c.lobby,z.center)>(c.lobby.radius+z.radius+c.zone_gap)^2,'Lobby overlaps arena '..z.id)
        for j=1,i-1 do
            local other=c.zones[j]
            assert(G.distance2(z.center,other.center)>(z.radius+other.radius+c.zone_gap)^2,'Arenas overlap: '..z.id..' / '..other.id)
        end
        for j,p in ipairs(z.spawns) do
            assert(G.point(p) and G.inside(p,z.center,z.radius-c.arrival_tolerance),'Spawn outside arena '..z.id)
            for k=1,j-1 do assert(G.distance3(p,z.spawns[k])>=c.minimum_spawn_spacing^2,'Spawns too close in '..z.id) end
        end
    end
    return true
end
return G
