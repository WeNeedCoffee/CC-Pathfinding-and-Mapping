-- LOAD NETNAV API
if not netNav then
	if not os.loadAPI("netNav") then
		error("could not load netNav API")
	end
end

-- OPEN REDNET
for _, side in ipairs({"left", "right", "top", "bottom", "front", "back"}) do
    if peripheral.getType(side) == "modem" then
            rednet.open(side)
    end
end
if not rednet.isOpen() then
    printError("Could not open rednet")
    return
end
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
-- SET NETNAV MAP
netNav.setMap("test", 15) -- the second argument determines how frequently the turtle will check with the server for newer map data
function get(itemname) 
    rednet.broadcast({["call"] = "get", ["item"] = itemname})
    local senderId, s, protocol = rednet.receive()
    if not s["return"] then return false elseif s["return"] == "none" then return false end
    print(serializeTable(s))
    return s
end


while true do 
    for i = 1, 15 do
        turtle.select(i)
        sleep(0.5)
        if turtle.getItemDetail(i) then 
            local cont = true
            if turtle.getItemDetail(i).name == "minecraft:coal" then
                if not turtle.getItemDetail(16) then
                    turtle.transferTo(16)
                    cont = false
                end
            end
            if cont then
                local ret = get(turtle.getItemDetail(i).name)
                if ret then
                    if turtle.getFuelLevel() < 1000 then
                        turtle.select(16)
                        turtle.refuel()
                        turtle.select(i)
                    end

                    netNav.goto(ret.location.x, ret.location.y, ret.location.z)
                    netNav.setHeading(ret.location.dir)
                    turtle.drop()
                end
            end
        end
    end
    netNav.goto(775, 6, 282) 
    netNav.setHeading(2)
    for i = 1, 15 do
        turtle.select(i)
        sleep(0.5)
        turtle.dropUp()
    end
    
    local found = false
    while not found do
        for i = 1, 15 do
            turtle.select(i)
            local a = turtle.suckUp()
            sleep(0.5)
            if not found then
                if a then
                    found = true
                end
            end
        end
        if not found then sleep(5) end
    end
end