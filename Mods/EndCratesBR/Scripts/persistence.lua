local P={}
local function serialize(v,depth)
    assert(depth<10,'Arena configuration is nested too deeply')
    if type(v)=='string' then return string.format('%q',v) end
    if type(v)=='number' then assert(v==v and math.abs(v)<math.huge,'Non-finite value');return string.format('%.17g',v) end
    if type(v)=='boolean' then return tostring(v) end
    assert(type(v)=='table','Only data can be saved')
    local parts={'{'}
    for k,value in pairs(v) do
        assert(type(k)=='number' or type(k)=='string','Unsupported configuration key')
        parts[#parts+1]='['..serialize(k,depth+1)..']='..serialize(value,depth+1)..','
    end
    parts[#parts+1]='}';return table.concat(parts)
end
function P.path()
    local path=assert(package.searchpath('config',package.path),'Cannot locate the mod configuration')
    return assert(path:match('^(.*[/\\])'))..'arena_state.lua'
end
function P.load(config)
    local path=P.path();local file=io.open(path,'r');if not file then return false end
    local source=file:read('*a');file:close()
    local chunk=assert(load(source,'@arena_state.lua','t',{}))
    local data=chunk();assert(type(data)=='table' and type(data.zones)=='table','Invalid arena data')
    config.lobby=data.lobby;config.zones=data.zones;config.world_id=data.world_id
    -- Starting matches is deliberately not persisted across process/world restarts.
    return true
end
function P.save(config)
    local path=P.path();local temporary=path..'.tmp'
    local file,why=io.open(temporary,'w');if not file then return false,why end
    local ok,result=file:write('return ',serialize({lobby=config.lobby,zones=config.zones,world_id=config.world_id},0),'\n')
    file:close();if not ok then return false,result end
    -- Keep the last successful configuration if Windows refuses the replacement.
    local previous=path..'.previous'
    local old=io.open(path,'r')
    if old then old:close();os.remove(previous);assert(os.rename(path,previous)) end
    local renamed,error_message=os.rename(temporary,path)
    if not renamed then if old then os.rename(previous,path) end;return false,error_message end
    return true
end
return P
