if not rednet.isOpen() then
    for _, side in ipairs({"left", "right"}) do
        if peripheral.getType(side) == "modem" then
                rednet.open(side)
        end
    end
end
if not rednet.isOpen() then
    printError("Could not open rednet")
    return
end
local dirs = {
    ["south"] = 0,
    ["west"] = 1,
    ["north"] = 2,
    ["east"] = 3
}
local call = {}
--[[
rednet.broadcast({["call"] = "set", ["itemname"] = "minecraft:cobblestone", ["item"] = {
    x = 762,
    y = 6,
    z = 267,
    dir = 3
}})
]]--
function serializeTable(val, name, skipnewlines, depth)
    skipnewlines = skipnewlines or false
    depth = depth or 0

    local tmp = string.rep(" ", depth)

    if name then tmp = tmp .. name .. " = " end

    if type(val) == "table" then
        tmp = tmp .. "{" .. (not skipnewlines and "\n" or "")

        for k, v in pairs(val) do
            tmp =  tmp .. serializeTable(v, k, skipnewlines, depth + 1) .. "," .. (not skipnewlines and "\n" or "")
        end

        tmp = tmp .. string.rep(" ", depth) .. "}"
    elseif type(val) == "number" then
        tmp = tmp .. tostring(val)
    elseif type(val) == "string" then
        tmp = tmp .. string.format("%q", val)
    elseif type(val) == "boolean" then
        tmp = tmp .. (val and "true" or "false")
    else
        tmp = tmp .. "\"[inserializeable datatype:" .. type(val) .. "]\""
    end

    return tmp
end
function get(itemname) 
    rednet.broadcast({["call"] = "get", ["item"] = itemname})
    local senderId, s, protocol = rednet.receive()
    return s
end
local tArgs = {...}
local method = tArgs[1]
if not method then return end
if method == "set" then 
    if #tArgs < 6 then return end
    call["call"] = "set"
    call["itemname"] = tArgs[2]
    local item = {}
    item["x"] = tArgs[3]
    item["y"] = tArgs[4]
    item["z"] = tArgs[5]
    item["dir"] = dirs[tArgs[6]]
    call["item"] = item
    rednet.broadcast(call)
    print(serializeTable(get(tArgs[2])))
elseif method == "get" then
    print(serializeTable(get(tArgs[2])))
end

