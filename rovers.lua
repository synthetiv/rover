-- rovers

step_rate = 30

Rover = include 'lib/rover'

rover_clock = nil

a = arc.connect()
g = grid.connect()

tau = math.pi * 2
seg_per_rad = 64 / tau
knob_max = math.pi * 3 / 4

arc_values = { {}, {}, {}, {} }
rovers = {}
held_keys = {}
for r = 1, 4 do
	rovers[r] = Rover.new()
	rovers[r].on_point_cross = function(self, v)
		crow.ii.tt.script_v(r, v * 5)
	end
	rovers[r].cut.loop_start = (r - 1) * 7 + 1
	rovers[r].cut.loop_end = (r - 1) * 7 + 1 + tau
	held_keys[r] = {
		div = false,
		drift_weight = false,
		drift_amount = false
	}
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

function a_spiral(r, start, finish, level, finish_level)
	start = math.floor(start * seg_per_rad + 0.5)
	finish = math.floor(finish * seg_per_rad + 0.5)
	local increment = finish < start and -1 or 1
	for x = start, finish, increment do
		a_blend(r, x, x == finish and finish_level or level)
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
	for r = 1, 4 do

		local held_keys = held_keys[r]
		local rover = rovers[r]
		rover:step()

		crow.output[r].volts = (rover.values.d - 0.5) * 5

		a_all(r, rover.point_highlight.value * rover.point_highlight.value * 0.3)

		if held_keys.drift_amount then
			a_spiral(r, 0, rover.drift_amount * knob_max, 0.2, 0.8)
		elseif held_keys.drift_weight then
			a_spiral(r, -knob_max, knob_max, 0.15, 0.1)
			a_spiral(r, -knob_max, (rover.drift_weight * 2 - 1) * knob_max, 0.05, 0.8)
		elseif held_keys.div then
			local div = params:get(string.format('rover_%d_div', r))
			div = math.floor(div + 0.5)
			local start = 0
			if div < 0 then
				div = -div
				start = math.pi
			end
			div = div + 1
			a_notch(r, start, 1, 1)
			for d = 1, div - 1 do
				a_notch(r, start + d * tau / div, 1, 0.5)
			end
			a_notch(r, rover.position, 2, 0.3)
		else
			a_notch(r, rover.position, 2, 1)
			if rover.div ~= 1 then
				a_notch(r, rover.disposition, 1.5, 0.3)
			end
			a_notch(r, rover.highlight_point.i, 1.5, rover.point_highlight.value)
		end

		local gx = (r - 1) * 4 + 1

		g:led(gx + 2, 1, held_keys.div and 10 or 2)

		local hold_level = 5 - rover.hold
		g:led(gx + 2, 2, math.floor(hold_level * rover.values.a * rover.values.a * 2 + 0.5))
		g:led(gx + 2, 3, math.floor(hold_level * rover.values.b * rover.values.b * 2 + 0.5))
		g:led(gx + 1, 3, math.floor(hold_level * rover.values.c * rover.values.c * 2 + 0.5))
		g:led(gx + 1, 2, math.floor(hold_level * rover.values.d * rover.values.d * 2 + 0.5))

		local drift_level = rover.drift.value * rover.drift_amount * 100
		g:led(gx + 2, 4, led_blend_15(math.max(0, drift_level * 0.1) ^ 2, 0.15))
		g:led(gx + 1, 4, led_blend_15(math.max(0, -drift_level * 0.1) ^ 2, 0.15))

		local cut = rover.cut
		g:led(gx, 7, (cut.state == cut.state_PLAY or cut.state == cut.state_OVERDUB) and 6 or 2)
		g:led(gx + 1, 7, (cut.state == cut.state_RECORD or cut.state == cut.state_OVERDUB) and 6 or 2)
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
	-- acceleration logic ripped from norns/lua/core/encoders.lua
	local now = util.time()
	local diff = now - arc_time[r]
	arc_time[r] = now
	local held_keys = held_keys[r]
	local rover = rovers[r]
	if held_keys.drift_amount then
		rover.drift_amount = rover.drift_amount + d / 384
	elseif held_keys.drift_weight then
		rover.drift_weight = util.clamp(rover.drift_weight + d / 768, 0, 0.99)
		rover.noise:set_weight(rover.drift_weight)
		rover.drift:set_weight(rover.drift_weight)
	elseif held_keys.div then
		-- TODO: set quant on controlspec
		params:delta(string.format('rover_%d_div', r), d * 0.06)
	else
		-- TODO: tune acceleration response
		if diff < 0.005 then
			d = d*6
		elseif diff < 0.01 then
			d = d*4
		elseif diff < 0.02 then
			d = d*3
		elseif diff < 0.03 then
			d = d*2
		end
		rover:nudge(d)
	end
	screen.ping()
end

function g.key(x, y, z)
	local r = math.floor((x - 1) / 4) + 1
	local rover = rovers[r]
	local held_keys = held_keys[r]
	local x = (x - 1) % 4 + 1
	if y == 1 then
		if x == 3 then
			held_keys.div = z == 1
		end
	elseif y == 2 or y == 3 then
		if x == 2 or x == 3 then
			rover.hold = rover.hold + (z == 1 and 1 or -1)
		end
	elseif y == 4 then
		if x == 2 then
			held_keys.drift_weight = z == 1
		elseif x == 3 then
			held_keys.drift_amount = z == 1
		end
	elseif y == 7 then
		if z == 1 then
			local cut = rover.cut
			if x == 1 then
				if cut.state == cut.state_RECORD then
					cut:overdub()
				elseif cut.state == cut.state_PLAY then
					cut:mute()
				elseif cut.state == cut.state_OVERDUB then
					cut:record()
				else
					cut:play()
				end
			elseif x == 2 then
				if cut.state == cut.state_PLAY then
					cut:overdub()
				elseif cut.state == cut.state_RECORD then
					cut:mute()
				elseif cut.state == cut.state_OVERDUB then
					cut:play()
				else
					cut:record()
				end
			end
		end
	end
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

	for r = 1, 4 do
		local rover = rovers[r]
		params:add{
			id = string.format('rover_%d_div', r),
			name = string.format('rover %d div', r),
			type = 'control',
			controlspec = controlspec.new(-12, 11, 'lin', 1, 0),
			formatter = function()
				local value = rover.div
				if value >= 1 then
					return string.format('%dx', value)
				else
					return string.format('%.2fx', value)
				end
			end,
			action = function(value)
				value = math.floor(value + 0.5)
				if value >= 0 then
					rover.div = value + 1
				else
					rover.div = -1 / (value - 1)
				end
			end
		}
	end
	params:bang()

	rover_clock:start()
end

function key(k, z)
	-- TODO: edit map
end

function redraw()
	screen.clear()
	-- TODO: draw map
	screen.update()
end

function cleanup()
	if rover_clock ~= nil then
		rover_clock:stop()
	end
	softcut.poll_stop_phase()
end