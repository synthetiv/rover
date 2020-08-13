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

function Integrator:step(v)
	self.value = self.value * self.inertia
	if v ~= nil then
		self:add(v)
	end
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
	r.drive_inertia_base = 1.0 -- TODO: add control
	r.drive = Integrator.new(r.drive_inertia_base, 0.0001)
	r.drift_amount = 0.0 -- bipolar; positive is linear, negative is exponential
	r.rate = 0
	r.div = 1
	r.disposition = 0
	r.position = 0
	-- TODO: I don't think I like determining inertia based on proximity to lit LED after all;
	-- if rate is high, it's really hard to slow down by tapping lightly
	r.hold_points = {
		a = false,
		b = false,
		c = false,
		d = false
	}
	r.values = {
		a = 0,
		b = 0,
		c = 0,
		d = 0
	}
	return r
end

-- TODO: in 'vinyl mode', this shouldn't change drive directly, but add to it
-- ...which implies another exp/lin control like drift amount
function Rover:nudge(delta)
	self.drive:add(delta)
end

function Rover:step()
	self.noise:step((math.random() - 0.5))
	self.drift:step(self.noise.value)
	self.drive:step()
	self.rate = self.drift.value * math.max(0, self.drift_amount) + self.drive.value * math.pow(1 + math.max(0, -self.drift_amount), self.drift.value)
	self.disposition = (self.disposition + self.rate)
	self.position = (self.position + self.rate / self.div)
	self.values.a = math.cos(self.position - qpi) * 0.5 + 0.5
	self.values.b = math.sin(self.position - qpi) * 0.5 + 0.5
	self.values.c = 1 - self.values.a
	self.values.d = 1 - self.values.b

	local drive_inertia = self.drive_inertia_base
	for p, held in pairs(self.hold_points) do
		if held then
			drive_inertia = drive_inertia * (1 - self.values[p])
		end
	end
	self.drive.inertia = drive_inertia
end

return Rover