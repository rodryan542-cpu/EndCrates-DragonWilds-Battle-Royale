-- Pure parsing and validation, also used by the isolated test suite.
local C = {}
function C.trim(s) return tostring(s or ""):match("^%s*(.-)%s*$") end
function C.key(s) return C.trim(s):lower():gsub("^item_", ""):gsub("[^%w]", "") end
function C.words(s)
    local words = {}
    for word in tostring(s):lower():gmatch("[%w]+") do words[#words + 1] = word end
    return words
end
function C.matches(haystack, query)
    local key = C.key(haystack)
    for _, word in ipairs(C.words(query)) do
        if not key:find(C.key(word), 1, true) then return false end
    end
    return true
end
function C.parse(line)
    if type(line) ~= "string" or #line > 1000 then return nil, "Command must be at most 1,000 characters." end
    line = C.trim(line)
    if line:sub(1, 1) ~= "!" then return nil, "Commands start with !" end
    local command, tail = line:match("^!([%w_]+)%s*(.*)$")
    if not command then return nil, "Invalid command. Type !help." end
    local args, current, quote = {}, {}, nil
    local function push()
        if #current > 0 then args[#args + 1] = table.concat(current); current = {} end
    end
    for i = 1, #tail do
        local ch = tail:sub(i, i)
        if quote then
            if ch == quote then quote = nil else current[#current + 1] = ch end
        elseif ch == '"' or ch == "'" then quote = ch
        elseif ch:match("%s") then push()
        else current[#current + 1] = ch end
    end
    if quote then return nil, "Close the quotation mark." end
    push()
    return {name=command:lower(), args=args, tail=tail}
end
function C.number(value, low, high, integer, label)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then
        error((label or "Value") .. " must be a finite number.", 0)
    end
    if integer and number % 1 ~= 0 then error((label or "Value") .. " must be a whole number.", 0) end
    if number < low or number > high then error(string.format("%s must be between %s and %s.", label or "Value", low, high), 0) end
    return number
end
function C.join(args, first, last) return table.concat(args, " ", first or 1, last or #args) end
function C.search_count(args, default)
    local count, last = default or 1, #args
    if last > 1 and tonumber(args[last]) then count = C.number(args[last], 1, 9999, true, "Count"); last = last - 1 end
    local query = C.trim(C.join(args, 1, last))
    if query == "" then error("Enter an item name or search words.", 0) end
    return query, count
end
function C.toggle(value, current)
    if value == nil then return not current end
    value = tostring(value):lower()
    if value == "on" or value == "1" or value == "true" then return true end
    if value == "off" or value == "0" or value == "false" then return false end
    error("Use on or off.", 0)
end
return C
