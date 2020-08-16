local Map = include 'lib/map'

local rate = 30

local tau = math.pi * 2
local qpi = math.pi / 4

local Integrator = {}
Integrator.__index = Integrator

function Integrator.new(f, s)
	local i = setmetatable({}, Integrator)
	if s == nil then
		i:set_weight(f)
	else
		i.inertia = f
		i.sensitivity = s
	end
	i.value = 0.0
	return i
end

function Integrator:add(v)
	self.value = self.value + v * self.sensitivity
end

function Integrator:step(v, damp)
	self.value = self.value * self.inertia
	if v ~= nil then
		self:add(v)
	end
	if damp ~= nil then
		self.value = self.value * damp
	end
end

function Integrator:dampen(f)
	self.value = self.value * f
end

function Integrator:set_weight(w)
	self.inertia = w
	if w == 0 then
		-- zero weight = pass-through, no inertia / no smoothing
		self.sensitivity = 1
	else
		-- set sensitivity such that the area under the integrator's impulse response from 0 (initial
		-- impulse) to `rate` steps (1 second) will be 1.0 for any value of `w`
		local logw = math.log(w)
		self.sensitivity = logw / (math.pow(w, rate) - w + logw)
	end
end

local Rover = {}
Rover.__index = Rover

function Rover.new()
	local r = setmetatable({}, Rover)
	r.noise = Integrator.new(0.3)
	r.drift = Integrator.new(0.9)
	r.drive = Integrator.new(1, 0.0001)
	r.drift_amount = 0.0 -- bipolar; positive is linear, negative is exponential
	r.rate = 0
	r.div = 1
	r.disposition = 0
	r.position = 0
	r.map = Map.new()
	r.p = 1
	r.point_distance = 0
	r.point_highlight = Integrator.new(0.9, 1)
	r.highlight_point = r.map.points[1]
	r.hold = 0
	r.values = {
		a = 0,
		b = 0,
		c = 0,
		d = 0,
		p = 0
	}
	return r
end

-- TODO: in 'vinyl mode', this shouldn't change drive directly, but add to it
-- ...which implies another exp/lin control like drift amount
function Rover:nudge(delta)
	self.drive:add(delta)
end

function Rover:step()
	local damp = 1
	if self.hold == 4 then
		damp = 0.1
	elseif self.hold == 3 then
		damp = 0.5
	elseif self.hold == 2 then
		damp = 0.8
	elseif self.hold == 1 then
		damp = 0.95
	end
	self.noise:step((math.random() - 0.5), damp)
	self.drift:step(self.noise.value, damp)
	self.drive:step(nil, damp)
	self.point_highlight:step()
	self.rate = self.drift.value * math.max(0, self.drift_amount) + self.drive.value * math.pow(1 + math.max(0, -self.drift_amount), self.drift.value)
	self.disposition = (self.disposition + self.rate) % tau
	local div_rate = self.rate / self.div
	self.position = (self.position + div_rate) % tau
	self.values.a = math.cos(self.position - qpi) * 0.5 + 0.5
	self.values.b = math.sin(self.position - qpi) * 0.5 + 0.5
	self.values.c = 1 - self.values.a
	self.values.d = 1 - self.values.b

	self.values.p, self.p = self.map:read(self.position)
	local point = self.map.points[self.p]
	local distance = self.position - point.i
	local d2 = self.position - tau - point.i
	if math.abs(d2) < math.abs(distance) then
		distance = d2
	end
	if (self.position >= point.i and self.position - div_rate < point.i) or (self.position <= point.i and self.position - div_rate > point.i) or (self.position <= point.i + tau and self.position - div_rate > point.i + tau) or (self.position >= point.i - tau and self.position - div_rate < point.i - tau) then
		self.point_highlight:add(1)
		self.highlight_point = point
		self:on_point_cross(point.o)
	end
	self.point_distance = distance
end

function Rover:on_point_cross() end

return Rover