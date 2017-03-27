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

kia = {}

world.addEventFunction(function(event)
  if event.id == world.event.S_EVENT_DEAD then
    local unit = event.initiator
    local side = unit:getCoalition()
    kia[side] = (kia[side] or 0) + 1
    UserFlag['7'] = (UserFlag['7'] or 0) + 1
  end
end)

function kia.out(seconds)
  local cav = kia[coalition.side.BLUE] or 0
  local vpa = kia[coalition.side.RED] or 0
  local text = 'KIA Cav ' .. cav .. ', VPA ' .. vpa
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

-- Spawns one chalk of Bravo company, 1st battalion, 7th Cavalry.
function cav.spawnChalk(zone)
  if #Unit.allInZone(zone, coalition.side.BLUE, Group.Category.GROUND) ~= 0 then return end
  if cav.names.unitCounter.counter >= 1000 then return end
  local units = Units()
  units:addType('Soldier M4', 7)
  units:addType('Soldier M249', 1)
  units:setExcellentSkill()
  units:setRandomTransportable(false)
  local angle
  if math.distancexz(zone.point, cav.zone.point) < cav.zone.radius then
    angle = math.anglexz(zone.point, cav.zone.point)
  else
    angle = 2 * math.pi * math.random()
  end
  units:formSquare(1, 1)
  local center = units:center()
  units:translateXY(-center.x, -center.y)
  units:rotateXY(angle)
  units:translateXY(zone.point.x, zone.point.z)
  units:setHeading(angle)
  cav.names:applyTo(units)
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
  if vpa.names.unitCounter.counter >= 2500 then return end
  local units = Units()
  units:addType('Infantry AK', 7)
  units:addType('Paratrooper RPG-16', 1)
  units:setGoodSkill()
  units:setRandomTransportable(false)
  local angle
  if math.distancexz(zone.point, vpa.zone.point) < vpa.zone.radius then
    angle = math.anglexz(zone.point, vpa.zone.point)
  else
    angle = 2 * math.pi * math.random()
  end
  units:formSquare(1, 1)
  local center = units:center()
  units:translateXY(-center.x, -center.y)
  units:rotateXY(angle)
  units:translateXY(zone.point.x, zone.point.z)
  units:setHeading(angle)
  vpa.names:applyTo(units)
  units:spawn(country.id.RUSSIA, Group.Category.GROUND)
end

function vpa.attackInZone(zone)
  if #coalition.getPlayers(coalition.side.RED) > 0 then return end
  local units = Unit.allInZone(zone, coalition.side.BLUE, Group.Category.GROUND)
  if #units == 0 then return end
  for group in Group.untasked(coalition.side.RED, Group.Category.GROUND) do
    group:setTurningToUnitsTask(units)
  end
end
