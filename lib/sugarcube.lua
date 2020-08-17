local sc = softcut

local cubes = {}
local v = 1

local function event_phase(voice, phase)
	local cube = cubes[voice]
	if cube ~= nil then
		-- bypass setter
		cube.params.position = phase % (cube.loop_end - cube.loop_start)
		cube:on_poll()
	end
end

local Levels = {}
Levels.__index = Levels

function Levels.new(cube, count, default, callback)
	local i = {
		cube = cube,
		callback = callback
	}
	local values = {}
	for l = 1, count do
		values[l] = default
	end
	i.values = values
	return setmetatable(i, {
		__index = setmetatable(values, Levels),
		__newindex = Levels.__newindex
	})
end

function Levels:__newindex(index, value)
	self.values[index] = value
	self.callback(index, value)
end

local SugarCube = {}
SugarCube.__index = SugarCube

local state_STOP = 0
local state_MUTE = 1
local state_PLAY = 2
local state_RECORD = 3
local state_OVERDUB = 4
SugarCube.state_STOP = state_STOP
SugarCube.state_MUTE = state_MUTE
SugarCube.state_PLAY = state_PLAY
SugarCube.state_RECORD = state_RECORD
SugarCube.state_OVERDUB = state_OVERDUB

function SugarCube.new(buffer)

	if v > sc.VOICE_COUNT then
		error('too many voices')
	end

	local params = {
		loop_start = 1,
		loop_end = 4,
		position = 1,
		rec_level = 1,
		dub_level = util.dbamp(-1),
		level = 1,
		pan = 0,
		fade_time = 0.01,
		rate_slew_time = 0.01,
		rate = 0
	}

	local cube = {
		voice = v,
		buffer = buffer or 1,
		state = state_STOP,
		params = params,
		on_poll = norns.none
	}

	cube.inputs = Levels.new(cube, 2, 1, function(input, value)
		sc.level_input_cut(input, cube.voice, value)
	end)

	cube.sends = Levels.new(cube, 6, 0, function(v2, value)
		sc.level_cut_cut(cube.voice, v2, value * cube.level)
	end)

	setmetatable(cube, {
		__index = setmetatable(params, SugarCube),
		__newindex = SugarCube.__newindex
	})

	cubes[v] = cube
	v = v + 1

	return cube
end

function SugarCube:init()
	local v = self.voice
	local quant = tau / 64
	sc.event_phase(event_phase)
	sc.enable(v, 1)
	sc.buffer(v, self.buffer)
	sc.pan(v, 0)
	sc.pan_slew_time(v, self.params.fade_time)
	sc.level_slew_time(v, self.params.fade_time)
	sc.rate_slew_time(v, self.params.rate_slew_time)
	sc.recpre_slew_time(v, self.params.fade_time)
	sc.rate(v, 0)
	sc.level(v, 0)
	sc.level_input_cut(1, v, self.inputs[1] and 1 or 0)
	sc.level_input_cut(2, v, self.inputs[2] and 1 or 0)
	sc.fade_time(v, self.params.fade_time)
	sc.loop_start(v, self.params.loop_start)
	sc.loop_end(v, self.params.loop_end)
	sc.position(v, self.params.loop_start)
	sc.loop(v, 1)
	sc.phase_quant(v, quant) -- TODO
	sc.phase_offset(v, -self.params.loop_start)
	sc.rec(v, 1)
	sc.play(v, 1)
	sc.pre_filter_dry(v, 1);
	sc.pre_filter_fc(v, 20);
	sc.pre_filter_rq(v, 1.5);
	sc.pre_filter_lp(v, 0);
	sc.pre_filter_hp(v, 0);
	sc.pre_filter_bp(v, 0);
	sc.pre_filter_br(v, 0);
	sc.post_filter_dry(v, 0);
	sc.post_filter_fc(v, 20000);
	sc.post_filter_rq(v, 1);
	sc.post_filter_lp(v, 1);
	sc.post_filter_hp(v, 0);
	sc.post_filter_bp(v, 0);
	sc.post_filter_br(v, 0);
end

function SugarCube:stop()
	sc.rate(self.voice, 0)
	sc.rec_level(self.voice, 0)
	sc.pre_level(self.voice, 0)
	sc.level(self.voice, 0)
	for v = 1, 6 do
		sc.level_cut_cut(self.voice, v, 0)
	end
	self.state = state_STOP
end

function SugarCube:mute()
	sc.rate(self.voice, self.params.rate)
	sc.rec_level(self.voice, 0)
	sc.pre_level(self.voice, 1)
	sc.level(self.voice, 0)
	for v = 1, 6 do
		sc.level_cut_cut(self.voice, v, 0)
	end
	self.state = state_MUTE
end

function SugarCube:play()
	sc.rate(self.voice, self.params.rate)
	sc.rec_level(self.voice, 0)
	sc.pre_level(self.voice, 1)
	sc.level(self.voice, self.params.level)
	for v = 1, 6 do
		sc.level_cut_cut(self.voice, v, self.sends[v] * self.level)
	end
	self.state = state_PLAY
end

function SugarCube:record()
	sc.rate(self.voice, self.params.rate)
	sc.rec_level(self.voice, self.params.rec_level)
	sc.pre_level(self.voice, 0)
	sc.level(self.voice, 0)
	for v = 1, 6 do
		sc.level_cut_cut(self.voice, v, 0)
	end
	self.state = state_RECORD
end

function SugarCube:overdub()
	sc.rate(self.voice, self.params.rate)
	sc.rec_level(self.voice, self.params.rec_level)
	sc.pre_level(self.voice, self.params.dub_level)
	sc.level(self.voice, self.params.level)
	for v = 1, 6 do
		sc.level_cut_cut(self.voice, v, self.sends[v] * self.level)
	end
	self.state = state_OVERDUB
end

function SugarCube:__newindex(index, value)
	self.params[index] = value
	-- TODO: these aren't really 'setters'... 'handlers'?
	if self.setters[index] ~= nil then
		self.setters[index](self, value)
	end
end

SugarCube.setters = {}

function SugarCube.setters:loop_start(value)
	if self.rate >= 0 then
		sc.loop_start(self.voice, value)
	else
		sc.loop_start(self.voice, value + self.fade_time)
	end
	sc.phase_offset(v, -value)
end

function SugarCube.setters:loop_end(value)
	if self.rate >= 0 then
		sc.loop_end(self.voice, value)
	else
		sc.loop_end(self.voice, value + self.fade_time)
	end
end

function SugarCube.setters:position(value)
	sc.position(self.voice, value)
end

function SugarCube.setters:rec_level(value)
	if self.state == state_RECORD then
		sc.rec_level(self.voice, value)
	end
end

function SugarCube.setters:dub_level(value)
	if self.state == state_OVERDUB then
		sc.pre_level(self.voice, value)
	end
end

function SugarCube.setters:level(value)
	if self.state == state_PLAY or self.state == state_OVERDUB then
		sc.level(self.voice, value)
	end
	for v = 1, 6 do
		sc.level_cut_cut(self.voice, v, self.sends[v] * value)
	end
end

function SugarCube.setters:pan(value)
	sc.pan(self.voice, value)
end

function SugarCube.setters:fade_time(value)
	sc.fade_time(self.voice, value)
	sc.pan_slew_time(self.voice, value)
	sc.level_slew_time(self.voice, value)
	sc.recpre_slew_time(self.voice, value)
	if self.rate < 0 then
		sc.loop_start(self.voice, self.loop_start + value)
		sc.loop_end(self.voice, self.loop_end + value)
	end
end

function SugarCube.setters:rate_slew_time(value)
	sc.rate_slew_time(self.voice, value)
end

function SugarCube.setters:rate(value)
	-- TODO: prevent crashes: keep this from going too high, whatever that is
	-- TODO: only do this when rate has crossed 0
	if value >= 0 then
		sc.loop_start(self.voice, self.loop_start)
		sc.loop_end(self.voice, self.loop_end)
	else
		sc.loop_start(self.voice, self.loop_start + self.fade_time)
		sc.loop_end(self.voice, self.loop_end + self.fade_time)
	end
	if self.state ~= state_STOP then
		sc.rate(self.voice, value)
	end
end

return SugarCube