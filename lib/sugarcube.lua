local sc = softcut

local cubes = {}
local v = 1

local function event_phase(voice, phase)
	if cubes[voice] ~= nil then
		cubes[voice]._position = phase % (cubes[voice]._loop_end - cubes[voice]._loop_start)
		cubes[voice]:on_poll()
	end
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

	local c = {
		voice = v,
		buffer = buffer or 1,
		state = state_STOP,
		_loop_start = 1,
		_loop_end = 4,
		_position = 1,
		_rec_level = 1,
		_dub_level = util.dbamp(-1),
		_play_level = 1,
		_fade_time = 0.01,
		_rate_slew_time = 0.01,
		_rate = 0,
		on_poll = norns.none
	}
	setmetatable(c, SugarCube)

	cubes[v] = c
	v = v + 1

	return c
end

function SugarCube:init()
	local v = self.voice
	local quant = tau / 64
	sc.event_phase(event_phase)
	sc.enable(v, 1)
	sc.buffer(v, self.buffer)
	sc.pan(v, 0)
	sc.pan_slew_time(v, self._fade_time)
	sc.level_slew_time(v, self._fade_time)
	sc.rate_slew_time(v, self._rate_slew_time)
	sc.recpre_slew_time(v, self._fade_time)
	sc.rate(v, 0)
	sc.level(v, 0)
	sc.level_input_cut(1, v, 1)
	sc.level_input_cut(2, v, 1)
	sc.fade_time(v, self._fade_time)
	sc.loop_start(v, self._loop_start)
	sc.loop_end(v, self._loop_end)
	sc.position(v, self._loop_start)
	sc.loop(v, 1)
	sc.phase_quant(v, quant) -- TODO
	sc.phase_offset(v, -self._loop_start)
	sc.rec(v, 1)
	sc.play(v, 1)
	sc.filter_dry(v, 1);
	sc.filter_fc(v, 0);
	sc.filter_lp(v, 0);
	sc.filter_bp(v, 0);
	sc.filter_rq(v, 0);
end

function SugarCube:stop()
	sc.rate(self.voice, 0)
	sc.rec_level(self.voice, 0)
	sc.pre_level(self.voice, 0)
	sc.level(self.voice, 0)
	self.state = state_STOP
end

function SugarCube:mute()
	sc.rate(self.voice, self._rate)
	sc.rec_level(self.voice, 0)
	sc.pre_level(self.voice, 1)
	sc.level(self.voice, 0)
	self.state = state_MUTE
end

function SugarCube:play()
	sc.rate(self.voice, self._rate)
	sc.rec_level(self.voice, 0)
	sc.pre_level(self.voice, 1)
	sc.level(self.voice, self._play_level)
	self.state = state_PLAY
end

function SugarCube:record()
	sc.rate(self.voice, self._rate)
	sc.rec_level(self.voice, self._rec_level)
	sc.pre_level(self.voice, 0)
	sc.level(self.voice, 0)
	self.state = state_RECORD
end

function SugarCube:overdub()
	sc.rate(self.voice, self._rate)
	sc.rec_level(self.voice, self._rec_level)
	sc.pre_level(self.voice, self._dub_level)
	sc.level(self.voice, self._play_level)
	self.state = state_OVERDUB
end

function SugarCube:__newindex(index, value)
	if index == 'loop_start' then
		self._loop_start = value
		if self._rate >= 0 then
			sc.loop_start(self.voice, value)
		else
			sc.loop_start(self.voice, value + self._fade_time)
		end
		sc.phase_offset(v, -value)
	elseif index == 'loop_end' then
		self._loop_end = value
		if self._rate >= 0 then
			sc.loop_end(self.voice, value)
		else
			sc.loop_end(self.voice, value + self._fade_time)
		end
	elseif index == 'rate' then
		self._rate = value
		-- TODO: only do this when rate has crossed 0
		if value >= 0 then
			sc.loop_start(self.voice, self._loop_start)
			sc.loop_end(self.voice, self._loop_end)
		else
			sc.loop_start(self.voice, self._loop_start + self._fade_time)
			sc.loop_end(self.voice, self._loop_end + self._fade_time)
		end
		if self.state ~= state_STOP then
			sc.rate(self.voice, value)
		end
	elseif index == 'rec_level' then
		self._rec_level = value
		if self.state == state_RECORD then
			sc.rec_level(self.voice, value)
		end
	elseif index == 'dub_level' then
		self._dub_level = value
		if self.state == state_OVERDUB then
			sc.pre_level(self.voice, value)
		end
	elseif index == 'rate_slew_time' then
		self._rate_slew_time = value
		sc.rate_slew_time(self.voice, value)
	end
end

return SugarCube