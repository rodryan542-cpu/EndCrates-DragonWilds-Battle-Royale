-- Two bounded linked FIFOs: critical notices bypass catalogue traffic.
local Outbox={};Outbox.__index=Outbox
function Outbox.new(limit) return setmetatable({limit=limit,count=0,lanes={{},{}},keys={},dropped=0},Outbox) end
function Outbox:remove(node)
    local lane=self.lanes[node.lane]
    if node.previous then node.previous.next=node.next else lane.head=node.next end
    if node.next then node.next.previous=node.previous else lane.tail=node.previous end
    if node.key then self.keys[node.key]=nil end
    self.count=self.count-1
end
function Outbox:push(message)
    local key=message.key and message.id..'\0'..message.key
    if key and self.keys[key] then self:remove(self.keys[key]) end
    if self.count>=self.limit then
        -- A full critical queue cannot be displaced by an item-search reply.
        local victim=self.lanes[2].head
        if not victim and not message.priority then self.dropped=self.dropped+1;return false end
        self:remove(victim or self.lanes[1].head);self.dropped=self.dropped+1
    end
    local index=message.priority and 1 or 2;local lane=self.lanes[index]
    local node={message=message,lane=index,key=key,previous=lane.tail}
    if lane.tail then lane.tail.next=node else lane.head=node end
    lane.tail=node;if key then self.keys[key]=node end;self.count=self.count+1
    return true
end
function Outbox:discard(id,key)
    local node=self.keys[id..'\0'..key];if node then self:remove(node) end
end
function Outbox:pop(now)
    while self.count>0 do
        local node=self.lanes[1].head or self.lanes[2].head;self:remove(node)
        local message=node.message
        if not message.expires or now<message.expires then return message end
        self.dropped=self.dropped+1
    end
end
return Outbox
