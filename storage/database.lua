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
if not items then 
    items = {}
end
while true do 
    local senderId, s, protocol = rednet.receive()
    if s.call == "set" then
        items[s.itemname] = s.item
        save(items, "data")
    elseif s.call == "get" then
        if not items[s.item] then
            rednet.broadcast({["return"] = "none"})
        else
            rednet.broadcast({["return"] = "success", ["location"] = items[s.item], ["item"] = s.item})
        end
    end
end