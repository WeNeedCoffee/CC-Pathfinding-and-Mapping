

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
function getItemLocation(itemname) 
    rednet.broadcast({["call"] = "get", ["item"] = itemname})
    local s = waitforreturn(itemname)
    if not s["return"] then return false elseif s["return"] == "none" then return false end
    return s
end
function waitforreturn(item) 
    local senderId, s, protocol = rednet.receive()
    if protocol == "return:" .. item then
        return s
    else
        return waitforreturn(item)
    end
end
function gotoChest(itemname) 
    local ret = getItemLocation(itemname)
    if ret then
        print("Got location for " .. itemname .. " in chest at " .. ret.location.x .. " " .. ret.location.y .. " " .. ret.location.z .. "\n")
        if netNav.goto(ret.location.x, ret.location.y, ret.location.z) then
            netNav.setHeading(ret.location.dir)
            return true
        else
            print("Don't know how to get to chest for " .. itemname)
        end
    else
        print("Don't know where to put " .. itemname)
    end
    return false
end
function gotoMainChest() 
    local x, y, z = gps.locate()
    if x ~= 755 or y ~= 6 or z ~= 282 then
        netNav.goto(775, 6, 282) 
        netNav.setHeading(2)
    end
end
while true do 
    for i = 1, 16 do
        turtle.select(i)
        sleep(0.25)
        if turtle.getItemDetail(i) then 
            if gotoChest(turtle.getItemDetail(i).name) then
                    turtle.drop()
            end
        end
    end
    gotoMainChest()
    for i = 1, 16 do
        turtle.select(i)
        sleep(0.25)
        turtle.dropUp()
    end
    
    local found = false
    while not found do
        for i = 1, 16 do
            if not turtle.getItemDetail(i) then     
                turtle.select(i)
                local a = turtle.suckUp()
                sleep(0.25)
                if not found then
                    if a then
                        found = true
                    end
                end
            else
                found = true
            end
        end
        if not found then sleep(5) end
    end
end