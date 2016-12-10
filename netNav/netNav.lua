local apis = {
	"remoteMap",
	"aStar",
	"location",
}
for _ api in ipairs(apis) do
	if not _G[api] then
		if not os.loadAPI(api) then
			error("could not load API: "..api)
		end
	end
end

local position

local SESSION_MAX_DISTANCE_DEFAULT = 32

local SESSION_COORD_CLEAR = 1
local SESSION_COORD_BLOCKED = 2
local SESSION_COORD_DISTANCE = math.huge
local UPDATE_COORD_CLEAR = -1
local UPDATE_COORD_BLOCKED = 1
local UPDATE_COORD_DISTANCE = 2

local sessionMidPoint
local sessionMaxDistance

local sessionMap
local serverMap

local function distanceFunc(a, b)
	local sessionMapA, sessionMapB = sessionMap:get(a), sessionMap:get(b)
	if aStar.distance(a, sessionMidPoint) > sessionMaxDistance then
		return SESSION_COORD_DISTANCE -- first coord is outside the search region
	elseif aStar.distance(b, sessionMidPoint) > sessionMaxDistance then
		return SESSION_COORD_DISTANCE -- second coord is outside the search region
	elseif sessionMapA == SESSION_COORD_BLOCKED or sessionMapB == SESSION_COORD_BLOCKED then
		return SESSION_COORD_DISTANCE -- we have found one of these coords to be blocked during this session
	elseif sessionMapA == SESSION_COORD_CLEAR and sessionMapB == SESSION_COORD_CLEAR then
		return aStar.distance(a, b) -- we have found both of these coords to be clear during this session
	else
		local serverMapA, serverMapB = serverMap:get(a), serverMap:get(b)
		if serverMapA or serverMapB then
			serverMapA = serverMapA and UPDATE_COORD_DISTANCE^(serverMapA + 1) or 1
			serverMapB = serverMapB and UPDATE_COORD_DISTANCE^(serverMapB + 1) or 1
			return math.max(serverMapA, serverMapB) -- the remote server map is indicating one of these coords may be blocked
		end
	end
	return aStar.distance(a, b) -- we dont know anything useful so just calc the distance
end

local directions = {
	[vector.new(0, 0, 1)] = 0,
	[vector.new(-1, 0, 0)] = 1,
	[vector.new(0, 0, -1)] = 2,
	[vector.new(1, 0, 0)] = 3,
	[vector.new(0, 1, 0)] = 4,
	[vector.new(0, -1, 0)] = 5,
}

local function deltaToDirection(delta)
	for vec, dir in pairs(directions) do
		if aStar.vectorEquals(delta, vec) then
			return dir
		end
	end
end

local function tryMove()
	for i = 1, 4 do
		if turtle.forward() then
			return true
		end
		turtle.turnRight()
	end
	return false
end

local function findPosition()
	local move = turtle.up
	while not tryMove() do
		if not move() then
			if move == turtle.up then
				move = turtle.down
				move()
			else
				error("trapped in a ridiculous place")
			end
		end
	end
	
	local p1 = {gps.locate()}
	if #p1 == 3 then
		p1 = vector.new(unpack(p1))
	else
		error("no gps signal - phase 1")
	end
	
	if not turtle.back() then
		error("couldn't move to determine direction")
	end
	
	local p2 = {gps.locate()}
	if #p2 == 3 then
		p2 = vector.new(unpack(p2))
	else
		error("no gps signal - phase 2")
	end
	
	local direction = deltaToDirection(p1 - p2)
	if direction and direction < 4 then
		return location.new(p2.x, p2.y, p2.z, direction)
	else
		return false
	end
end

local function detect(currPos, adjPos)
	local direction = deltaToDirection(adjPos - currPos)
	if direction then
		position:setHeading(direction)
		if direction == 4 then
			return turtle.detectUp()
		elseif direction == 5 then
			return turtle.detectDown()
		else
			return turtle.detect()
		end
	end
	return false
end

local function inspect(currPos, adjPos)
	local direction = deltaToDirection(adjPos - currPos)
	if direction then
		position:setHeading(direction)
		if direction == 4 then
			return turtle.inspectUp()
		elseif direction == 5 then
			return turtle.inspectDown()
		else
			return turtle.inspect()
		end
	end
	return false
end

local function updateCoord(coord, isBlocked)
	if isBlocked then
		sessionMap:set(coord, SESSION_COORD_BLOCKED)
		serverMap:set(coord, UPDATE_COORD_BLOCKED)
	else
		sessionMap:set(coord, SESSION_COORD_CLEAR)
		serverMap:set(coord, UPDATE_COORD_CLEAR)
	end
end

local function detectAll(currPos)
	for _, pos in ipairs(aStar.adjacent(currPos)) do -- better order of checking directions
		updateCoord(pos, detect(currPos, pos))
	end
end

local function findSensor()
	for _, side in ipairs(peripheral.getNames()) do
		if peripheral.getType(side) == "turtlesensorenvironment" then
			return side
		end
	end
	return false
end

local function scan(currPos)
	local sensorSide = findSensor()
	if sensorSide then
		local rawBlockInfo = peripheral.call(sensorSide, "sonicScan")
		local sortedBlockInfo = aStar.newMap()
		for _, blockInfo in ipairs(rawBlockInfo) do
			sortedBlockInfo:set(currPos + vector.new(blockInfo.x, blockInfo.y, blockInfo.z), blockInfo)
		end
		local toCheckQueue = {}
		for _, pos in ipairs(aStar.adjacent(currPos)) do
			if sortedBlockInfo:get(pos) then
				table.insert(toCheckQueue, pos)
			end
		end
		while toCheckQueue[1] do
			local pos = table.remove(toCheckQueue, 1)
			local blockInfo = sortedBlockInfo:get(pos)
			if blockInfo.type == "AIR" then
				for _, pos2 in ipairs(aStar.adjacent(pos)) do
					local blockInfo2 = sortedBlockInfo:get(pos2)
					if blockInfo2 and not blockInfo2.checked then
						table.insert(toCheckQueue, pos2)
					end
				end
				updateCoord(pos, false)
			else
				updateCoord(pos, true)
			end
			blockInfo.checked = true
		end
		for _, blockInfo in ipairs(rawBlockInfo) do
			local pos = currPos + vector.new(blockInfo.x, blockInfo.y, blockInfo.z)
			local blockInfo = sortedBlockInfo:get(pos)
			if not blockInfo.checked then
				if blockInfo.type == "AIR" then
					sessionMap:set(pos, SESSION_COORD_CLEAR)
				else
					sessionMap:set(pos, SESSION_COORD_BLOCKED)
				end
			end
		end
	else
		detectAll(currPos)
	end
	serverMap:check()
	serverMap:pushUpdates()
end

local function move(currPos, adjPos)
	local direction = deltaToDirection(adjPos - currPos)
	if direction then
		position:setHeading(direction)
		if direction == 4 then
			return position:up()
		elseif direction == 5 then
			return position:down()
		else
			return position:forward()
		end
	end
	return false
end

local exit = false
local function _goto(x, y, z, maxDistance)
	exit = false
	if not serverMap then
		error("serverMap has not been specified")
	end
	if turtle.getFuelLevel() == 0 then
		return false, "ran out of fuel"
	end
	if not position then
		position = findPosition()
		if not position then
			return false, "couldn't determine location"
		end
	end
	
	local goal = vector.new(tonumber(x), tonumber(y), tonumber(z))
	
	serverMap:check() -- remove timed out data we have received from server

	sessionMap = aStar.newMap() -- reset the sessionMap
	sessionMidPoint = vector.new(math.floor((goal.x + position.x)/2), math.floor((goal.y + position.y)/2), math.floor((goal.z + position.z)/2))
	sessionMaxDistance = (type(maxDistance) == "number" and maxDistance) or math.max(2*aStar.distance(sessionMidPoint, goal), SESSION_MAX_DISTANCE_DEFAULT)

	local path = aStar.compute(distanceFunc, position, goal)
	if not path then
		return false, "no known path to goal"
	end

	while not (exit or aStar.vectorEquals(position, goal)) do
		local movePos = table.remove(path)
		while not move(position, movePos) do
			local blockPresent, blockData = inspect(position, movePos)
			local recalculate, isTurtle = false, false
			if blockPresent and (blockData.name == "ComputerCraft:CC-TurtleAdvanced" or blockData.name == "ComputerCraft:CC-Turtle") then -- there is a turtle in the way
				sleep(math.random(0, 3))
				local blockPresent2, blockData2 = inspect(position, movePos)
				if blockPresent2 and (blockData2.name == "ComputerCraft:CC-TurtleAdvanced" or blockData2.name == "ComputerCraft:CC-Turtle") then -- the turtle is still there
					recalculate, isTurtle = true, true
				end
			elseif blockPresent then
				recalculate = true
			elseif turtle.getFuelLevel() == 0 then
				return false, "ran out of fuel"
			else
				sleep(1)
			end
			if recalculate then
				scan(position)
				if sessionMap:get(goal) == SESSION_COORD_BLOCKED then return false, "goal is blocked" end
				path = aStar.compute(distanceFunc, position, goal)
				if not path then
					return false, "no known path to goal"
				end
				if isTurtle then
					sessionMap:set(movePos, nil)
				end
				movePos = table.remove(path)
			end
		end
		if serverMap:get(movePos) then
			serverMap:set(movePos, UPDATE_COORD_CLEAR)
		end
	end
	
	serverMap:check()
	serverMap:pushUpdates(true)
	
	return aStar.vectorEquals(position, goal)
end

local isRunning = false
function goto(...)
	if isRunning then
		return false, "already running"
	end
	isRunning = true
	local passback = {pcall(_goto, ...)}
	isRunning = false
	if not passback[1] then
		printError(passback[2])
		return false
	end
	return unpack(passback, 2)
end

function stop()
	if isRunning then
		exit = true
	end
end

function setMap(mapName, mapTimeout)
	if type(mapName) ~= "string" then
		error("mapName must be string")
	end
	if type(mapTimeout) ~= "number" or mapTimeout < 0 then
		error("timeout must be positive number")
	end
	serverMap = remoteMap.new(mapName, mapTimeout)
end

function getMap()
	return serverMap
end

function getPosition()
	if position then
		return position:value()
	end
end
