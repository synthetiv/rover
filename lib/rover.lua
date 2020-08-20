local Map = include 'lib/map'
local SugarCube = include 'lib/sugarcube'

local tau = math.pi * 2
local qpi = math.pi / 4
local log2 = math.log(2)

local max_softcut_rate = 24
local max_softcut_pitch = math.log(max_softcut_rate) / log2

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

function Integrator:damp(d)
	self.value = self.value * self.inertia * d
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
		self.sensitivity = logw / (math.pow(w, step_rate) - w + logw)
	end
end

local Disintegrator = {}
Disintegrator.__index = Disintegrator

function Disintegrator.new()
	local d = setmetatable({}, Disintegrator)
	d.input = 0
	d.rate = 0
	d.value = 0
	d.weight = 0.8
	d.integrator = Integrator.new(d.weight)
	return d
end

function Disintegrator:add(v)
	self.input = self.input + v
end

function Disintegrator:step(v)
	if v ~= nil then
		self:add(v)
	end
	self.rate = self.input - self.rate * self.rate * self.rate * self.weight
	self.input = 0
	self.integrator:step(self.rate)
	self.value = self.integrator.value
end

function Disintegrator:set_weight(w)
	self.weight = w
	self.integrator:set_weight(w)
end

local Rover = {}
Rover.__index = Rover

function Rover.new()
	local r = setmetatable({}, Rover)
	r.drift_amount = -0.15 -- bipolar; positive is linear, negative is exponential
	r.drift_weight = 0.8
	r.noise = Integrator.new(r.drift_weight)
	r.drift = Integrator.new(r.drift_weight)
	r.drive = Integrator.new(1, 0.0001)
	r.touch = Disintegrator.new()
	r.rate = 0
	r.pitch = 0
	r.pitch_ratio = 1
	r.pitch_base = 1
	r.pitch_harmonic = true
	r.position = 0
	r.last_position = 0
	r.map = Map.new()
	r.p = 1
	r.point_highlight = Integrator.new(0.9, 1)
	r.highlight_point = r.map.points[1]
	r.cut = SugarCube.new()
	r.cut_grains = false
	r.fade_position = r.position - r.cut.fade_time / 2
	r.grain_position = r.fade_position
	r.grain_reverse = false
	r.cut.rate_slew_time = 15 / step_rate -- 15-step slew time is arbitrary, but seems to sound fine
	-- TODO: handle jumps around 0.0 which must (?) be caused by loop point fades
	r.cut.on_poll = function(self)
		if not r.cut_grains then
			r.position = self.position
		else
			r.grain_position = self.position
		end
	end
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

function Rover:step()
	if self.hold > 0 then
		local damp
		if self.hold == 4 then
			damp = 0.1
		elseif self.hold == 3 then
			damp = 0.5
		elseif self.hold == 2 then
			damp = 0.8
		elseif self.hold == 1 then
			damp = 0.95
		end
		self.noise:damp(damp)
		self.drift:damp(damp)
		self.drive:damp(damp)
	else
		self.noise:step(math.random() - 0.5)
		self.drift:step(self.noise.value)
		self.drive:step()
	end
	self.touch:step()
	self.point_highlight:step()

	local drift_cubed = self.drift_amount * self.drift_amount * self.drift_amount
	local pitch_drift = math.pow(2, self.drift.value * math.max(0, -drift_cubed))
	local position_drift = self.drift.value * math.max(0, drift_cubed)

	local pitch_ratio = self.pitch_ratio * self.pitch_base * pitch_drift

	self.rate = self.drive.value + self.touch.value + position_drift

	if self.cut_grains then
		local fade_time = self.cut.fade_time_scaled
		local cut_rate = util.clamp(pitch_ratio, -max_softcut_rate, max_softcut_rate)
		cut_rate = cut_rate * (self.grain_reverse and -1 or 1)
		self.position = (self.position + self.rate) % tau
		self.cut.rate = cut_rate
		self.fade_position = (self.position - fade_time) % tau
		self.cut.position = self.fade_position + self.cut.loop_start
		-- wrap the grain position to the first half of the fade region; we'll draw two grains on the arc
		-- if we don't wrap here and the fade region doesn't cross a SC phase quant, grain_position doesn't get reported by softcut and grains may appear to fly out of the fade region
		if fade_time == 0 then
			self.grain_position = self.fade_position
		else
			self.grain_position = (self.grain_position + cut_rate / step_rate - self.fade_position) % fade_time + self.fade_position
		end
	else
		local max_rate = max_softcut_rate / (pitch_ratio * step_rate)
		self.rate = util.clamp(self.rate, -max_rate, max_rate)
		-- TODO: is there a better (less potentially jitter-prone) way to interpolate between positions reported by softcut?
		-- well, you'd want to start by slewing the displayed rate (but NOT the rate sent to SC) based on SC rate slew time, so they matched
		self.position = (self.position + self.rate * pitch_ratio) % tau
		self.cut.rate = self.rate * pitch_ratio * step_rate
	end

	self.values.a = math.cos(self.position - qpi)
	self.values.b = math.sin(self.position - qpi)
	self.values.c = -self.values.a
	self.values.d = -self.values.b

	-- TODO: does this need to be handled differently in grain mode, for better correlation between audio and map?
	self.values.p, self.p = self.map:read(self.position)
	local point = self.map.points[self.p]
	if point.t > 0 then

		-- check for zero crossings
		-- this will alias/break if self.rate > math.pi, but like... that'd be really fast
		local distance = self.position - self.last_position
		if distance > math.pi then
			distance = distance - tau
		elseif distance < -math.pi then
			distance = distance + tau
		end

		if (self.position >= point.i and self.position - distance < point.i)
		or (self.position >= point.i - tau and self.position - distance < point.i - tau)
		or (self.position <= point.i and self.position - distance > point.i)
		or (self.position <= point.i + tau and self.position - distance > point.i + tau)
		then
			if point.t > math.random() then
				self.point_highlight.value = 1
				self.highlight_point = point
				self:on_point_cross(point.o)
			end
		end
	end

	self.last_position = self.position
end

function Rover:pitch_delta(d)
	local pitch = self.pitch + d
	local ratio = math.pow(2, pitch)
	if self.pitch_harmonic then
		if ratio > 1 then
			ratio = math.floor(ratio)
		else
			ratio = 1 / math.floor(1 / ratio)
		end
	end
	if self.cut_grains then
		if ratio > max_softcut_rate then
			ratio = max_softcut_rate
			pitch = max_softcut_pitch
		end
	else
		local max_ratio = math.abs(24 / (self.rate * step_rate))
		if self.pitch_harmonic then
			if max_ratio > 1 then
				max_ratio = math.floor(max_ratio)
			else
				max_ratio = 1 / math.floor(1 / ratio)
			end
		end
		if ratio > max_ratio then
			ratio = max_ratio
			pitch = math.log(ratio) / log2
		end
	end
	self.pitch = pitch
	self.pitch_ratio = ratio
end

function Rover:rebase_pitch()
	if self.cut_grains then
		self.pitch_base = self.pitch_ratio * self.pitch_base
		self.pitch = 0
		self.pitch_ratio = 1
	else
		self.drive.value = self.drive.value * self.pitch_ratio
		self.pitch = 0
		self.pitch_ratio = 1
	end
end

function Rover:toggle_grains()
	local pitch_ratio = self.pitch_ratio * self.pitch_base
	if self.cut_grains then
		self.drive.value = pitch_ratio / step_rate * (self.grain_reverse and -1 or 1)
		self.pitch_base = 1
		self.pitch = 0
		self.pitch_ratio = 1
		self.cut_grains = false
	else
		local reverse = false
		local current_pitch = self.drive.value
		if current_pitch < 0 then
			reverse = true
			current_pitch = -current_pitch
		end
		-- if we're currently stopped, start at a pitch of 1, not 0
		if current_pitch < 0.001 / step_rate then
			current_pitch = 1 / step_rate
		end
		self.drive.value = self.drive.value * pitch_ratio
		self.pitch_base = current_pitch * step_rate
		self.pitch = 0
		self.pitch_ratio = 1
		self.cut_grains = true
	end
end

function Rover:on_point_cross() end

return Rover