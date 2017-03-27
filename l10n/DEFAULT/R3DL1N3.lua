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

-- Answers the horizontal angle between two points, from the first point to the
-- second point.
function math.anglexz(p, q)
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
function Timer:fire(time)
  self.time = time
  self:fired()
  return self.repeats and time + self.seconds
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

Zone = setmetatable({}, {
  -- Constructs a zone using either a string or a zone itself as the zone table.
  -- Zone tables contain a point and a radius. The point is a three-dimensional
  -- vector.
  __call = function(self, arg)
    if 'string' == type(arg) then
      return trigger.misc.getZone(arg)
    end
    return arg
  end,
})

--------------------------------------------------------------------------------
--                                                                         Group
--------------------------------------------------------------------------------

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
function Group.tasked(side, category)
  return Group.filtered(side, category, function(group)
    return group:getController():hasTask()
  end)
end

-- Answers all the untasked groups.
function Group.untasked(side, category)
  return Group.filtered(side, category, function(group)
    return not group:getController():hasTask()
  end)
end

-- Sets up a counter attack. Searches for `fromSide` groups without controller
-- tasks. Adds a turning-point mission for each untasked group if `toSide` units
-- occupy the given zone.
function Group.setTurningToUnitsTasksInZone(fromSide, toSide, category, zone)
  local units = Unit.allInZone(zone, toSide, category)
  if #units == 0 then return end
  for group in Group.filtered(fromSide, category, function(group)
    return not group:getController():hasTask()
  end) do
    group:setTurningToUnitsTask(units)
  end
end

-- Sets this group's task to turn towards the location of the nearest member of
-- the given units. Nearest means the smallest horizontal distance from this
-- group's centre point. Sorts the given table of units. Replaces the group
-- controller's current task. Does nothing if this group is empty.
function Group:setTurningToUnitsTask(units)
  local centerPoint = self:centerPoint()
  if centerPoint == nil then return end
  table.sort(units, function(lhs, rhs)
    return math.distancexz(lhs:getPoint(), centerPoint) < math.distancexz(rhs:getPoint(), centerPoint)
  end)
  local mission = Mission()
  mission:turningToPoint(self:getUnit(1):getPoint())
  mission:turningToPoint(units[1]:getPoint())
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

-- Only works with ground groups.
function Group:continueMoving()
  trigger.action.groupContinueMoving(self)
end

--------------------------------------------------------------------------------
--                                                                          Unit
--------------------------------------------------------------------------------

function Unit:life()
  return self:getLife() / self:getLife0()
end

-- Answers the unit's height above ground level. Importantly, the land height
-- needs a two-dimensional vector, a table, with keys `x` and `z` for horizontal
-- and vertical coordinates.
--
-- Be aware that sometimes, this gives odd-looking results, i.e. negative when a
-- helicopter is hovering close to the ground.
function Unit:height()
  local p = self:getPoint()
  return p.y - land.getHeight{x = p.x, z = p.z}
end

-- Returns the distance between two units, this unit and another given unit
-- which may be the same unit.
function Unit:distanceXZ(other)
  return math.distancexz(self:getPoint(), other:getPoint())
end

-- Answers true if this unit is within the given zone.
function Unit:inZone(zone)
  return math.distancexz(self:getPoint(), zone.point) < zone.radius
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
    local angle = 2 * math.pi * math.random()
    local radius = zone.radius * math.random()
    local delta = math.deltaxz(angle, radius)
    unit.x = zone.point.x + delta.x
    unit.y = zone.point.z + delta.z
  end
end

function Units:translateXY(dx, dy)
  for _, unit in ipairs(self.units) do
    unit.x = unit.x + dx
    unit.y = unit.y + dy
  end
end

-- Rotates all the units by the given angle about the x-y plane's origin.
function Units:rotateXY(angle)
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

-- Forms the units into a square using the given displacement between units.
function Units:formSquare(dx, dy)
  local all = self:all()
  local numberOfRows = math.floor(math.sqrt(#all))
  for index, unit in ipairs(all) do
    local column = (index - 1) % numberOfRows
    local row = (index - 1 - column) / numberOfRows
    unit.x = column * dx
    unit.y = row * dy
  end
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

-- Sets up the units condition, a fraction between 0 and 1.
function Units:setProbability(fraction)
  self.probability = fraction
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
  local group = coalition.addGroup(country or self.country, category or self.category, self:table())
  -- Cache the unit skills. This is the only time that the units and the skills
  -- exist together at the same time. This assumes, of course, that the order of
  -- the spawned units matched the order of the configured units. This will fail
  -- if this assumption is wrong for any reason. The index for the spawned units
  -- must correspond to the index for the `self` units.
  for index, unit in ipairs(group:getUnits()) do
    unit:setSkill(self.units[index].skill)
  end
  return group
end

-- Adds the given group, or more precisely, adds units based on the given group.
-- Takes the name of the units from the group name, unless the units already
-- have a name. Adds units for each group unit, copying the type, name and
-- skill.
function Units:addGroup(group)
  if not self.name then
    self.name = group:getName()
  end
  for _, unit in ipairs(self:getUnits()) do
    self:add{
      type = unit:getTypeName(),
      name = unit:getName(),
      skill = unit:skill(),
    }
  end
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

-- Gives access to the waypoints. Answers the actual waypoints, not a copy.
-- Modifying the result also modifies the mission.
function Mission:waypoints()
  return self.params.route.points
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
--                                                                         inAir
--------------------------------------------------------------------------------

local wasInAir = {}

local inAirFunctions = {}

-- Answers true if the unit was in the air at the last sampling.
function Unit:wasInAir()
  return wasInAir[self:getID()]
end

-- Setter for unit's was-in-air state.
function Unit:setWasInAir(was)
  wasInAir[self:getID()] = was
end

-- Sets the new in-air status of this unit. Notifies the in-air functions,
-- passing the current in-air status as well as the previous in-air status: what
-- it is, and what it was. Does not notify until the status changes. Change
-- includes changing from unknown to known (from nil to true or false).
function Unit:setInAir(inAir)
  if not inAir then
    inAir = self:inAir()
  end
  local was = self:wasInAir()
  local funcs = inAirFunctions[self:getID()]
  if funcs then
    for _, func in ipairs(funcs) do
      if inAir ~= was then
        func(inAir, was)
      end
    end
  end
  self:setWasInAir(inAir)
end

-- Adds an in-air function for this unit. Answers a function identifier number.
-- Use this to remove the function subsequently, whenever necessary.
function Unit:addInAirFunction(func)
  local funcs = inAirFunctions[self:getID()]
  if not funcs then
    funcs = {}
    inAirFunctions[self:getID()] = funcs
  end
  return table.insert(funcs, func)
end

function Unit:removeInAirFunction(funcId)
  local funcs = inAirFunctions[self:getID()]
  if funcs then
    table.remove(funcs, funcId)
  end
end

-- Runs once every second. Samples the in-air status of all player units.
local inAirTimer = Timer(function()
  for _, side in ipairs{coalition.side.NEUTRAL, coalition.side.RED, coalition.side.BLUE} do
    for _, unit in ipairs(coalition.getPlayers(side)) do
      unit:setInAir(unit:inAir())
    end
  end
end)

function setInAirTimerDelay(seconds)
  inAirTimer:delay(seconds, true)
end
