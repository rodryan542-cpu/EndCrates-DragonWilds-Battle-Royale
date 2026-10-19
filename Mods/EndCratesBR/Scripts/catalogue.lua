local Parse=require('parse')
local Catalogue={};Catalogue.__index=Catalogue
local function valid(o) return o and o:IsValid() end
function Catalogue.new()
    local self=setmetatable({rows={},exact={},cache={},cache_order={},queries={},query_order={}},Catalogue)
    for _,row in ipairs(require('item_data')) do self:add(row) end
    return self
end
function Catalogue:add(row)
    if self.exact[row.path] then return end
    local p=row.path:lower()
    if p:find('deprecated',1,true) or p:find('/deleted/',1,true) or p:find('/futuremajorversion/',1,true) then return end
    self.rows[#self.rows+1]=row;self.exact[row.path]=row
    local key=Parse.key(row.name)
    self.exact[key]=self.exact[key] or {};table.insert(self.exact[key],row)
    self.queries={};self.query_order={}
end
function Catalogue:refresh_loaded()
    for _,obj in ipairs(FindAllOf('ItemData') or {}) do
        if valid(obj) then
            local full=obj:GetFullName();local path=full:match('^[^ ]+ (.+)$')
            if path then self:add({name=obj:GetFName():ToString(),path=path}) end
        end
    end
end
function Catalogue:find(query)
    local key=Parse.trim(query):lower()
    if self.queries[key] then return self.queries[key] end
    local rows={}
    for _,row in ipairs(self.rows) do if Parse.matches(row.name,query) then rows[#rows+1]=row end end
    table.sort(rows,function(a,b)return a.name<b.name end)
    self.queries[key]=rows;self.query_order[#self.query_order+1]=key
    if #self.query_order>64 then self.queries[table.remove(self.query_order,1)]=nil end
    return rows
end
function Catalogue:unique(query)
    assert(Parse.trim(query)~='','Enter an item name. Use !items to search.')
    local rows=self.exact[Parse.key(query)] or self:find(query)
    if #rows==0 then error('No item matches '..query,0) end
    if #rows~=1 then error('Several items match. Use an exact name from !items.',0) end
    return rows[1]
end
function Catalogue:asset(row)
    local obj=self.cache[row.path]
    if obj and valid(obj) then return obj end
    obj=StaticFindObject(row.path)
    if not valid(obj) then
        LoadAsset(row.path:match('^(.*)%.') or row.path)
        obj=StaticFindObject(row.path)
    end
    if not valid(obj) then error('That asset is unavailable in this game build.',0) end
    local deleted=false;pcall(function()deleted=obj.bSoftDeleted==true end)
    if deleted then error('That item is marked deleted by the game.',0) end
    self.cache[row.path]=obj;self.cache_order[#self.cache_order+1]=row.path
    if #self.cache_order>128 then self.cache[table.remove(self.cache_order,1)]=nil end
    return obj
end
function Catalogue:give(adapter,id,query,count)
    local row=self:unique(query);local data=self:asset(row)
    local p=adapter:peer(id);local inventory=p.pc.BP_Components_Inventory
    assert(valid(inventory),'Inventory is unavailable.')
    local before=inventory:GetNumItemsByData(data)
    inventory:AddItemByData(data,count,1.0,{})
    local actual=math.max(0,inventory:GetNumItemsByData(data)-before)
    return actual,row.name
end
return Catalogue
