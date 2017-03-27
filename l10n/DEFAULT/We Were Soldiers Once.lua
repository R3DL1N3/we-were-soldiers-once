cav = {
  zone = Zone('B1/7 Cav'),
  -- Names for chalks and troopers.
  names = Names('B1/7 Cav Chalk #', 'B1/7 Cav Trooper #'),
}

-- Spawns one chalk of Bravo company, 1st battalion, 7th Cavalry.
function cav.spawnChalk(zone)
  if #Unit.allInZone(zone, coalition.side.BLUE, Group.Category.GROUND) ~= 0 then
    return
  end
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
