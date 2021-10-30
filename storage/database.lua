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
function save(table,name)
    local file = fs.open(name,"w")
    file.write(textutils.serialize(table))
    file.close()
end
function load(name)
    local file = fs.open(name,"r")
    if not file then return false end
    local data = file.readAll()
    file.close()
    return textutils.unserialize(data)
end
local items = load("data")
local regex = load("data_regex")
if not items then 
    items = {}
end
if not regex then
    regex = {}
end

while true do 
    local senderId, s, protocol = rednet.receive()
    if s.call == "set" then
        items[s.itemname] = s.item
        save(items, "data")
    elseif s.call == "setr" then
        local exists = false
        for entry in regex do
            if s.str == entry.str then
                rednet.broadcast({["return"] = "exists", ["entry"] = entry})
                exists = true
                break
            end

        end
        if not exists then 
            local i = #regex+1
            regex[i] = s.location
            regex[i]["str"] = s.str
            save(regex, "data_regex")
        end
    elseif s.call == "get" then
        if not items[s.item] then
            local found = false
            for entry in regex do
                if string.match(s.item, entry.str) then
                    rednet.broadcast({["return"] = "success", ["location"] = entry, ["item"] = s.item})
                    found = true
                    break
                end
            end
            if not found then rednet.broadcast({["return"] = "none"}) end
        else
            rednet.broadcast({["return"] = "success", ["location"] = items[s.item], ["item"] = s.item})
        end
    elseif s.call == "del" then
        if items[s.item] then
            items[s.item] = nil
        else
            for k, v in pairs(regex) do
                if v.str == s.item then
                    regex[k] = nil
                    break
                end
            end
        end

    end
end