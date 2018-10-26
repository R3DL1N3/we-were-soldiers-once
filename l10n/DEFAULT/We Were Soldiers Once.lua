-- R3DL1N3/We Were Soldiers Once.lua
--
-- Copyright © 2017, R3DL1N3, United Kingdom
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the “Software”), to
-- deal in the Software without restriction, including without limitation the
-- rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
-- sell copies of the Software, and to permit persons to whom the Software is
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

function Unit:addScore(key, score)
  self:addPlayerScore(key, 1)
  self:addPlayerScore('Score', score)
end

-- Periodically outputs player scores to all sides.
world.addEventFunction(function(event)
  if event.id == world.event.S_EVENT_PLAYER_SCORED then
    UserFlag['77'] = (UserFlag['77'] or 0) + 1
  end
end)

slick = {}

-- Slicks can embark all troopers, including tasked troopers.
function slick.embarkOrDisembark(unit)
  if not unit then return end
  if not unit:isLanded() then return end
  local groups = table.fromiter(Group.filtered(coalition.side.BLUE, Group.Category.GROUND, function(group)
    return group:getSize() > 0 and cav.names:includesGroup(group)
  end))
  unit:embarkOrDisembark(groups, 100, 100)
end

world.addEventFunction(function(event)
  -- Sometimes there is no initiator. Just ignore it in that case.
  if not event.initiator then return end
  if event.id == world.event.S_EVENT_CRASH then
    trigger.action.outText(event.initiator:getName() .. ' crashed', 3)
    event.initiator:addScore('crashes', -50)
  elseif event.id == world.event.S_EVENT_EMBARKED then
    local text = event.initiator:getName() .. ' embarked ' .. event.units.name
    trigger.action.outTextForCoalition(coalition.side.BLUE, text, 3)
  elseif event.id == world.event.S_EVENT_DISEMBARKED then
    local text = event.initiator:getName() .. ' disembarked ' .. event.units.name
    trigger.action.outTextForCoalition(coalition.side.BLUE, text, 3)
  elseif event.id == world.event.S_EVENT_EJECTION then
    trigger.action.outText(event.initiator:getName() .. ' ejected', 3)
    event.initiator:addScore('ejects', -10)
  elseif event.id == world.event.S_EVENT_PLAYER_LEAVE_UNIT then
    event.initiator:addScore('leaves', -25)
  elseif event.id == world.event.S_EVENT_HIT then
    local score
    if event.initiator:isHostileWith(event.target) then
      score = event.initiator:disembarkedBy() and 3 or 1
    elseif event.initiator:isFriendlyWith(event.target) then
      score = -10
    else
      score = 0
    end
    event.initiator:addScore('hits', score)
    if event.target:getLife() < 1 then
      local life = event.target.getLife0 and event.target:getLife0() or 1
      event.initiator:addScore('kills', life * score)
    end
  end
end)

--------------------------------------------------------------------------------
--                                                                           kia
--------------------------------------------------------------------------------

kia = {}

world.addEventFunction(function(event)
  if not event.initiator then return end
  if event.id == world.event.S_EVENT_DEAD then
    local unit = event.initiator
    if not unit.getCoalition then return end
    local side = unit:getCoalition()
    kia[side] = (kia[side] or 0) + 1
    UserFlag['7'] = (UserFlag['7'] or 0) + 1
  end
end)

local cavMax = 1000
local vpaMax = 2500

function kia.out(seconds)
  local cav = kia[coalition.side.BLUE] or 0
  local vpa = kia[coalition.side.RED] or 0
  local text = 'KIA Cav ' .. cav .. '/' .. cavMax .. ', VPA ' .. vpa .. '/' .. vpaMax
  trigger.action.outText(text, seconds or 3)
end

--------------------------------------------------------------------------------
--                                                                           cav
--------------------------------------------------------------------------------

cav = {
  zone = Zone('Cav'),
  -- Names for chalks and troopers.
  names = Names('Cav Chalk #', 'Cav Trooper #'),
}

-- Spawns one chalk of Cavalry.
function cav.spawnChalk(fromZone, toZone)
  if #Unit.allInZone(fromZone, coalition.side.BLUE, Group.Category.GROUND) ~= 0 then return end
  if cav.names.unitCounter.counter >= cavMax then return end
  if #table.fromiter(Unit.filtered(coalition.side.BLUE, Group.Category.GROUND)) >= 150 then return end
  local units = Units()
  units:addType('Soldier M4', 7)
  units:addType('Soldier M249', 1)
  units:setExcellentSkill()
  units:setRandomTransportable(false)
  cav.names:applyTo(units)
  units:formSquareInZones(fromZone, cav.zone)
  if toZone then
    local mission = Mission()
    local unit = units:all()[1]
    mission:addTurningPoint(unit.x, unit.y)
    mission:turningToPoint(toZone.point)
    units.route = {points = mission:waypoints()}
  end
  units:spawn(country.id.USA, Group.Category.GROUND)
end

--------------------------------------------------------------------------------
--                                                                           vpa
--------------------------------------------------------------------------------

vpa = {
  zone = Zone('VPA'),
  names = Names('VPA Squad #', 'VPA Soldier #'),
}

function vpa.spawnSquad(zone)
  if #Unit.allInZone(zone, coalition.side.RED, Group.Category.GROUND) ~= 0 then return end
  if vpa.names.unitCounter.counter >= vpaMax then return end
  if #table.fromiter(Unit.filtered(coalition.side.RED, Group.Category.GROUND)) >= 300 then return end
  local units = Units()
  units:addType('Infantry AK', 7)
  units:addType('Paratrooper RPG-16', 1)
  units:setGoodSkill()
  units:setRandomTransportable(false)
  vpa.names:applyTo(units)
  units:formSquareInZones(zone, vpa.zone)
  units:spawn(country.id.RUSSIA, Group.Category.GROUND)
end

-- Directs all VPA groups to attack blue units within the given zone, the Chu
-- Pong mountain area.
--
-- Be careful to avoid lagging. However, at the same time, take care to balance
-- the task assignments. Otherwise, favoured locations will spawn first when the
-- spawn zone becomes free. Instead pick one at random.
function vpa.attackInZone(zone)
  if #coalition.getPlayers(coalition.side.RED) > 0 then return end
  local units = Unit.allInZone(zone, coalition.side.BLUE, Group.Category.GROUND)
  for unit in Unit.unitsInZone(zone, coalition.side.BLUE, Group.Category.HELICOPTER) do
    table.insert(units, unit)
  end
  local filteredGroups = Group.filtered(coalition.side.RED, Group.Category.GROUND, function(group)
    return vpa.names:includesGroup(group)
  end)
  if #units == 0 then
    for group in filteredGroups do
      group:getController():resetTask()
    end
  else
    local groups = table.fromiter(filteredGroups)
    local group = groups[math.random(#groups)]
    group:setTurningToUnitsTask(units, AI.Task.VehicleFormation.OFF_ROAD, 10)
  end
end
