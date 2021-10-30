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
function save(table, name)
    local file = fs.open(name, "w")
    file.write(textutils.serialize(table))
    file.close()
end
function load(name)
    local file = fs.open(name, "r")
    if not file then
        return false
    end
    local data = file.readAll()
    file.close()
    return textutils.unserialize(data)
end
local items = load("data")
local rgxdata = load("data_rgxdata")
if not items then
    items = {}
end
if not rgxdata then
    rgxdata = {}
end

while true do
    local senderId, s, protocol = rednet.receive()
    if s.call == "set" then
        items[s.itemname] = s.item
        save(items, "data")
    elseif s.call == "setr" then
        local exists = false
        for _, entry in ipairs(rgxdata) do
            if s.str == entry.str then
                exists = true
                break
            end
        end
        if not exists then
            local i = #rgxdata + 1
            rgxdata[i] = s.location
            rgxdata[i]["str"] = s.str
            save(rgxdata, "data_rgxdata")
        end
    elseif s.call == "get" then
        if not items[s.item] then
            local found = false
            for _, entry in ipairs(rgxdata) do
                if not found then
                    if entry.str ~= nil then
                        if string.match(s.item, entry.str) then
                            rednet.broadcast({["return"] = "success", ["location"] = entry, ["item"] = s.item}, "return:" .. s.item)
                            found = true
                        end
                    end
                end
            end
            if not found then
                rednet.broadcast({["return"] = "none"}, "return:" .. s.item)
            end
        else
            rednet.broadcast({["return"] = "success", ["location"] = items[s.item], ["item"] = s.item}, "return:" .. s.item)
        end
    elseif s.call == "del" then
        if items[s.item] then
            items[s.item] = nil
        else
            for k, v in pairs(rgxdata) do
                if v.str == s.item then
                    rgxdata[k] = nil
                end
            end
        end
    end
end
