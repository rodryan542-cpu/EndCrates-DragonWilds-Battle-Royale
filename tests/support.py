from pathlib import Path
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / 'Mods' / 'EndCratesBR' / 'Scripts'

def runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().scripts_path = SCRIPTS.as_posix() + '/?.lua'
    lua.execute('package.path = scripts_path')
    return lua

MATCH_MOCKS = '''
G=require('geometry');Engine=require('engine');config=require('config')
config.enabled=true;config.pvp_world_confirmed=true
config.lobby={x=0,y=0,z=500,radius=1500};config.zones={}
function add_zone(i)
    local zone={id='zone'..i,center={x=i*100000,y=100000,z=500},radius=12000,spawns={}}
    for n=1,20 do
        local angle=2*math.pi*n/20
        zone.spawns[n]={x=zone.center.x+4000*math.cos(angle),y=zone.center.y+4000*math.sin(angle),z=500}
    end
    config.zones[#config.zones+1]=zone
end
add_zone(1);add_zone(2);add_zone(3);add_zone(4)
driver={players={},messages={},calls={},auto_teleport=true,mode_ok=true,samples=0}
function driver:random(n) return 1 end
function driver:message(id,message) self.messages[#self.messages+1]={id=id,text=message};return true end
function driver:snapshot(id) self.samples=self.samples+1;return self.players[id] end
function driver:mode(id,mode)
    self.calls[#self.calls+1]={id=id,mode=mode}
    if mode~='active' and self.players[id] then self.players[id].health=100 end
    return self.mode_ok
end
function driver:release(id) self.calls[#self.calls+1]={id=id,mode='release'};return true end
function driver:teleport(id,point)
    self.calls[#self.calls+1]={id=id,target=point}
    if self.auto_teleport and self.players[id] then
        self.players[id].x=point.x;self.players[id].y=point.y;self.players[id].z=point.z
    end
    return self.teleport_ok~=false
end
engine=Engine.new(config,driver)
function join(first,last)
    for n=first,last do
        local id='p'..n
        driver.players[id]={x=0,y=0,z=500,ready=true,health=100,token=id..'_pawn'}
        engine:register(id,'Player '..n,id..'_pawn',0)
    end
    engine:tick(0)
end
function queue(first,last)
    for n=first,last do assert(engine:enqueue('p'..n,0)) end
end
function activate(total)
    join(1,total);queue(1,total)
    for now=0,1000 do
        engine:tick(now)
        if engine:count_matches('active')==math.min(math.floor(total/config.players_per_match),config.max_active_matches,#config.zones) then
            clock=now;return
        end
    end
    error('Matches never activated')
end
function messages_containing(needle)
    local count=0;for _,m in ipairs(driver.messages) do if m.text:find(needle,1,true) then count=count+1 end end;return count
end
'''
