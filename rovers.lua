-- rovers

step_rate = 30

SugarCube = include 'lib/sugarcube'
Rover = include 'lib/rover'

rover_clock = nil

a = arc.connect()
g = grid.connect()

tau = math.pi * 2
seg_per_rad = 64 / tau
knob_max = tau / 3
knob_max_2x = knob_max * 2

log2 = math.log(2)

arc_values = { {}, {}, {}, {} }
rovers = {}
held_keys = {}
key_times = {}
local tape_length = tau + SugarCube.max_fade_time + 0.1
for r = 1, 4 do
	rovers[r] = Rover.new()
	rovers[r].on_point_cross = function(self, v)
		crow.ii.tt.script_v(r, v * 5)
	end
	rovers[r].cut.loop_start = (r - 1) * tape_length + 0.1
	rovers[r].cut.loop_end = (r - 1) * tape_length + 0.1 + tau
	held_keys[r] = {
		drive = false,
		pitch = false,
		drift_weight = false,
		drift_amount = false,
		map_a = false,
		map_b = false,
		fade = false,
		input_cut = { false, false, false, false },
		input = { false, false },
		level = false,
		pan = false,
		tilt = false,
		resonance = false
	}
	key_times[r] = {
		pitch = 0
	}
end

drive_sink = 0
drive_source = 0

screen_tau = 120
screen_offset = 0
screen_follow = 1
map_focus = false
map_cursor = 0
map_cursor_p = 1
screen_rover = 1

function update_cursor_p()
	local _, p = rovers[screen_rover].map:read(map_cursor)
	map_cursor_p = p
end

function has_held_key(r)
	local k = held_keys[r]
	if k.drive or k.pitch or k.drift_weight or k.drift_amount or k.map_a or k.map_b or k.fade or k.level or k.pan or k.tilt or k.resonance then
		return true
	end
	for v = 1, 4 do
		if k.input_cut[v] then
			return true
		end
	end
	for i = 1, 2 do
		if k.input[i] then
			return true
		end
	end
	return false
end

function led_blend(a, b)
	return 1 - ((1 - a) * (1 - b))
end

function led_blend_15(a, b)
	return util.clamp(math.floor(led_blend(a, b) * 15 + 0.5), 0, 15)
end

function a_blend(r, x, value)
	x = math.floor(x + 0.5) % 64 + 1
	arc_values[r][x] = led_blend(arc_values[r][x], value)
end

function a_notch(r, angle, width, level)
	local x = (angle * seg_per_rad) % 64
	if width == 1 then
		a_blend(r, x, level)
	else
		local w = width / 2
		local xl = x - w
		local xh = x + w
		local ll = 1 - (xl + 0.5 - math.floor(xl + 0.5))
		local lh = xh + 0.5 - math.floor(xh + 0.5)
		a_blend(r, xl, ll * level)
		a_blend(r, xh, lh * level)
		for x = math.floor(xl + 1.5), math.floor(xh - 0.5) do
			a_blend(r, x, level)
		end
	end
end

function a_spiral(r, start, length, level, finish_level)
	local finish = math.floor((start + length) * seg_per_rad + 0.5)
	start = math.floor(start * seg_per_rad + 0.5)
	local increment = finish < start and -1 or 1
	for x = start, finish, increment do
		a_blend(r, x, x == finish and finish_level or level)
	end
end

function a_bipolar(r, value)
	a_spiral(r, 0, value * knob_max, 0.2, 0.7)
	if value > 1 then
		a_notch(r, knob_max, 1, 0.7)
	elseif value < -1 then
		a_notch(r, -knob_max, 1, 0.7)
	end
end

function a_unipolar(r, value)
	a_spiral(r, -knob_max, value * knob_max_2x, 0.2, 0.7)
	if value > 1 then
		a_notch(r, knob_max, 1, 0.7)
	end
end

function a_refresh()
	for r = 1, 4 do
		for x = 1, 64 do
			a:led(r, x, math.min(15, math.floor(arc_values[r][x] * 15 + 0.5)))
		end
	end
	a:refresh()
end

function a_all(r, value)
	for x = 1, 64 do
		arc_values[r][x] = value
	end
end

function tick()
	g:all(0)
	
	if drive_sink > 0 and drive_source > 0 then
		local sink = rovers[drive_sink]
		local source = rovers[drive_source]
		local sink_drive = sink.drive.value * sink.pitch_ratio
		local source_drive = source.rate
		local diff = source_drive - sink_drive
		if diff < 0.01 then
			sink.drive.value = source_drive / sink.pitch_ratio
		else
			sink.drive.value = (sink_drive + diff * 0.05) / sink.pitch_ratio
		end
	end

	for r = 1, 4 do

		local held_keys = held_keys[r]
		local rover = rovers[r]
		local cut = rover.cut

		rover:step()

		if r == screen_rover and screen_follow > 0.5 then
			screen_offset = -rover.position + math.pi
		end

		crow.output[r].volts = rover.values.d * 5

		if held_keys.drive or (held_keys.fade and rover.cut_grains) or not has_held_key(r) then
			a_all(r, rover.point_highlight.value * rover.point_highlight.value * 0.3)
			a_notch(r, rover.highlight_point.i, 1.5, rover.point_highlight.value)
			if rover.cut_grains then
				a_notch(r, rover.position, rover.cut.fade_time_scaled * 2 * seg_per_rad, 0.5)
				a_notch(r, rover.grain_position, 1.5, math.min(1, seg_per_rad * (rover.grain_position - rover.fade_position)))
				a_notch(r, rover.grain_position + rover.cut.fade_time_scaled, 1.5, math.min(1, seg_per_rad * (rover.position - rover.grain_position)))
			else
				a_notch(r, rover.position, 2, 1)
				-- TODO: draw another notch if tape length is something other than 2pi
			end
		else
			a_all(r, 0)
			a_notch(r, rover.position, 1.5, 0.3)
		end

		if held_keys.drift_amount then
			a_bipolar(r, rover.drift_amount)
		end

		if held_keys.drift_weight then
			-- a_spiral(r, -knob_max, knob_max, 0.15, 0.1) -- TODO
			a_unipolar(r, rover.drift_weight)
		end
		
		if held_keys.pitch then
			a_spiral(r, 0, rover.pitch * knob_max, 0.2, 0.7)
			if rover.pitch_ratio >= 1 then
				for h = 2, math.floor(rover.pitch_ratio) do
					a_notch(r, knob_max * math.log(h) / log2, 1, 0.7)
				end
			else
				for h = 2, math.floor(1 / rover.pitch_ratio) do
					a_notch(r, -knob_max * math.log(h) / log2, 1, 0.7)
				end
			end
		end

		if held_keys.fade and not rover.cut_grains then
			a_unipolar(r, rover.cut.fade_time)
		end

		for v = 1, 4 do
			if held_keys.input_cut[v] then
				if v == r then
					a_unipolar(r, cut.dub_level)
				else
					a_unipolar(r, rovers[v].cut.sends[r])
				end
			end
		end

		for i = 1, 2 do
			if held_keys.input[i] then
				a_unipolar(r, cut.inputs[i])
			end
		end

		if held_keys.level then
			a_unipolar(r, cut.level)
		end

		if held_keys.pan then
			a_bipolar(r, cut.pan)
		end
			
		if held_keys.tilt then
			a_bipolar(r, cut.tilt)
		end

		if held_keys.resonance then
			-- TODO
		end
		
		local gx = (r - 1) * 4 + 1

		local hold_level = (5 - rover.hold) / 10
		g:led(gx + 1, 1, led_blend_15(((rover.values.a + 1) * hold_level) ^ 2, 0.09))
		g:led(gx + 1, 2, led_blend_15(((rover.values.b + 1) * hold_level) ^ 2, 0.09))
		g:led(gx, 2, led_blend_15(((rover.values.c + 1) * hold_level) ^ 2, 0.09))
		g:led(gx, 1, led_blend_15(((rover.values.d + 1) * hold_level) ^ 2, 0.09))

		if drive_sink == r or drive_source == r then
			g:led(gx + 2, 1, 10)
		else
			g:led(gx + 2, 1, held_keys.drive and 10 or 2)
		end
		if held_keys.pitch then
			g:led(gx + 2, 2, 10)
			g:led(gx + 3, 2, rover.pitch_harmonic and 7 or 2)
		else
			g:led(gx + 2, 2, 2)
		end

		local noise_level = rover.noise.value * rover.drift_amount
		local drift_level = rover.drift.value * rover.drift_amount
		g:led(gx, 3, led_blend_15(noise_level ^ 2, 0.15))
		g:led(gx + 1, 3, led_blend_15(drift_level ^ 2, 0.15))

		g:led(gx + 2, 3, rover.cut_grains and 4 or 2)

		local map_level = rover.values.p ^ 2 * (rover.values.p < 0 and -1 or 1)
		local map_base = (rover.point_highlight.value * 0.4 + 0.3) ^ 2
		g:led(gx + 1, 4, led_blend_15(math.max(0, map_level), map_base))
		g:led(gx, 4, led_blend_15(math.max(0, -map_level), map_base))

		g:led(gx + 2, 4, held_keys.fade and 10 or 2)

		local cut = rover.cut
		for v = 1, 4 do
			if v == r then
				g:led(gx + v - 1, 6, math.floor(cut.dub_level ^ 2 * 4 + 0.5))
			else
				g:led(gx + v - 1, 6, math.floor(rovers[v].cut.sends[r] ^ 2 * 4 + 0.5))
			end
		end
		g:led(gx, 7, (cut.state == cut.state_PLAY or cut.state == cut.state_OVERDUB) and 6 or 2)
		g:led(gx + 1, 7, (cut.state == cut.state_RECORD or cut.state == cut.state_OVERDUB) and 6 or 2)
		for i = 1, 2 do
			g:led(gx + i + 1, 7, math.floor(cut.inputs[i] ^ 2 * 4 + 0.5))
		end
		g:led(gx, 8, math.floor(cut.level ^ 2 * 4 + 0.5))
		g:led(gx + 1, 8, math.floor(cut.pan ^ 2 * 4 + 0.5))
		g:led(gx + 2, 8, math.floor(cut.tilt ^ 2 * 4 + 0.5))
	end
	a_refresh()
	g:refresh()
	redraw()
end

arc_time = {}
for r = 1, 4 do
	arc_time[r] = util.time()
end

function a.delta(r, d)

	local rover = rovers[r]
	local held_keys = held_keys[r]
	local d_bipolar = d / 384
	local d_unipolar = d / 768

	if not has_held_key(r) then
		rover.touch:add(d * math.pi / 512)
		return
	end

	if held_keys.drive then
		-- acceleration logic ripped from norns/lua/core/encoders.lua
		-- TODO: tune acceleration response
		local now = util.time()
		local diff = now - arc_time[r]
		arc_time[r] = now
		if diff < 0.005 then
			d = d*6
		elseif diff < 0.01 then
			d = d*4
		elseif diff < 0.02 then
			d = d*3
		elseif diff < 0.03 then
			d = d*2
		end
		rover.drive:add(d)
		return
	end

	local cut = rover.cut

	if held_keys.drift_amount then
		rover.drift_amount = rover.drift_amount + d_bipolar
	end

	if held_keys.drift_weight then
		rover.drift_weight = util.clamp(rover.drift_weight + d_unipolar, 0, 0.99)
		rover.noise:set_weight(rover.drift_weight)
		rover.drift:set_weight(rover.drift_weight)
	end

	if held_keys.pitch then
		rover:pitch_delta(d_bipolar)
	end

	if held_keys.fade then
		-- TODO: scale exponentially (probably need to use a param)
		cut.fade_time = util.clamp(cut.fade_time + d * 0.001, 0.001, 1)
	end

	for v = 1, 4 do
		if held_keys.input_cut[v] then
			if v == r then
				cut.dub_level = util.clamp(cut.dub_level + d_unipolar, 0, 1.2)
			else
				rovers[v].cut.sends[r] = util.clamp(rovers[v].cut.sends[r] + d_unipolar, 0, 1.2)
			end
		end
	end

	for i = 1, 2 do
		if held_keys.input[i] then
			cut.inputs[i] = util.clamp(cut.inputs[i] + d_unipolar, 0, 1.2)
		end
	end

	if held_keys.level then
		cut.level = util.clamp(cut.level + d_unipolar, 0, 1.2)
	end

	if held_keys.pan then
		cut.pan = util.clamp(cut.pan + d_bipolar, -1, 1)
	end

	if held_keys.tilt then
		cut.tilt = util.clamp(cut.tilt + d_bipolar, -1, 1)
	end

	if held_keys.resonance then
		-- TODO
	end
end

function g.key(x, y, z)
	local r = math.floor((x - 1) / 4) + 1
	local rover = rovers[r]
	local held_keys = held_keys[r]
	local key_times = key_times[r]
	local x = (x - 1) % 4 + 1
	if y == 1 or y == 2 then
		if x == 1 or x == 2 then
			rover.hold = rover.hold + (z == 1 and 1 or -1)
		elseif y == 1 and x == 3 then
			if z == 1 then
				held_keys.drive = true
				if drive_sink > 0 then
					drive_source = r
				else
					drive_sink = r
				end
			else
				held_keys.drive = false
				if drive_sink == r then
					drive_sink = drive_source
					drive_source = 0
				elseif drive_source == r then
					drive_source = 0
				end
			end
		elseif y == 2 and x == 3 then
			held_keys.pitch = z == 1
			if z == 1 then
				if held_keys.drive then
					rover:rebase_pitch()
				end
				local now = util.time()
				if rover.cut_grains and now - key_times.pitch < 0.2 then
					rover.grain_reverse = not rover.grain_reverse
				end
				key_times.pitch = now
			end
		elseif y == 2 and x == 4 then
			if held_keys.pitch and z == 1 then
				rover.pitch_harmonic = not rover.pitch_harmonic
				rover:pitch_delta(0)
			end
		end
	elseif y == 3 then
		if x == 1 then
			held_keys.drift_weight = z == 1
		elseif x == 2 then
			held_keys.drift_amount = z == 1
		elseif x == 3 and z == 1 then
			rover:toggle_grains()
		end
	elseif y == 4 then
		if x == 1 then
			held_keys.map_a = z == 1
		elseif x == 2 then
			held_keys.map_b = z == 1
		elseif x == 3 then
			held_keys.fade = z == 1
		end
		if (x == 1 or x == 2) and held_keys.map_a and held_keys.map_b then
			rover.map:insert(rover.position)
			map_cursor = rover.position
			update_cursor_p()
		end
	elseif y == 6 then
		held_keys.input_cut[x] = z == 1
	elseif y == 7 then
		local cut = rover.cut
		if y == 7 then
			if x == 1 and z == 1 then
				if cut.state == cut.state_RECORD then
					cut:overdub()
				elseif cut.state == cut.state_PLAY then
					cut:mute()
				elseif cut.state == cut.state_OVERDUB then
					cut:record()
				else
					cut:play()
				end
			elseif x == 2 and z == 1 then
				if cut.state == cut.state_PLAY then
					cut:overdub()
				elseif cut.state == cut.state_RECORD then
					cut:mute()
				elseif cut.state == cut.state_OVERDUB then
					cut:play()
				else
					cut:record()
				end
			elseif x == 3 then
				held_keys.input[1] = z == 1
			elseif x == 4 then
				held_keys.input[2] = z == 1
			end
		end
	elseif y == 8 then
		if x == 1 then
			held_keys.level = z == 1
		elseif x == 2 then
			held_keys.pan = z == 1
		elseif x == 3 then
			held_keys.tilt = z == 1
		elseif x == 4 then
			held_keys.resonance = z == 1
		end
	end
	screen_rover = r
	update_cursor_p()
end

function init()

	crow.clear()
	for o = 1, 4 do
		crow.output[o].slew = 1 / step_rate
	end

	rover_clock = metro.init{
		time = 1 / step_rate,
		event = tick
	}

	for r = 1, 4 do
		rovers[r].cut:init()
		rovers[r].cut:mute()
	end
	softcut.poll_start_phase()

	update_cursor_p()

	--[[
	params:add{
		id = 'touch_type',
		name = 'touch control',
		type = 'option',
		labels = {
			'position',
			'rate'
		},
		action = function(value)
			-- TODO!
		end
	}

	params:add{
		id = 'touch_weight',
		name = 'touch weight',
		type = 'control',
		controlspec = controlspec.new(0, 0.9999, 'lin', 0.001, 0.6),
		action = function(value)
			-- TODO
		end
	}

	params:add{
		id = 'touch_type',
		name = 'touch control',
		type = 'option',
		labels = {
			'direct',
			'rate'
		},
		action = function(value)
			-- TODO!
		end
	}
	-- TODO: in 'direct' mode, you can sync all four
	-- -- use a sync toggle, slew up/down to synced rate
	--]]

	--[[
	TODO: possible output types:
	- crow CV rate
	- crow CV pos (a, b, c, d)
	- crow CV map value (p)
	- ...additional, multi-dimensional map values?
	- TT events
	- MIDI events: notes, chords
	- crow triggers
	- softcut loops!!

	TODO: 'recorder' modes:
	- softcut, duh
	- MIDI recorder
	- CV recorder
	]]

	rover_clock:start()
end

function key(k, z)
	local rover = rovers[screen_rover]
	if k == 1 then
		-- TODO
	elseif k == 2 then
		map_focus = z == 1
		if map_focus then
			map_cursor = rover.map.points[map_cursor_p].i
		end
	elseif k == 3 then
		if z == 1 then
			if map_focus then
				rover.map:delete(map_cursor)
			else
				rover.map:insert(map_cursor)
			end
			update_cursor_p()
			map_cursor = rover.map.points[map_cursor_p].i
		end
	end
end

function enc(e, d)
	local rover = rovers[screen_rover]
	if e == 1 then
		screen_follow = util.clamp(screen_follow + d * 0.1, 0, 1)
		if d > 0 and screen_follow > 0.5 then
			screen_follow = 1
		elseif d < 0 and screen_follow <= 0.5 then
			screen_follow = 0
		end
	elseif e == 2 then
		if map_focus then
			local point = rover.map.points[map_cursor_p]
			rover.map:move(map_cursor_p, d * 0.03)
			map_cursor = point.i
		else
			map_cursor = (map_cursor + d * 0.03) % tau
		end
		update_cursor_p()
	elseif e == 3 then
		local point = rover.map.points[map_cursor_p]
		if map_focus then
			map_cursor = point.i
			point.o = util.clamp(point.o + d * 0.01, -1, 1)
		else
			point.t = util.clamp(point.t + d * 0.02, 0, 1)
		end
	end
end

function get_point_x(i)
	return (i + screen_offset) * screen_tau / tau
end

function get_point_y(o)
	return 31.5 - o * 31
end

function redraw()
	local rover = rovers[screen_rover]
	local map = rover.map
	local points = map.points
	local count = map.count

	screen.clear()

	screen.aa(0)
	screen.level(1)
	screen.line_width(1)

	-- y axis
	screen.move(0.5, 0)
	screen.line(0.5, 64)
	screen.stroke()
	screen.pixel(1, 0)
	screen.pixel(1, 31)
	screen.pixel(1, 63)
	screen.fill()

	-- cursor
	local cursor_point = points[map_cursor_p]
	local x = get_point_x(map_cursor)
	local y = get_point_y(cursor_point.o)
	for offset = -1, 1 do
		local xo = x + screen_tau * offset
		if xo >= 0 and xo <= 128 then
			if map_focus then
				screen.rect(xo - 5, y - 5, 10, 10)
				screen.stroke()
			else
				screen.move(xo, 0)
				screen.line(xo, 64)
				screen.stroke()
			end
		end
	end

	x = get_point_x(rover.highlight_point.i) % screen_tau
	y = get_point_y(rover.highlight_point.o)
	local r = 5 / rover.point_highlight.value
	local l = rover.point_highlight.value ^ 3 * 15
	if l > 1 then
		screen.circle(x, y, r)
		screen.level(math.floor(l))
		screen.aa(0)
		screen.stroke()
	end

	screen.aa(1)

	for p = -count, count * 2 + 1 do
		local point = points[(p - 1) % count + 1]
		x = get_point_x(point.i) + screen_tau * math.floor((p - 1) / count)
		y = get_point_y(point.o)
		if p == -count then
			screen.move(x, y)
		else
			screen.line(x, y)
		end
	end
	screen.level(2)
	screen.line_width(1.1)
	screen.stroke()

	screen.aa(0)

	for p = 1 - count, count * 2 do
		local point = points[(p - 1) % count + 1]
		if p ~= map_cursor_p and point.t > 0 then
			x = get_point_x(point.i) + screen_tau * math.floor((p - 1) / count)
			y = get_point_y(point.o)
			screen.rect(x - 2.5, y - 2.5, 5, 5)
			screen.level(0)
			screen.fill()
			screen.rect(x - 0.5, y - 0.5, 1, 1)
			screen.level(math.ceil(point.t * 15))
			screen.fill()
		end
	end

	local o, p = map:read(rover.position)
	y = get_point_y(o)
	for offset = -1, 1 do
		x = get_point_x(rover.position) + screen_tau * offset
		screen.rect(x - 0.5, y - 0.5, 1, 1)
		screen.level(15)
		screen.fill()
	end

	y = get_point_y(cursor_point.o)
	for offset = -1, 1 do
		x = get_point_x(cursor_point.i) + screen_tau * offset
		screen.rect(x - 2.5, y - 2.5, 5, 5)
		screen.level(0)
		screen.fill()
		screen.rect(x - 1.5, y - 1.5, 3, 3)
		screen.level(map_focus and 15 or 4)
		screen.fill()
		screen.rect(x - 0.5, y - 0.5, 1, 1)
		screen.level(math.ceil(cursor_point.t * 15))
		screen.fill()
	end

	screen.update()
end

function cleanup()
	if rover_clock ~= nil then
		rover_clock:stop()
	end
	softcut.poll_stop_phase()
end