local apis = {
	"remoteMap",
	"aStar",
	"location",
	"scanStrategy",
}
for _, api in ipairs(apis) do
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

local function tryMove()
	for i = 1, 4 do
		if turtle.forward() then
			return true
		end
		turtle.turnRight()
	end
	return false
end

function findPosition()
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
	
	local currentDirection = location.headingFromDelta(p1 - p2)
	if currentDirection and currentDirection < 4 then
		return location.new(p2.x, p2.y, p2.z, currentDirection)
	else
		return false
	end
end

local function inspect(currPos, adjPos)
	local direction = location.headingFromDelta(adjPos - currPos)
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

local function updateSessionMap(coord, isBlocked)
	if isBlocked then
		sessionMap:set(coord, SESSION_COORD_BLOCKED)
	else
		sessionMap:set(coord, SESSION_COORD_CLEAR)
	end
end

local function updateServerMap(coord, isBlocked)
	if isBlocked then
		serverMap:set(coord, UPDATE_COORD_BLOCKED)
	else
		serverMap:set(coord, UPDATE_COORD_CLEAR)
	end
end

local function scan(currentPosition)
	local strategy = scanStrategy.getBest()
	if strategy then
		strategy.execute(currentPosition, updateSessionMap, updateServerMap)
		serverMap:check()
		serverMap:pushUpdates()
	else
		-- throw error ?
	end
end

local function move(currPos, adjPos)
	local direction = location.headingFromDelta(adjPos - currPos)
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
	else
		-- check if position has changed
		local curPos = {gps.locate()}
		if #curPos == 3 then
			curPos = vector.new(unpack(curPos))
			if not aStar.vectorEquals(curPos, position) then -- position has changed
				position = findPosition()
				if not position then
					return false, "couldn't determine location"
				end
			end
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

function setHeading(dir)
    position:setHeading(dir)
end

function addScanStrategy(strategy)
	scanStrategy.add(strategy)
end
