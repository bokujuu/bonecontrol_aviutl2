--[[
	AviUtl2 Bone Control (general purpose)
	This module provides parent storage and basic transformation utilities
	for simple parent/child bone control in AviUtl2 scripting environment.
	It is a pure-Lua implementation with optional debug overlay.
]]--

-- global table for AviUtl2 bone control (isolated from aviutl1 reference)
r2_parent_info = {}
for i = 0, 100 do
	r2_parent_info[i] = {}
end

-- initialize index 0 as neutral parent
r2_parent_info[0].x = 0
r2_parent_info[0].y = 0
r2_parent_info[0].z = 0
r2_parent_info[0].rx = 0
r2_parent_info[0].ry = 0
r2_parent_info[0].rz = 0
r2_parent_info[0].zoom = 1
r2_parent_info[0].alpha = 1
r2_parent_info[0].disp = false
-- aspect (AviUtl2 uses single aspect value [-1..1])
r2_parent_info[0].aspect = 0
-- center (pivot) and aspect defaults
r2_parent_info[0].cx = 0
r2_parent_info[0].cy = 0
r2_parent_info[0].cz = 0
r2_parent_info[0].ax = 1
r2_parent_info[0].ay = 1
r2_parent_info[0].az = 1
-- explicit non-uniform scales for aspect chaining
r2_parent_info[0].sx = 1
r2_parent_info[0].sy = 1

-- local math shortcuts
local sin = math.sin
local cos = math.cos
local PI = math.pi
local pi_180 = PI / 180
local abs = math.abs
local acos = math.acos
local atan = math.atan2

-- compare helper (tolerant equality for two corners)
local ABS = function(x0, y0, z0, x1, y1, z1, x2, y2, z2, x3, y3, z3)
	return abs(x0 - x1) < 1 and abs(y0 - y1) < 1 and abs(z0 - z1) < 1 and abs(x2 - x3) < 1 and abs(y2 - y3) < 1 and abs(z2 - z3) < 1
end

-- rotate by AviUtl’s convention around z then y then x
local _rot = function(radx, rady, radz, x, y)
	local x0 = x * cos(radz) - y * sin(radz)
	local y0 = x * sin(radz) + y * cos(radz)
	local z0 = -x0 * sin(rady)
	return x0 * cos(rady), y0 * cos(radx) - z0 * sin(radx), y0 * sin(radx) + z0 * cos(radx)
end

-- double rotation: first child, then parent
local _rot_double = function(radx0, rady0, radz0, radx1, rady1, radz1, x, y)
	local x0, y0, z0 = _rot(radx0, rady0, radz0, x, y)
	local x1 = x0 * cos(radz1) - y0 * sin(radz1)
	local y1 = x0 * sin(radz1) + y0 * cos(radz1)
	local z1 = z0 * cos(rady1) - x1 * sin(rady1)
	return z0 * sin(rady1) + x1 * cos(rady1), y1 * cos(radx1) - z1 * sin(radx1), y1 * sin(radx1) + z1 * cos(radx1)
end

-- rotation composition solver (adopted from aviutl1 reference, isolated namespace)
r2_P_C_ROTATION = function(rx0, ry0, rz0, rx1, ry1, rz1)
	-- object width/height from current environment (fallback if fields missing)
	local w = obj.w or obj.getvalue and (obj:getvalue("width") or obj:getvalue("w")) or 0
	local h = obj.h or obj.getvalue and (obj:getvalue("height") or obj:getvalue("h")) or 0
	if not w or w == 0 then w = 100 end
	if not h or h == 0 then h = 100 end
	-- degrees to radians
	rx0 = rx0 * pi_180
	ry0 = ry0 * pi_180
	rz0 = rz0 * pi_180
	rx1 = rx1 * pi_180
	ry1 = ry1 * pi_180
	rz1 = rz1 * pi_180
	-- image local corners
	local xl = -w * 0.5
	local yl = -h * 0.5
	local xr = -xl
	local yr = yl
	-- transform two corners with double rotation
	local txl, tyl, tzl = _rot_double(rx0, ry0, rz0, rx1, ry1, rz1, xl, yl)
	local txr, tyr, tzr = _rot_double(rx0, ry0, rz0, rx1, ry1, rz1, xr, yr)
	-- candidate solutions
	local pi = atan((txr + txl) * w, (txr - txl) * h)
	local RZ = {pi, pi + PI}
	local RY = {}
	local rz, cz, sz, ry, txl1, tyl1, tzl1, txr1, tyr1, tzr1
	for i = 1, 2 do
		rz = RZ[i]
		cz = cos(rz)
		sz = sin(rz)
		pi = (txr + txl) * sz / h + (txr - txl) * cz / w
		if pi < -1 then pi = -1 elseif 1 < pi then pi = 1 end
		pi = acos(pi)
		RY[1] = pi
		RY[2] = -pi
		for j = 1, 2 do
			ry = RY[j]
			pi = -(tyl - tyr) * sz / w - (tyl + tyr) * cz / h
			if pi < -1 then pi = -1 elseif 1 < pi then pi = 1 end
			pi = acos(pi)
			txl1, tyl1, tzl1 = _rot(pi, ry, rz, xl, yl)
			txr1, tyr1, tzr1 = _rot(pi, ry, rz, xr, yr)
			if ABS(txl, tyl, tzl, txl1, tyl1, tzl1, txr, tyr, tzr, txr1, tyr1, tzr1) then
				return pi / pi_180, ry / pi_180, rz / pi_180
			end
			txl1, tyl1, tzl1 = _rot(-pi, ry, rz, xl, yl)
			txr1, tyr1, tzr1 = _rot(-pi, ry, rz, xr, yr)
			if ABS(txl, tyl, tzl, txl1, tyl1, tzl1, txr, tyr, tzr, txr1, tyr1, tzr1) then
				return -pi / pi_180, ry / pi_180, rz / pi_180
			end
		end
	end
end

-- simple debug overlay: show parent/child id with tint
r2_P_C_DISP = function(NUM, pc)
	-- step2_fix: disable debug drawing to guarantee no side-effects on rendering
	return
end

-- helper to compose transforms outward from a parent (optional utility)
r2_outBonecontrol = function(pinfo, x, y, z, rx, ry, rz, zoom, alpha)
	if type(pinfo) ~= "table" then
		return
	end
	local ozoom = pinfo.zoom
	local dx = x * ozoom
	local dy = y * ozoom
	local dz = z * ozoom
	local rad = pinfo.rz * pi_180
	local c = math.cos(rad)
	local s = math.sin(rad)
	local x1 = dx * c - dy * s
	local y1 = dx * s + dy * c
	rad = pinfo.ry * pi_180
	c = math.cos(rad)
	s = math.sin(rad)
	local z1 = dz * c - x1 * s
	local ox = (dz * s + x1 * c) + pinfo.x
	rad = pinfo.rx * pi_180
	c = math.cos(rad)
	s = math.sin(rad)
	local oy = (y1 * c - z1 * s) + pinfo.y
	local oz = (y1 * s + z1 * c) + pinfo.z
	local orx, ory, orz = r2_P_C_ROTATION(rx, ry, rz, pinfo.rx, pinfo.ry, pinfo.rz)
	ozoom = zoom * ozoom
	local oalpha = alpha * pinfo.alpha
	return ox, oy, oz, orx, ory, orz, ozoom, oalpha
end

-- helper to write transforms into a parent info table (optional utility)
r2_inBonecontrol = function(pinfo, x, y, z, rx, ry, rz, zoom, alpha)
	if type(pinfo) ~= "table" then
		pinfo = {}
	end
	pinfo.x = x
	pinfo.y = y
	pinfo.z = z
	pinfo.rx = rx
	pinfo.ry = ry
	pinfo.rz = rz
	pinfo.zoom = zoom
	pinfo.alpha = alpha
end


