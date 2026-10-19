-- Circle timing is derived from elapsed time, so a slow tick cannot skip a stage.
local Ring={}
function Ring.at(config,zone,elapsed)
    if not config.ring_enabled then return {radius=zone.radius,stage=0,phase='fixed',remaining=0} end
    local previous=1;elapsed=math.max(0,elapsed)
    for i,stage in ipairs(config.ring_stages) do
        if elapsed<stage.hold then
            return {radius=zone.radius*previous,stage=i,phase='holding',remaining=math.ceil(stage.hold-elapsed),target=zone.radius*stage.factor}
        end
        elapsed=elapsed-stage.hold
        if elapsed<stage.shrink then
            return {radius=zone.radius*(previous+(stage.factor-previous)*elapsed/stage.shrink),stage=i,
                phase='closing',remaining=math.ceil(stage.shrink-elapsed),target=zone.radius*stage.factor}
        end
        elapsed=elapsed-stage.shrink;previous=stage.factor
    end
    return {radius=zone.radius*previous,stage=#config.ring_stages,phase='final',remaining=0}
end
return Ring
