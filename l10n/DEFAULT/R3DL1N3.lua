-- R3DL1N3.lua
--
-- __________________ ________  .____    ____ _______  ________
-- \______   \_____  \\______ \ |    |  /_   |\      \ \_____  \
--  |       _/ _(__  < |    |  \|    |   |   |/   |   \  _(__  <
--  |    |   \/       \|    `   \    |___|   /    |    \/       \
--  |____|_  /______  /_______  /_______ \___\____|__  /______  /
--         \/       \/        \/        \/           \/       \/
--
-- Copyright © 2017, R3DL1N3, United Kingdom
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the “Software”), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
--   The above copyright notice and this permission notice shall be included in
--   all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED “AS IS,” WITHOUT WARRANTY OF ANY KIND, EITHER
-- EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT. IN NO
-- EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
-- OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
-- ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
-- DEALINGS IN THE SOFTWARE.
--
--------------------------------------------------------------------------------
--
-- Design Goals
-- ====== =====
--
-- 1. Keep it simple. This script aims to provide just enough tools to make
--    scripting easier and more accessible. Just enough and no more. It does not
--    offer a super-structure around Lua, or over the underlying simulator. It
--    tries to be just Lua, and blend nicely with DCS. For these reasons, the
--    script makes good use of co-routines when possible.
-- 2. Clarity. There are import distinctions to be made when dealing with
--    vectors, or points. Two dimensional vectors are tables with keys x and y.
--    Three dimensional ones have x, y and z; called `Vec3` structures in the
--    underlying C++ simulator. However, the latter look north from the pilot's
--    eye, where y increases up and z increases depth. In other words, y
--    represents altidude and z represents northing. To convert from three to
--    two dimensions, take x and z; not x and y as you might expect. Whereever
--    this distinction needs clarifying, the script either uses `vec3` as the
--    argument name or tries to make it clear in the description. Just be aware.
--

-- Loads a chunk of Lua from the given file, then executes it within the given
-- function environment using a protected call. Returns the result of the
-- function and nil on success. Answers nil and an error on failure; errors
-- include file loading failures as well as execution errors within the loaded
-- Lua.
function env_dofile(env, filename)
  local f, err = loadfile(filename)
  if not f then return nil, err end
  setfenv(f, env)
  local status, result = pcall(f)
  if not status then return nil, result end
  return result, nil
end

--------------------------------------------------------------------------------
--                                                                          math
--------------------------------------------------------------------------------
--
-- Extend the Lua standard math library. By design, the math extensions below
-- follow the math library's naming convention: no camel or underscore casing,
-- just plain lower-case delimiter-free run-the-name-together style. But this
-- just applies to the math extensions, not to others.

-- Seed the pseudo-random number generator and pop the first random number in
-- order to start the new sequence. This can only be done if random seeding and
-- operating system time are available.
if os and math.randomseed then
  math.randomseed(os.time())
  math.random()
end

-- Answers the horizontal distance between two points, _p_ and _q_. Points,
-- a.k.a. `Vec3` three-dimensional vector tables, are in the coordinate system
-- of the pilot's eye looking north where _z_ is depth or the northing axis; _y_
-- is the vertical axis, or altitude.
function math.distancexz(p, q)
  local dx = p.x - q.x
  local dz = p.z - q.z
  return math.sqrt(dx * dx + dz * dz)
end

-- Answers the horizontal heading angle between two points, from the first point
-- to the second point.
function math.headingxz(p, q)
  local dx = q.x - p.x
  local dz = q.z - p.z
  local angle = math.atan2(dz, dx)
  if angle < 0 then
    angle = 2 * math.pi + angle
  end
  return angle
end

-- Constructs a point delta on the x-z plane from an angle and radius.
function math.deltaxz(angle, radius)
  return {
    x = math.cos(angle) * radius,
    z = math.sin(angle) * radius,
  }
end

-- Answers a random 3-vector point within the given zone. The result does not
-- contain an altitude, y co-ordinate.
function math.randomxzinzone(zone)
  local angle = 2 * math.pi * math.random()
  local radius = zone.radius * math.random()
  local delta = math.deltaxz(angle, radius)
  return {x = zone.point.x + delta.x, z = zone.point.z + delta.z}
end

-- Answers the square magnitude of the given 3-vector. Useful for comparing
-- vector magnitudes; comparing squares is faster.
function math.squaremagnitude(vec3)
  return vec3.x * vec3.x + vec3.y * vec3.y + vec3.z * vec3.z
end

function math.magnitude(vec3)
  return math.sqrt(math.squaremagnitude(vec3))
end

--------------------------------------------------------------------------------
--                                                                     metatable
--------------------------------------------------------------------------------

metatable = {}

-- Returns a table's meta-table, creating a new one if not already set up.
-- Updates a table's meta-table if given new keys and values. Gets the table's
-- meta-table and inserts the given table. The insertion replaces any existing
-- meta-table entries.
function metatable.of(table, values)
  local metatable = getmetatable(table)
  if not metatable then
    metatable = {}
    setmetatable(table, metatable)
  end
  if values then
    for key, value in pairs(values) do
      metatable[key] = value
    end
  end
  return metatable
end

-- Convenience method for setting up a call function given a table and a
-- function.
function metatable.call(table, func)
  return metatable.of(table, {__call = func})
end

-- Sets up the meta-tables of Group and Unit for calling with a name to get
-- the group or unit by name.
function metatable.init()
  metatable.call(Group, function(self, ...)
    return self.getByName(...)
  end)

  metatable.call(Unit, function(self, ...)
    return self.getByName(...)
  end)
end

metatable.init()

--------------------------------------------------------------------------------
--                                                                         table
--------------------------------------------------------------------------------

-- Deep copy. Recursively copies tables and non-tables.
function table.deepcopy(object)
  local tables = {}
  local function copy(object)
    if 'table' ~= type(object) then
      return object
    elseif tables[object] then
      return tables[object]
    else
      local table = {}
      tables[object] = table
      for key, value in pairs(object) do
        table[copy(key)] = copy(value)
      end
      return setmetatable(table, getmetatable(object))
    end
  end
  return copy(object)
end

-- Builds a table from an iterator.
function table.fromiter(iter)
  local values = {}
  for value in iter do
    table.insert(values, value)
  end
  return values
end

function table.valueiter(values)
  return coroutine.wrap(function()
    for _, value in pairs(values) do
      coroutine.yield(value)
    end
  end)
end

function table.keys(table)
  local keys = {}
  for key, _ in pairs(table) do
    _G.table.insert(keys, key)
  end
  return keys
end

function table.values(table)
  local values = {}
  for _, value in pairs(table) do
    _G.table.insert(values, value)
  end
  return values
end

function table.copy(table)
  local copy = {}
  for key, value in pairs(table) do
    copy[key] = value
  end
  return copy
end

function table.tostrings(table, depth)
  local strings = {}
  if 'table' == type(table) then
    local tables = {{{}, table}}
    repeat
      local keys, table = unpack(_G.table.remove(tables))
      for key, value in pairs(table) do
        local subkeys = {}
        for _, key in ipairs(keys) do
          _G.table.insert(subkeys, key)
        end
        _G.table.insert(subkeys, key)
        if 'table' ~= type(value) then
          _G.table.insert(strings, _G.table.concat(subkeys, '.') .. ':' .. tostring(value))
        elseif depth == nil or #subkeys < depth then
          _G.table.insert(tables, {subkeys, value})
        end
      end
    until #tables == 0
  end
  return strings
end

-- Returns true if the given table contains a value matching the one given.
-- Otherwise answers false.
function table.contains(table, match)
  for _, value in pairs(table) do
    if value == match then
      return true
    end
  end
  return false
end

-- Answers unique values from the given table. Uses table look-up and insertion
-- for optimisation.
function table.uniqvalues(values)
  local byvalue = {}
  for _, value in ipairs(values) do
    byvalue[value] = {}
  end
  return table.keys(byvalue)
end

-- Groups an array of values by the results of the given function.
function table.groupvaluesby(values, func)
  local groups = {}
  for _, value in ipairs(values) do
    local index = func(value)
    local group = groups[index]
    if group then
      _G.table.insert(group, value)
    else
      groups[index] = {value}
    end
  end
  return groups
end

-- Answers a table of key arrays indexed by key type.
function table.keysbytype(table)
  return _G.table.groupvaluesby(_G.table.keys(table), function(key)
    return type(key)
  end)
end

--------------------------------------------------------------------------------
--                                                                     serialize
--------------------------------------------------------------------------------

serialize = {}

function serialize.keyindent(key, indent)
  return (indent or '') .. (key or '') .. (key and ' = ' or '')
end

function serialize.number(object, key, indent)
  return serialize.keyindent(key, indent) .. tostring(object)
end

function serialize.boolean(object, key, indent)
  return serialize.keyindent(key, indent) .. tostring(object)
end

function serialize.string(object, key, indent)
  return serialize.keyindent(key, indent) .. string.format('%q', object)
end

-- Recursively serialises a table to Lua code with optional indent and offset,
-- defaulting to blank indent and tab offset. Serialises only numeric and string
-- keys. Sorts the keys; sorted numeric indices first, then sorted strings.
-- Answers a multi-line string but without a new-line terminator, by design. Add
-- a terminator externally if needed.
function serialize.table(object, key, indent, offset)
  indent = indent or ''
  offset = offset or '\t'
  local strings = {}
  local keysbytype = table.keysbytype(object)
  for _, type in ipairs{'number', 'string'} do
    local keys = keysbytype[type]
    if keys then
      table.sort(keys)
      for _, key in ipairs(keys) do
        table.insert(strings, serialize.object(object[key], '[' .. serialize.object(key) .. ']', indent .. offset, offset))
      end
    end
  end
  -- Elide new-lines when the table is empty.
  local string = serialize.keyindent(key, indent) .. '{'
  if #strings > 0 then
    string = string .. '\n' .. table.concat(strings, ',\n') .. '\n' .. indent
  end
  return string .. '}'
end

function serialize.object(object, key, indent, offset)
  local func = serialize[type(object)]
  return func and func(object, key, indent, offset) or 'nil'
end

--------------------------------------------------------------------------------
--                                                                        string
--------------------------------------------------------------------------------

-- Splits a string by matching an inverse pattern. The given pattern matches the
-- non-delimiter character sequences. The result is an array of sub-strings
-- matching the pattern. Matches non-space sequences by default.
function string.split(string, pattern)
  local strings = {__index = table.insert}
  setmetatable(strings, strings)
  string.gsub(string, pattern or '[^%s]+', strings)
  setmetatable(strings, nil)
  strings.__index = nil
  return strings
end

--------------------------------------------------------------------------------
--                                                                       Counter
--------------------------------------------------------------------------------

Counter = {}
Counter.__index = Counter
setmetatable(Counter, {
  __call = function(self, value)
    return setmetatable({counter = value or 0}, self)
  end,
})

function Counter:__call()
  self.counter = self.counter + 1
  return self.counter
end

--------------------------------------------------------------------------------
--                                                                         world
--------------------------------------------------------------------------------

-- Adds an event function to the world. Creates an anonymous handler which calls
-- the given function. Returns the handler which can be used to remove the event
-- function using `world.removeEventHandler(handler)` or `handler:remove()`.
function world.addEventFunction(func)
  local handler = {func = func}
  function handler:onEvent(event)
    self.func(event)
  end
  function handler:remove()
    world.removeEventHandler(self)
  end
  return handler, world.addEventHandler(handler)
end

--------------------------------------------------------------------------------
--                                                                         Timer
--------------------------------------------------------------------------------

-- Wraps the `timer` function methods. Calling `Timer(function(timer) end)`
-- constructs a `Timer` which you can schedule or remove. You can also schedule
-- a delay based on the current time, or schedule a repeating timer using a
-- delay in seconds. Repeats are based on the time of the last firing.
Timer = {}
Timer.__index = Timer
setmetatable(Timer, {
  __call = function(self, fired)
    return setmetatable({fired = fired}, self)
  end,
})

-- Schedules the timer using an absolute time. Reschedules if the timer is
-- currently pending.
function Timer:schedule(time)
  if self.id then
    timer.setFunctionTime(self.id, time)
  else
    self.id = timer.scheduleFunction(Timer.fire, self, time)
  end
end

-- Removes the timer's schedule function but does not disable the timer.
-- Rescheduling creates a new scheduled timer function.
--
-- Calling `remove` as the timer fires both removes the timer function and also
-- nil'ifies the stored identifier. This will cause the fired function to answer
-- `nil`. However, what happens if the fired function schedules a new timer? In
-- that case, the function identifier will not be `nil` and `Timer:fire` will
-- answer a non-nil for a timer function that has been removed.
function Timer:remove()
  if self.id then
    timer.removeFunction(self.id)
    self.id = nil
  end
end

-- Schedules a delayed timer firing based on the current time. Sets up a
-- repeating timer if the second `repeats` argument is true.
function Timer:delay(seconds, repeats)
  self.seconds = seconds
  self.repeats = repeats
  self:schedule(timer.getTime() + self.seconds)
end

-- Timer firing arrives here. Sets up the timer's `time`, fires the timer
-- function, and sets up a repeat if necessary.
--
-- Only returns the next firing time if the timer has not been removed and the
-- timer repeats. Assumes that a non-repeating timer automatically removes the
-- underlying timer function. One-shot timers disconnect the timer function,
-- return nil on firing and get removed automatically.
function Timer:fire(time)
  self.time = time
  self:fired()
  if self.id and self.repeats then
    return time + self.seconds
  else
    self.id = nil
  end
end

--------------------------------------------------------------------------------
--                                                                      UserFlag
--------------------------------------------------------------------------------

UserFlag = {}
setmetatable(UserFlag, {
  __index = function(self, key)
    return trigger.misc.getUserFlag(key)
  end,
  -- The value has to be a number or a Boolean; it cannot be a string.
  __newindex = function(self, key, value)
    trigger.action.setUserFlag(key, value)
  end,
  __call = function(self, string)
    return {
      key = string,
      get = function(self)
        return UserFlag[self.key]
      end,
      set = function(self, value)
        UserFlag[self.key] = value
      end,
    }
  end,
})

--------------------------------------------------------------------------------
--                                                                          Zone
--------------------------------------------------------------------------------

Zone = {}
Zone.__index = Zone
Zone = setmetatable(Zone, {
  -- Constructs a zone using either a string or a zone itself as the zone table.
  -- Zone tables contain a point and a radius. The point is a three-dimensional
  -- vector.
  __call = function(self, arg)
    if 'string' == type(arg) then
      arg = trigger.misc.getZone(arg)
    end
    return setmetatable({point = arg.point, radius = arg.radius}, self)
  end,
})

-- Answers the zone's centre point, a two-vector.
function Zone:center()
  local p = self.point
  return {x = p.x, y = p.z}
end

-- Horizontal distance between the zone's centre and a given point.
function Zone:distanceXZ(vec3)
  return math.distancexz(self.point, vec3)
end

-- True if the given point lies horizontally within this zone.
function Zone:within(vec3)
  return self:distanceXZ(vec3) < self.radius
end

function Zone:surfaceType()
  return land.getSurfaceType(self:center())
end

function Zone:onLand()
  return self:surfaceType() == land.SurfaceType.LAND
end

function Zone:inShallowWater()
  return self:surfaceType() == land.SurfaceType.SHALLOW_WATER
end

function Zone:inWater()
  return self:surfaceType() == land.SurfaceType.WATER
end

function Zone:onRoad()
  return self:surfaceType() == land.SurfaceType.ROAD
end

function Zone:onRunway()
  return self:surfaceType() == land.SurfaceType.RUNWAY
end

function Zone:randomXZ()
  return math.randomxzinzone(self)
end

function Zone:randomSubZone(radius)
  return Zone{point = self:randomXZ(), radius = radius or 1}
end

-- Generates a limited number of random sub-zones whose centres lie within this
-- zone. Defaults to 100 sub-zones of 1-metre radius. The optional function
-- filters the generated zones.
function Zone:randomSubZones(count, radius, filter)
  return coroutine.wrap(function()
    for _ = 1, count or 100 do
      local zone = self:randomSubZone(radius)
      if filter == nil or filter(zone) then
        coroutine.yield(zone)
      end
    end
  end)
end

--------------------------------------------------------------------------------
--                                                                          MGRS
--------------------------------------------------------------------------------

MGRS = {}
MGRS.__index = MGRS
setmetatable(MGRS, {
  __call = function(self, ...)
    local lat, long = ...
    -- Typically, the arguments are numeric latitude and longitude. But if the
    -- first argument is a table, assume it is a two- or three-vector. In that
    -- case, convert the vector to latitude and longitude first.
    if 'table' == type(lat) then
      if lat.z then
        lat, long = coord.LOtoLL(lat)
      else
        lat, long = coord.LOtoLL{x = lat.x, z = lat.y}
      end
    end
    return setmetatable(coord.LLtoMGRS(lat, long), self)
  end,
})

function MGRS:utm()
  return self.UTMZone
end

function MGRS:digraph()
  return self.MGRSDigraph
end

function MGRS:easting()
  return self.Easting
end

function MGRS:northing()
  return self.Northing
end

function MGRS:__tostring()
  return string.format("%s %s %05d %05d", self:utm(), self:digraph(), self:easting()), self:northing()
end

function MGRS:eastingsNorthings()
  local eastingsNorthings = {}
  local function digit(ing, pow)
    return math.floor((ing % (pow * 10)) / pow)
  end
  local easting = self:easting()
  local northing = self:northing()
  for i = 0, 4 do
    local pow = math.pow(10, i)
    table.insert(eastingsNorthings, 1, {digit(easting, pow), digit(northing, pow)})
  end
  return eastingsNorthings
end

function MGRS:toString(precision, utm)
  local strings = {}
  if utm then table.insert(strings, self:utm()) end
  table.insert(strings, self:digraph())
  local ings = self:eastingsNorthings()
  for i = 1, precision or 5 do
    local ing = ings[i]
    table.insert(strings, string.format('%d%d', ing[1], ing[2]))
  end
  return table.concat(strings, ' ')
end

function MGRS:latLong()
  return coord.MGRStoLL(self)
end

function MGRS:point()
  return coord.LLtoLO(self:latLong())
end

function MGRS:vec2()
  local p = self:point()
  return {x = p.x, y = p.z}
end

function MGRS:surfaceType()
  return land.getSurfaceType(self:vec2())
end

function MGRS:height()
  return land.getHeight(self:vec2())
end

--------------------------------------------------------------------------------
--                                                                     coalition
--------------------------------------------------------------------------------

-- Answers an iterator that yields all coalition sides.
function coalition.allSides()
  return table.valueiter(coalition.side)
end

--------------------------------------------------------------------------------
--                                                                         Group
--------------------------------------------------------------------------------

function Group:id()
  return self:getID()
end

function Group:outText(text, seconds, clear)
  trigger.action.outTextForGroup(self:id(), text, seconds, clear)
end

-- Answers a function that wraps a co-routine iterator. You can use the result
-- directly in a for-statement. The iterated elements are Group instances.
function Group.filtered(side, category, filter)
  return coroutine.wrap(function()
    for _, group in pairs(coalition.getGroups(side, category)) do
      if filter == nil or filter(group) then
        coroutine.yield(group)
      end
    end
  end)
end

-- Answers all the tasked groups belonging to the given side and within the
-- given category.
function Group.tasked(side, category, filter)
  return Group.filtered(side, category, function(group)
    return group:getSize() > 0 and group:getController():hasTask() and (filter == nil or filter(group))
  end)
end

-- Answers all the untasked groups.
function Group.untasked(side, category, filter)
  return Group.filtered(side, category, function(group)
    return group:getSize() > 0 and not group:getController():hasTask() and (filter == nil or filter(group))
  end)
end

-- Sets up a counter attack. Searches for `fromSide` groups without controller
-- tasks. Adds a turning-point mission for each untasked group if `toSide` units
-- occupy the given zone.
function Group.setTurningToUnitsTasksInZone(fromSide, toSide, category, zone)
  local units = Unit.allInZone(zone, toSide, category)
  if #units == 0 then return end
  for group in Group.untasked(fromSide, category) do
    group:setTurningToUnitsTask(units)
  end
end

-- Sorts the given units by distance from this group's centre point. Sorts
-- in-place unless the group has no units and therefore no centre point. Answers
-- sorted units, else nil if no centre.
function Group:sortUnitsByDistance(units)
  local centerPoint = self:centerPoint()
  if centerPoint == nil then return end
  table.sort(units, function(lhs, rhs)
    return math.distancexz(lhs:getPoint(), centerPoint) < math.distancexz(rhs:getPoint(), centerPoint)
  end)
  return units
end

-- Sets this group's task to turn towards the location of the nearest member of
-- the given units. Nearest means the smallest horizontal distance from this
-- group's centre point. Sorts the given table of units. Replaces the group
-- controller's current task. Does nothing if this group is empty.
function Group:setTurningToUnitsTask(units, action, speed)
  if #units == 0 then return end
  self:sortUnitsByDistance(units)
  self:turnToPoint(units[1]:getPoint(), action, speed)
end

-- Constructs a new turning-to-point mission based on this group. Does not apply
-- the mission, just answers a new mission.
--
-- Includes the first unit's position as the initial waypoint, since the
-- simulator's group controller will ignore the mission otherwise. Only does so
-- if the group is not empty. Empty groups have no units but may exist
-- temporarily.
function Group:turningToPointMission(vec3, action)
  local mission = Mission()
  local unit = self:getUnit(1)
  if unit then
    mission:turningToPoint(unit:getPoint())
  end
  mission:turningToPoint(vec3)
  if action then
    mission:setAction(action)
  end
  return mission
end

-- Turns the group to move towards the given point. The group starts
-- immediately, replacing any existing tasks.
function Group:turnToPoint(vec3, action, speed)
  local mission = self:turningToPointMission(vec3, action)
  if speed then mission:setSpeed(speed) end
  mission:setTaskTo(self:getController())
end

-- Group in zone means all units in the group within the zone. This method
-- finishes early if it finds a unit outside the zone. Answers true only if all
-- units fall within the given zone radius.
function Group:inZone(zone)
  for _, unit in pairs(self:getUnits()) do
    if not unit:inZone(zone) then
      return false
    end
  end
  return true
end

-- Finds the centre point of a group by averaging the positions of the group's
-- units. Answers nil if the group contains no units.
function Group:centerPoint()
  local x, y, z, n = 0, 0, 0, 0
  for _, unit in pairs(self:getUnits()) do
    local p = unit:getPoint()
    x, y, z, n = x + p.x, y + p.y, z + p.z, n + 1
  end
  if n == 0 then return nil end
  return {x = x / n, y = y / n, z = z / n}
end

-- Answers the group's zone based on its units' locations in the x-z plane. The
-- centre of the zone is the centre of the group. The radius is the distance
-- between the centre and the group's furthest unit from the centre. Never
-- answers a zero-radius zone.
function Group:zone()
  local point = self:centerPoint()
  local radius = 1
  for _, unit in pairs(self:getUnits()) do
    local distance = math.distancexz(unit:getPoint(), point)
    if distance > radius then
      radius = distance
    end
  end
  return {point = point, radius = radius}
end

-- Only works with ground groups.
function Group:continueMoving()
  trigger.action.groupContinueMoving(self)
end

function Group:stopMoving()
  trigger.action.groupStopMoving(self)
end

-- Groups are not coalition objects, and therefore cannot access their country.
-- Instead, access the country via the group's first unit.
function Group:country()
  local unit = self:getSize() > 0 and self:getUnit(1)
  return unit and unit:getCountry()
end

-- Sorts the given groups by their centre-point distance from the given point.
-- The first group becomes the closest group to the point, based on the centre.
function Group.sortGroupsByCenterPoint(groups, point)
  table.sort(groups, function(lhs, rhs)
    return math.distancexz(lhs:centerPoint(), point) < math.distancexz(rhs:centerPoint(), point)
  end)
end

function Group.destroyEmpty(side, category)
  for group in Group.filtered(side, category, function(group)
    return group:getSize() == 0
  end) do
    group:destroy()
  end
end

-- Destroy all empty groups. The simulator does not automatically destroy them.
-- Helps maintain frames-per-second. Run this periodically.
function Group.destroyAllEmpty()
  Group.destroyEmpty(coalition.side.RED)
  Group.destroyEmpty(coalition.side.BLUE)
end

-- Answers an iterator for all group categories.
function Group.allCategories()
  return table.valueiter(Group.Category)
end

--------------------------------------------------------------------------------
--                                                                          Unit
--------------------------------------------------------------------------------

function Unit:group()
  return self:getGroup()
end

-- Outputs trigger text for this unit, indirectly outputting the text for the
-- unit's entire group. The simulator does not support unit-level trigger text.
function Unit:outText(text, seconds, clear)
  self:group():outText(text, seconds, clear)
end

function Unit:life()
  return self:getLife() / self:getLife0()
end

-- Answers the unit's height above ground level. Importantly, the land height
-- needs a two-dimensional vector, a table, with keys `x` and `y` for horizontal
-- and vertical coordinates.
function Unit:height()
  local p = self:getPoint()
  return p.y - land.getHeight{x = p.x, y = p.z}
end

-- The unit's speed is the magnitude of its velocity vector.
function Unit:speed()
  return math.magnitude(self:getVelocity())
end

function Unit:heading()
  return math.headingxz({x = 0, z = 0}, self:getPosition().x)
end

-- Answers the unit's bounding box.
function Unit:box()
  return self:getDesc().box
end

-- Answers the unit's width, height and length in that order.
function Unit:dimensions()
  local box = self:box()
  return box.max.x - box.min.x, box.max.y - box.min.y, box.max.z - box.min.z
end

-- Answers the width and length of the unit. The width is defined as the
-- shortest horizontal dimension. The length is the longest.
function Unit:widthAndLength()
  local dx, _, dz = self:dimensions()
  if dx < dz then
    return dx, dz
  else
    return dz, dx
  end
end

-- Returns the distance between two units, this unit and another given unit
-- which may be the same unit.
function Unit:distanceXZ(other)
  return math.distancexz(self:getPoint(), other:getPoint())
end

function Unit:distanceFromGroup(group)
  local centerPoint = group:centerPoint()
  if centerPoint == nil then return end
  return math.distancexz(self:getPoint(), centerPoint)
end

-- Answers the distance from this unit to the zone centre relative to the zone
-- boundary. If negative, this unit is within the boundary. If positive, the
-- unit is outside the zone. The magnitude tells you how far this unit is either
-- in or out of the zone.
function Unit:distanceFromZone(zone)
  return math.distancexz(self:getPoint(), zone.point) - zone.radius
end

-- Answers true if this unit is within the given zone.
function Unit:inZone(zone)
  return self:distanceFromZone(zone) < 0
end

-- True if this unit is friendly with another unit, meaning belonging to the
-- same coalition. Red and blue are not friendly with neutrals, but are not
-- hostile. Neutrals are friendly with everyone. Units are coalition objects:
-- they known their coalition.
function Unit:isFriendlyWith(other)
  if not other.getCoalition then return nil end
  local side = self:getCoalition()
  return side == coalition.side.NEUTRAL or side == other:getCoalition()
end

-- True if not neutral and the other unit is not on the same side. Answers `nil`
-- if the other object has no coalition, because it's not a coalition object.
function Unit:isHostileWith(other)
  if not other.getCoalition then return nil end
  local side = self:getCoalition()
  return side ~= coalition.side.NEUTRAL and side ~= other:getCoalition()
end

function Unit:surfaceType()
  local p = self:getPoint()
  return land.getSurfaceType{x = p.x, y = p.z}
end

function Unit:onLand()
  return self:surfaceType() == land.SurfaceType.LAND
end

function Unit:inShallowWater()
  return self:surfaceType() == land.SurfaceType.SHALLOW_WATER
end

function Unit:inWater()
  return self:surfaceType() == land.SurfaceType.WATER
end

function Unit:onRoad()
  return self:surfaceType() == land.SurfaceType.ROAD
end

function Unit:onRunway()
  return self:surfaceType() == land.SurfaceType.RUNWAY
end

-- Returns an iterator for all units within a given zone that belong to a given
-- coalition side, optionally matching a given group category, and optionally
-- filtered by a given function.
function Unit.filtered(side, category, filter)
  return coroutine.wrap(function()
    for _, group in pairs(coalition.getGroups(side, category)) do
      for _, unit in pairs(group:getUnits()) do
        if filter == nil or filter(unit, group) then
          coroutine.yield(unit, group)
        end
      end
    end
  end)
end

-- Filters units using a zone. Answers an iterator that includes all units, with
-- their group, which fall within the given zone.
function Unit.unitsInZone(zone, side, category)
  return Unit.filtered(side, category, function(unit)
    return unit:inZone(zone)
  end)
end

-- Answers iterator for helicopter units within the given zone and belonging to
-- the given side.
function Unit.helicoptersInZone(zone, side)
  return Unit.unitsInZone(zone, side, Group.Category.HELICOPTER)
end

-- Iterates ground units within zone, belonging to side.
function Unit.groundUnitsInZone(zone, side)
  return Unit.unitsInZone(zone, side, Group.Category.GROUND)
end

function Unit.allInZone(zone, side, category)
  return table.fromiter(Unit.unitsInZone(zone, side, category))
end

function Unit.allHelicoptersInZone(zone, side)
  return Unit.allInZone(zone, side, Group.Category.HELICOPTER)
end

function Unit.allGroundUnitsInZone(zone, side)
  return Unit.allInZone(zone, side, Group.Category.GROUND)
end

-- There is no way to retrieve a unit's skill once set, it seems. Instead
-- therefore, set up a setter and getter pair which caches the skill by unit
-- identifier. This only works if you apply the setter. Setting the skill does
-- not actually set the skill. Instead, it just remembers it for the getter.
local skillForUnit = {}

function Unit:setSkill(skill)
  skillForUnit[self:getID()] = skill
end

function Unit:skill()
  return skillForUnit[self:getID()]
end

--------------------------------------------------------------------------------
--                                                                         Units
--------------------------------------------------------------------------------

-- Encapsulates a table of units for group construction. Simplifies the creation
-- of a group. Note, the units do not form a group until you add the units,
-- giving their country and category. You can discard the `Units` table after
-- adding. They become a new group.
Units = {
  Group = {
    [Group.Category.AIRPLANE] = 'Airplane',
    [Group.Category.HELICOPTER] = 'Helicopter',
    [Group.Category.GROUND] = 'Ground',
    [Group.Category.SHIP] = 'Ship',
  },
}
Units.__index = Units
setmetatable(Units, {
  __call = function(self)
    return setmetatable({units = {}}, self)
  end,
})

function Units:all()
  return self.units
end

-- Adds a unit.
function Units:add(unit)
  table.insert(self.units, unit)
end

-- Adds a unit, or units, of a given type.
function Units:addType(type, times)
  for _ = 1, times or 1 do
    self:add{type = type}
  end
end

-- Randomises the positions of all the units so far specified to within the
-- given zone.
function Units:randomizeXYInZone(zone)
  for _, unit in ipairs(self.units) do
    local point = math.randomxzinzone(zone)
    unit.x, unit.y = point.x, point.z
  end
end

function Units:translateXY(dx, dy)
  for _, unit in ipairs(self.units) do
    unit.x = unit.x + dx
    unit.y = unit.y + dy
  end
end

-- Rotates all the units to the given heading about the x-y plane's origin.
-- Note, the heading argument is in radians relative to north; 0 means up and
-- increases anti-clockwise. Hence, the argument name is heading not angle.
function Units:rotateXY(heading)
  local angle = 0.5 * math.pi + heading
  if angle > 2 * math.pi then angle = angle - 2 * math.pi end
  local dx, dy = math.cos(angle), math.sin(angle)
  for _, unit in ipairs(self.units) do
    unit.x, unit.y = unit.x * dx - unit.y * dy, unit.x * dy + unit.y * dx
  end
end

-- Finds the two-dimensional centre-point of all the units so far accumulated;
-- or nil if no units.
function Units:center()
  local x, y, n = 0, 0, 0
  for _, unit in ipairs(self.units) do
    x, y, n = x + unit.x, y + unit.y, n + 1
  end
  if n == 0 then return nil end
  return {x = x / n, y = y / n}
end

-- Automatically orientates the units. The columns face north and the middle of
-- the units falls at the origin.
function Units:formColumns(dx, dy, numberOfColumns)
  for index, unit in ipairs(self:all()) do
    local column = (index - 1) % numberOfColumns
    local row = (index - 1 - column) / numberOfColumns
    unit.x = column * dx
    unit.y = row * dy
  end
  local center = self:center()
  self:translateXY(-center.x, -center.y)
end

-- Forms the units into a square using the given displacement between units.
function Units:formSquare(dx, dy)
  self:formColumns(dx, dy, math.floor(math.sqrt(#self:all())))
end

-- Useful for when you want to form units within overlapping zones. The heading
-- becomes the angle between the sub-zone's centre-point and that of the
-- super-zone.
function Units:formSquareInZones(subZone, superZone, dx, dy)
  local heading
  if math.distancexz(subZone.point, superZone.point) < superZone.radius then
    heading = math.headingxz(subZone.point, superZone.point)
  else
    heading = 2 * math.pi * math.random()
  end
  self:formSquare(dx or 1, dy or 1)
  self:rotateXY(heading)
  self:translateXY(subZone.point.x, subZone.point.z)
  self:setHeading(heading)
end

function Units:setHeading(heading)
  for _, unit in ipairs(self.units) do
    unit.heading = heading
  end
end

function Units:randomizeHeading()
  for _, unit in ipairs(self.units) do
    unit.heading = 2 * math.pi * math.random()
  end
end

-- Makes all the units randomly transportable, or not.
function Units:setRandomTransportable(bool)
  for _, unit in ipairs(self.units) do
    if not unit.transportable then
      unit.transportable = {}
    end
    unit.transportable.randomTransportable = bool
  end
end

function Units:setSkill(skill)
  for _, unit in ipairs(self.units) do
    unit.skill = skill
  end
end

function Units:setAverageSkill()
  self:setSkill(AI.Skill.AVERAGE)
end

function Units:setGoodSkill()
  self:setSkill(AI.Skill.GOOD)
end

function Units:setHighSkill()
  self:setSkill(AI.Skill.HIGH)
end

function Units:setExcellentSkill()
  self:setSkill(AI.Skill.EXCELLENT)
end

function Units:setClientSkill()
  self:setSkill(AI.Skill.CLIENT)
end

-- Sets up the units condition, a fraction between 0 and 1.
function Units:setProbability(fraction)
  self.probability = fraction
end

-- Applies the given mission to these units. Copies the mission's route,
-- including the route's waypoints.
function Units:setMission(mission)
  self.route = table.deepcopy(mission:route())
end

-- Constructs a new mission based on one of the units. The index identifies
-- which one of the units, the first by default. The new mission's initial
-- turning point starts at the given unit's location. Ignores altitude.
function Units:missionFromUnit(index)
  local mission = Mission()
  local unit = self.units[index or 1]
  if unit then mission:addTurningPoint(unit.x, unit.y) end
  return mission
end

-- Decimates the units using the given probability of death. Uses 10%
-- probability of dying if none given; therefore one in ten units will not
-- survive on average, by default.
function Units:decimate(probability)
  local index = 1
  while index <= #self.units do
    if math.random() < (probability or 0.1) then
      table.remove(self.units, index)
    else
      index = index + 1
    end
  end
end

function Units:table()
  if not self.name then
    -- Sets up the name of the units, which will become the group name when spawned.
    -- Makes the name from a prefix and a number. The name will be unique at the
    -- time of making. Spawn the units in order to reserve the new name.
    local prefixes = {}
    table.insert(prefixes, _G.country.name[country])
    table.insert(prefixes, Units.Group[category])
    self.name = Units.makeName(Group, table.concat(prefixes, ' '))
  end
  return setmetatable(self, nil)
end

-- Spawns a new group based on these units, given a country identifier and a group
-- category. Answers the newly-added group. Removes the meta-table from self
-- before using self to add the new group. Self therefore becomes just another
-- table hereafter. The group always needs a name. Adding supplies an
-- auto-generated group name if the units do not already have one.
function Units:spawn(country, category)
  if not self.route then
    self:setMission(self:missionFromUnit())
  end
  local group = coalition.addGroup(country or self.country, category or self.category, self:table())
  -- Cache the unit skills. This is the only time that the units and the skills
  -- exist together at the same time. This assumes, of course, that the order of
  -- the spawned units matched the order of the configured units. This will fail
  -- if this assumption is wrong for any reason. The index for the spawned units
  -- must correspond to the index for the `self` units. This is only possible
  -- when spawning succeeds.
  if group and group:isExist() then
    for index, unit in ipairs(group:getUnits()) do
      unit:setSkill(self.units[index].skill)
    end
  end
  return group
end

function Units:spawnAirplane(country)
  return self:spawn(country, Group.Category.AIRPLANE)
end

function Units:spawnHelicopter(country)
  return self:spawn(country, Group.Category.HELICOPTER)
end

function Units:spawnGround(country)
  return self:spawn(country, Group.Category.GROUND)
end

function Units:spawnShip(country)
  return self:spawn(country, Group.Category.SHIP)
end

-- Adds the given group, or more precisely, adds units based on the given group.
-- Takes the name of the units from the group name, unless the units already
-- have a name. Adds units for each group unit, copying the type, name and
-- skill.
--
-- Also remembers each unit's life and initial life, from which you can assess
-- the damage to the chalk; although no way to restore the hit points exists
-- currently. The group's initial size is also recorded. Useful for knowing how
-- many casualties the group suffered before embarking.
function Units:addGroup(group)
  if not self.name then
    self.name = group:getName()
  end
  if not self.country then
    self.country = group:country()
  end
  if not self.category then
    self.category = group:getCategory()
  end
  for _, unit in ipairs(group:getUnits()) do
    self:add{
      type = unit:getTypeName(),
      name = unit:getName(),
      skill = unit:skill(),
      life = unit:getLife(),
      life0 = unit:getLife0(),
    }
  end
  self.initialSize = group:getInitialSize()
end

-- Assesses the total chalk damage based on its initial life and its current
-- life at the time of embarking. This implementation relies on having life
-- information taken from an existing group. Answers nil if no life information
-- exists for these units.
function Units:damage()
  local damage
  for _, unit in ipairs(self:all()) do
    if unit.life and unit.life0 then
      damage = (damage or 0) + math.floor(unit.life0 - unit.life)
    end
  end
  return damage
end

-- Makes a unique group or unit name using a prefix and a number. You supply the
-- class, either `Group` or `Unit` and the prefix string. Answers a unique name
-- at the time of making. Spawn the group or unit in order to reserve the new
-- unique name.
function Units.makeName(class, prefix)
  local number = 0
  local name
  repeat
    number = number + 1
    name = prefix .. ' #' .. number
  until not class.getByName(name)
  return name
end

--------------------------------------------------------------------------------
--                                                                    Controller
--------------------------------------------------------------------------------

function Controller:immortal(immortal)
  self:setCommand{id = 'SetImmortal', params = {value = immortal or true}}
end

function Controller:invisible(invisible)
  self:setCommand{id = 'SetInvisible', params = {value = invisible or true}}
end

--------------------------------------------------------------------------------
--                                                                         Names
--------------------------------------------------------------------------------

-- Maintains two independent naming counters, one for groups and one for units.
-- This is a common paradigm. Also useful for identifying groups and units by
-- their names.
Names = {}
Names.__index = Names
setmetatable(Names, {
  __call = function(self, groupPrefix, unitPrefix)
    if unitPrefix == nil and string.sub(groupPrefix, -1) == 's' then
      unitPrefix = string.sub(groupPrefix, 1, -2) .. ' #'
      groupPrefix = groupPrefix .. ' #'
    end
    return setmetatable({
      groupCounter = Counter(),
      unitCounter = Counter(),
      groupPrefix = groupPrefix,
      unitPrefix = unitPrefix,
    }, self)
  end,
})

function Names:setGroupPrefix(prefix)
  self.groupPrefix = prefix
end

function Names:setUnitPrefix(prefix)
  self.unitPrefix = prefix
end

function Names:groupName()
  return self.groupPrefix .. tostring(self.groupCounter())
end

function Names:unitName()
  return self.unitPrefix .. tostring(self.unitCounter())
end

-- Applies group and unit names to the given units table. Does not overwrite any
-- existing names. Does not assume that the given units table is a `Units`
-- sub-class; it can be, but can also be the resulting pure table.
function Names:applyTo(units)
  if not units.name then
    units.name = self:groupName()
  end
  for _, unit in ipairs(units.units) do
    if not unit.name then
      unit.name = self:unitName()
    end
  end
end

-- Answers true if the given group belongs to this naming scheme based on the
-- group's name prefix.
function Names:includesGroup(group)
  return string.find(group:getName(), self.groupPrefix) == 1
end

function Names:includesUnit(unit)
  return string.find(unit:getName(), self.unitPrefix) == 1
end

-- Answers all groups within the given zone that match this naming scheme. Sorts
-- the groups by their horizontal distance from the zone centre. Closest appears
-- first. You must also specify the country, but the category is optional.
-- Answers all categories if unspecified.
function Names:groupsInZone(zone, side, category, filter)
  local groups = table.fromiter(Group.filtered(side, category, function(group)
    return self:includesGroup(group) and group:inZone(zone) and (filter == nil or filter(group))
  end))
  Group.sortGroupsByCenterPoint(groups, zone.point)
  return groups
end

--------------------------------------------------------------------------------
--                                                                       Mission
--------------------------------------------------------------------------------

-- Represents a mission task for a controller. Note that the first waypoint must
-- be the group's current point on the map, otherwise the controller ignores the
-- mission.
Mission = {}
Mission.__index = Mission
setmetatable(Mission, {
  __call = function(self)
    return setmetatable({
      id = 'Mission',
      params = {
        route = {
          points = {},
        },
      },
    }, self)
  end,
})

function Mission:route()
  return self.params.route
end

-- Gives access to the waypoints. Answers the actual waypoints, not a copy.
-- Modifying the result also modifies the mission.
function Mission:waypoints()
  return self:route().points
end

-- Adds a waypoint to the mission, or some other kind of point.
function Mission:add(waypoint)
  return table.insert(self:waypoints(), waypoint)
end

function Mission:addTurningPoint(x, y, alt)
  return self:add{type = AI.Task.WaypointType.TURNING_POINT, x = x, y = y, alt = alt}
end

-- Adds a turning point without an altitude based on a three-dimensional vector.
function Mission:turningToPoint(vec3)
  return self:addTurningPoint(vec3.x, vec3.z)
end

function Mission:turningAtPoint(vec3)
  return self:addTurningPoint(vec3.x, vec3.z, vec3.y)
end

-- Assigns an action for all the waypoints.
function Mission:setAction(action)
  for _, waypoint in ipairs(self:waypoints()) do
    waypoint.action = action
  end
end

function Mission:setOnRoadAction()
  self:setAction(AI.Task.VehicleFormation.ON_ROAD)
end

function Mission:setOffRoadAction()
  self:setAction(AI.Task.VehicleFormation.OFF_ROAD)
end

function Mission:setSpeed(speed)
  for _, waypoint in ipairs(self:waypoints()) do
    waypoint.speed = speed
  end
end

function Mission:setSpeedKph(kph)
  self:setSpeed(kph / 3.6)
end

-- One nautical mile equals 1852 meters.
function Mission:setSpeedKt(kt)
  self:setSpeedKph(kt * 1.852)
end

-- Converts this mission into an ordinary table by removing the meta-table, and
-- thus making it suitable for submission to a controller as a new task.
function Mission:table()
  return setmetatable(self, nil)
end

function Mission:setTaskTo(controller)
  controller:setTask(self:table())
end

function Mission:pushTaskTo(controller)
  controller:pushTask(self:table())
end

--------------------------------------------------------------------------------
--                                                                       landing
--------------------------------------------------------------------------------

world.event.S_EVENT_LANDING = 'S_EVENT_LANDING'
world.event.S_EVENT_LANDED = 'S_EVENT_LANDED'

local landingTimers = {}
local landingTimeInterval = 1
local landingSpeedThreshold = 1

local isLanded = {}

function Unit:landingTimer()
  return landingTimers[self:getID()]
end

function Unit:setLandingTimer(timer)
  landingTimers[self:getID()] = timer
end

-- Note, not landing is not necessarily the same as landed. Took off is also not
-- landing, as well as not landed.
function Unit:isLanding()
  return self:landingTimer() ~= nil
end

function Unit:isLanded()
  return isLanded[self:getID()]
end

function Unit:setIsLanded(is)
  isLanded[self:getID()] = is
end

-- Starts the landing cycle. The world starts to see LANDING and LANDED events.
-- Landing events repeat until the unit's speed decreases below the speed
-- threshold. At that point, landing becomes landed and the world sees a single
-- LANDED event.
function Unit:startLanding()
  -- Stop landing before starting!
  self:stopLanding()
  local timer = Timer(function(timer)
    -- Filters out brief landings, such as when a helicopter skids the ground
    -- in-flight. That does not count as a landing. The initiator's speed must
    -- be less than 1 metres per second, by default. The chalk will not embark
    -- or disembark if you land too quickly.
    local speed = self:speed()
    local landed = speed < landingSpeedThreshold
    if landed then
      timer:remove()
    end
    -- Invokes a world event during a world event.
    world.onEvent{
      id = landed and world.event.S_EVENT_LANDED or world.event.S_EVENT_LANDING,
      initiator = self,
      speed = speed,
      time = timer.time,
    }
  end)
  self:setLandingTimer(timer)
  timer:delay(landingTimeInterval, true)
end

function Unit:stopLanding()
  local timer = self:landingTimer()
  if timer then
    timer:remove()
    self:setLandingTimer(nil)
  end
end

function Unit.setLandingTimeInterval(seconds)
  landingTimeInterval = seconds
end

function Unit.setLandingSpeedThreshold(speed)
  landingSpeedThreshold = speed
end

-- Start a timer when a slick, a helicopter carrying a chalk, lands. Start
-- checking the unit speed.
world.addEventFunction(function(event)
  -- Entirely ignore events without an initiator.
  if not event.initiator then return end
  if event.id == world.event.S_EVENT_TAKEOFF then
    event.initiator:stopLanding()
    event.initiator:setIsLanded(nil)
  elseif event.id == world.event.S_EVENT_LAND then
    event.initiator:startLanding()
    event.initiator:setIsLanded(nil)
  elseif event.id == world.event.S_EVENT_LANDING then
    event.initiator:setIsLanded(false)
  elseif event.id == world.event.S_EVENT_LANDED then
    event.initiator:setIsLanded(true)
  elseif event.id == world.event.S_EVENT_CRASH then
    event.initiator:stopLanding()
    event.initiator:setIsLanded(nil)
  elseif event.id == world.event.S_EVENT_EJECTION then
    event.initiator:stopLanding()
    event.initiator:setIsLanded(nil)
  elseif event.id == world.event.S_EVENT_PLAYER_ENTER_UNIT then
    -- This only runs when in multi-player mode. Note that not nil is true, as
    -- well as not false being true. Therefore, is-landed becomes true if not
    -- in-air true but also if in-air is nil or unknown. Defaults to landed.
    event.initiator:setIsLanded(not event.initiator:inAir())
  elseif event.id == world.event.S_EVENT_PLAYER_LEAVE_UNIT then
    event.initiator:stopLanding()
    event.initiator:setIsLanded(nil)
  end
end)

--------------------------------------------------------------------------------
--                                                                        chalks
--------------------------------------------------------------------------------

world.event.S_EVENT_EMBARKING = 'S_EVENT_EMBARKING'
world.event.S_EVENT_EMBARKED = 'S_EVENT_EMBARKED'

world.event.S_EVENT_DISEMBARKING = 'S_EVENT_DISEMBARKING'
world.event.S_EVENT_DISEMBARKED = 'S_EVENT_DISEMBARKED'

world.event.S_EVENT_SURVIVING = 'S_EVENT_SURVIVING'
world.event.S_EVENT_SURVIVED = 'S_EVENT_SURVIVED'

-- Creates an association between a unit and a chalk, a Units instance.
local chalks = {}

-- Answers this unit's chalk, or nil if the unit has no chalk.
function Unit:chalk()
  return chalks[self:getID()]
end

function Unit:setChalk(units)
  chalks[self:getID()] = units
end

local disembarkedBy = {}

-- Answers a name string representing a player. Disembarked groups retain the
-- player name of the unit that disembarked them. Useful for assigning scores,
-- whenever you want to award disembarked chalk performance to the helicopter
-- that transported them.
function Group:disembarkedBy()
  return disembarkedBy[self:getID()]
end

function Group:setDisembarkedBy(playerName)
  disembarkedBy[self:getID()] = playerName
end

function Unit:disembarkedBy()
  return self:getGroup():disembarkedBy()
end

-- Answers the unit's player name where the player that disembarked the unit
-- overrides any current player.
function Unit:playerName()
  return self:disembarkedBy() or self:getPlayerName()
end

-- Call this method whenever a chopper's door opens. Opening the helicopter door
-- invites either an on-board chalk to disembark, or a nearby chalk to embark.
-- The radius threshold argument specifies the maximum distance between this
-- unit and any chalk unit. If units are outside the limit, you might want to
-- display a message to this unit's player, giving the current distance.
--
-- Note, this works in both directions: chopper to chalk, or chalk to chopper.
-- You can move units to the chopper in order to embark them.
--
-- Run this when a door opens, i.e. a unit's argument switches to within range
-- 0.9 to 1.0 or fully open. For different aircraft, the argument number maps as
-- follows.
--
--    38    UH-1 cockpit doors, Gazelle doors, Mi-8 left door
--    43    UH-1 left door
--    44    UH-1 right door
--    86    Mi-8 cargo doors
--    133   Mi-8 left blister
--    131   Mi-8 right blister
--
function Unit:embarkOrDisembark(groups, radiusThreshold, distanceThreshold, dx, dy)
  if not self:chalk() then
    self:embarkChalk(groups, radiusThreshold, distanceThreshold)
  else
    self:disembarkChalk(dx, dy)
  end
end

-- Selects and sorts the given groups by their zone radius and their distance
-- from this unit.
function Unit:embarks(groups, radiusThreshold)
  if not radiusThreshold then
    local width, length = self:widthAndLength()
    radiusThreshold = width + length
  end
  local embarks = {}
  for _, group in ipairs(groups) do
    local zone = group:zone()
    if zone.radius < radiusThreshold then
      table.insert(embarks, {group = group, distance = zone.radius + self:distanceFromZone(zone)})
    end
  end
  table.sort(embarks, function(lhs, rhs)
    return lhs.distance < rhs.distance
  end)
  return embarks
end

-- Embarks a chalk from the given groups. Groups become chalks once embarked.
-- Assumes that all the given groups are eligable for embarking. Selects just
-- one group. The given radius threshold defines the maximum size of the group
-- zone for embarking. Does not embark groups more spread out that this.
function Unit:embarkChalk(groups, radiusThreshold, distanceThreshold)
  local embarks = self:embarks(groups, radiusThreshold)
  if #embarks == 0 then return end
  if embarks[1].distance < distanceThreshold then
    self:embarkGroup(embarks[1].group)
  end
end

-- Embarks the given group. Destroys the group.
function Unit:embarkGroup(group)
  local units = Units()
  units:addGroup(group)
  world.onEvent{
    id = world.event.S_EVENT_EMBARKING,
    initiator = self,
    group = group,
    units = units,
  }
  self:setChalk(units)
  group:destroy()
  world.onEvent{
    id = world.event.S_EVENT_EMBARKED,
    initiator = self,
    group = group,
    units = units,
  }
  return units
end

-- Disembarks when landing. Does nothing if the unit has no chalk. The
-- disembarked chalk forms two columns alongside the unit, pointing in the
-- unit's heading direction. Uses the unit's width-length average as the default
-- distance between the two columns.
function Unit:disembarkChalk(dx, dy)
  local chalk = self:chalk()
  if not chalk then return end
  self:setChalk(nil)
  if not dx then
    local width, length = self:widthAndLength()
    dx = (width + length) / 2
  end
  chalk:formColumns(dx, dy or 1, 2)
  local heading = self:heading()
  chalk:rotateXY(heading)
  chalk:translateXY(self:getPoint().x, self:getPoint().z)
  chalk:setHeading(heading)
  world.onEvent{
    id = world.event.S_EVENT_DISEMBARKING,
    initiator = self,
    units = chalk,
  }
  local group = chalk:spawn()
  group:setDisembarkedBy(self:getPlayerName())
  world.onEvent{
    id = world.event.S_EVENT_DISEMBARKED,
    initiator = self,
    group = group,
    units = chalk,
  }
end

-- Crashing spawns the chalk randomly, damaged and decimated. Uses the
-- helicopter's crash speed to determine survivability. Everyone dies at 60 mph
-- (26 metres per second).
function Unit:crashChalk()
  local chalk = self:chalk()
  if not chalk then return end
  self:setChalk(nil)
  chalk:decimate(self:speed() / 26.8224)
  if #chalk.units == 0 then return end
  if not chalk:isSurvivor() then
    local suffix
    if chalk.name then
      suffix = ' of ' .. chalk.name
    else
      suffix = ''
    end
    chalk.name = 'Survivors' .. suffix
  end
  chalk:setProbability(math.random())
  local _, length = self:widthAndLength()
  chalk:randomizeXYInZone{point = self:getPoint(), radius = length}
  chalk:randomizeHeading()
  world.onEvent{
    id = world.event.S_EVENT_SURVIVING,
    initiator = self,
    units = chalk,
  }
  local group = chalk:spawn()
  world.onEvent{
    id = world.event.S_EVENT_SURVIVED,
    initiator = self,
    group = group,
    units = chalk,
  }
end

-- Automatically disembark the chalk when bad things happen. Do sensible things
-- in response.
world.addEventFunction(function(event)
  if not event.initiator then return end
  if event.id == world.event.S_EVENT_CRASH then
    event.initiator:crashChalk()
  elseif event.id == world.event.S_EVENT_EJECTION then
    -- Ejecting either spawns survivors or makes them disappear forever. Use
    -- height above land to determine which one happens.
    if event.initiator:height() < 10 then
      event.initiator:crashChalk()
    else
      event.initiator:setChalk(nil)
    end
  elseif event.id == world.event.S_EVENT_PLAYER_ENTER_UNIT then
    -- There are some strange scenarios where the player re-enters the same unit
    -- without leaving it, and without crashing or ejecting.
    event.initiator:setChalk(nil)
  elseif event.id == world.event.S_EVENT_PLAYER_LEAVE_UNIT then
    event.initiator:setChalk(nil)
  end
end)

-- True if this group is a survivor group.
function Group:isSurvivor()
  return string.find(self:getName(), 'Survivors') == 1
end

-- True if this Units instance represents a survivor group.
function Units:isSurvivor()
  return self.name and string.find(self.name, 'Survivors') == 1
end

--------------------------------------------------------------------------------
--                                                                         Crash
--------------------------------------------------------------------------------

world.event.S_EVENT_CRASH_SPAWNING = 'S_EVENT_CRASH_SPAWNING'
world.event.S_EVENT_CRASH_SPAWNED = 'S_EVENT_CRASH_SPAWNED'

world.event.S_EVENT_CRASH_FLARING = 'S_EVENT_CRASH_FLARING'
world.event.S_EVENT_CRASH_FLARED = 'S_EVENT_CRASH_FLARED'

world.event.S_EVENT_CRASH_CLEANING = 'S_EVENT_CRASH_CLEANING'
world.event.S_EVENT_CRASH_CLEANED = 'S_EVENT_CRASH_CLEANED'

-- Crash: a time, a zone, a timer, a coalition, a flare colour, a flare counter,
-- a unit name and a unit type name. The zone and unit-related information comes
-- from the unit that crashed. Do not retain the original unit. Once set up, the
-- crash site no longer cares who crashed. The simulator can remove the crashing
-- unit before the crash site disappears.
Crash = {}
Crash.__index = Crash
setmetatable(Crash, {
  __call = function(self, unit)
    local _, length = unit:widthAndLength()
    local crash = {
      time = timer.getTime(),
      zone = {point = unit:getPoint(), radius = length},
      side = unit:getCoalition(),
      name = unit:getName(),
      typeName = unit:getTypeName(),
    }
    return setmetatable(crash, self)
  end,
})

-- Spawning does not immediately pop a flare. It just starts the site's crash
-- timer, which subsequently pops flares.
function Crash:spawn()
  self.timer = Timer(function()
    self:fired()
  end)
  world.onEvent{id = world.event.S_EVENT_CRASH_SPAWNING, crash = self}
  if not self.timer.id then
    self.timer:delay(10, true)
  end
  world.onEvent{id = world.event.S_EVENT_CRASH_SPAWNED, crash = self}
end

-- Fires a signal flare, or cleans the crash site. Cleaning depends on the
-- coalition. If all the ground units have left the zone, the crash site stops
-- flaring. There is no one left there to pop them.
function Crash:fired()
  if #Unit.allGroundUnitsInZone(self.zone, self.side) > 0 then
    self:flare()
  else
    self:clean()
  end
end

-- Fires a flare.
function Crash:flare()
  world.onEvent{id = world.event.S_EVENT_CRASH_FLARING, crash = self}
  local color = self.flareColor or trigger.flareColor.Green
  local azimuth = self.azimuth or 0
  trigger.action.signalFlare(self.zone.point, color, azimuth)
  self.counter = (self.counter or 0) + 1
  world.onEvent{id = world.event.S_EVENT_CRASH_FLARED, crash = self}
end

-- Cleans a crash site. Invoked by the world-event handler responding to
-- crash-flaring events, or just before the signal flare. It just removes the
-- crash timer, which removes the crash site when the garbage collector arrives.
function Crash:clean()
  world.onEvent{id = world.event.S_EVENT_CRASH_CLEANING, crash = self}
  self.timer:remove()
  world.onEvent{id = world.event.S_EVENT_CRASH_CLEANED, crash = self}
end

-- Whenever there is a crash, spawn a crash site. Clean up the crash site when
-- the coalition leaves. The site fires flares until empty, or the flares run
-- out because you cleaned the crash site. Crash sites pop infinite flares by
-- default. Crash sites send world events while active.
world.addEventFunction(function(event)
  if not event.initiator then return end
  if event.id == world.event.S_EVENT_CRASH then
    Crash(event.initiator):spawn()
  end
end)

--------------------------------------------------------------------------------
--                                                                        scores
--------------------------------------------------------------------------------

world.event.S_EVENT_PLAYER_SCORED = 'S_EVENT_PLAYER_SCORED'

-- When units score, they add points to their player. So players jumping to
-- different units carry their scores with them.
local scores = {}

-- Answers the scores to-date for this unit's player, or `nil` if this unit has
-- no player.
function Unit:playerScores()
  local playerName = self:playerName()
  return playerName and scores[playerName]
end

-- Adds a score value for the given score key. Does nothing if the unit has no
-- player, which includes an embarked-by player. Scoring sends a player-scored
-- world event. The event contains this unit as the initiator, the player name
-- and the up-to-date score.
function Unit:addPlayerScore(key, value)
  local playerName = self:playerName()
  if playerName then
    local playerScores = scores[playerName]
    if not playerScores then
      playerScores = {}
      scores[playerName] = playerScores
    end
    local score = (playerScores[key] or 0) + value
    playerScores[key] = score
    world.onEvent{
      id = world.event.S_EVENT_PLAYER_SCORED,
      initiator = self,
      playerName = playerName,
      score = score,
    }
  end
end

-- Answers a copy of all the player scores indexed by player name.
function Unit.allPlayerScores()
  return table.deepcopy(scores)
end

-- Collates all the given player's scores. answering zero or more strings, one
-- string for each score key-value pair where the key and the accumulated value
-- have a colon delimiter. Sorts the score strings by value, low to high.
function Unit.playerScoreStringsFor(playerName)
  local strings = {}
  local playerScores = Unit.allPlayerScores()[playerName]
  if playerScores then
    for key, value in pairs(playerScores) do
      table.insert(strings, key .. ':' .. value)
    end
    table.sort(strings)
  end
  return strings
end

-- Answers lines of text representing scores for all players.
function Unit.allPlayerScoreLines()
  local lines = {}
  local playerNames = table.keys(scores)
  table.sort(playerNames)
  for _, playerName in ipairs(playerNames) do
    local strings = Unit.playerScoreStringsFor(playerName)
    table.insert(strings, 1, playerName)
    table.insert(lines, table.concat(strings, ' '))
  end
  return lines
end

-- Outputs a text message to all sides showing the scores for all players.
-- Outputs nothing if there are no scores as yet.
function Unit.outAllPlayerScores(seconds, clear)
  local lines = Unit.allPlayerScoreLines()
  if #lines > 0 then
    trigger.action.outText(table.concat(lines, '\n'), seconds or 10, clear)
  end
end
