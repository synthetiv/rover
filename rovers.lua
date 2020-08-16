-- rovers

Rover = include 'lib/rover'

rover_clock = nil

a = arc.connect()
g = grid.connect()

tau = math.pi * 2

arc_values = { {}, {}, {}, {} }
rovers = {}
held_keys = {}
cursors = {}
cursor_ps = {}
for r = 1, 4 do
	rovers[r] = Rover.new()
	rovers[r].on_point_cross = function(self, v)
		crow.ii.tt.script_v(r, v * 5)
	end
	held_keys[r] = {
		div = false,
		drift = false,
		map = false,
		map_edit = false
	}
	cursors[r] = 0
	cursor_ps[r] = 1
end

function led_blend(a, b)
	return 1 - ((1 - a) * (1 - b))
end

function led_blend_15(a, b)
	return math.floor(led_blend(a, b) * 15 + 0.5)
end

function a_blend(r, x, value)
	x = math.floor(x + 0.5) % 64 + 1
	arc_values[r][x] = led_blend(arc_values[r][x], value)
end

function a_notch(r, angle, width, level)
	local x = (angle * 64 / tau) % 64
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

function a_spiral(r, angle, level, finish_level)
	local finish = math.floor(angle * 64 / tau + 0.5)
	local increment = finish < 0 and -1 or 1
	for x = 0, finish, increment do
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

		a_all(r, rover.point_highlight.value * rover.point_highlight.value * 0.3)

		if held_keys.map then
			if held_keys.map_edit then
				local point = rover.map.points[cursor_ps[r]]
				a_spiral(r, point.o * tau / 3, 0.2, 0.8)
			else
				local cursor = cursors[r]
				local cursor_p = cursor_ps[r]
				a_notch(r, cursor, 1, 0.8)
				a_notch(r, rover.position, 2, 0.3)
				local map = rover.map
				for p, point in ipairs(map.points) do
					a_notch(r, point.i, 1, p == cursor_p and 0.5 or 0.2)
				end
				a_notch(r, rover.highlight_point.i, 1.5, rover.point_highlight.value)
			end
		elseif held_keys.drift then
			a_spiral(r, rover.drift_amount * math.pi, 0.2, 0.8)
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
		g:led(gx + 2, 1, math.floor(rover.values.a * rover.values.a * 10 + 0.5))
		g:led(gx + 2, 2, math.floor(rover.values.b * rover.values.b * 10 + 0.5))
		g:led(gx + 1, 2, math.floor(rover.values.c * rover.values.c * 10 + 0.5))
		g:led(gx + 1, 1, math.floor(rover.values.d * rover.values.d * 10 + 0.5))

		crow.output[r].volts = (rover.values.d - 0.5) * 5

		-- TODO: indicators for noise, drift, drive(?);

		local drift_level = rover.drift.value * rover.drift_amount * 100
		-- TODO: square and 'blend' with initial level of 2
		g:led(gx + 1, 4, math.floor(util.clamp(-drift_level, 0, 8) + 2.5))
		g:led(gx + 2, 4, math.floor(util.clamp(drift_level, 0, 8) + 2.5))

		--[[
		local noise_level = rover.noise.value * 50000
		g:led(gx + 1, 4, math.floor(util.clamp(-noise_level, 0, 10) + 0.5))
		g:led(gx + 2, 4, math.floor(util.clamp(noise_level, 0, 10) + 0.5))
		--]]
		-- control drift amount, maybe other factors (inertias? noise amplitude...? maybe macro controls with 'weight' controlling amplitude + inertia inversely)

		if held_keys.map then
			g:led(gx, 6, led_blend_15(0.25, math.abs(rover.values.p) * 0.7))
			g:led(gx + 1, 6, led_blend_15(held_keys.map_edit and 0.25 or 0.15, math.abs(rover.map.points[cursor_ps[r]].o) * 0.7))
			g:led(gx + 2, 6, 2)
			g:led(gx + 3, 6, 2)
		else
			g:led(gx, 6, led_blend_15(0.15, math.abs(rover.values.p)))
		end
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
	if diff < 0.005 then
		d = d*6
	elseif diff < 0.01 then
		d = d*4
	elseif diff < 0.02 then
		d = d*3
	elseif diff < 0.03 then
		d = d*2
	end
	local held_keys = held_keys[r]
	local rover = rovers[r]
	if held_keys.map then
		local cursor = cursors[r]
		if held_keys.map_edit then
			local point = rover.map.points[cursor_ps[r]]
			cursor = point.i
			point.o = util.clamp(point.o + d * 0.001, -1, 1)
		else
			cursor = (cursor + d * 0.002) % tau
			local o, p = rover.map:read(cursor)
			cursor_ps[r] = p
		end
		cursors[r] = cursor
	elseif held_keys.drift then
		rover.drift_amount = rover.drift_amount + d * 0.001
	elseif held_keys.div then
		params:delta(string.format('rover_%d_div', r), d * 0.02)
	else
		rover:nudge(d)
	end
	screen.ping()
end

function g.key(x, y, z)
	local r = math.floor((x - 1) / 4) + 1
	local rover = rovers[r]
	local rx = (x - 1) % 4 + 1
	-- if (rx == 2 or rx == 3) and (y == 1 or y == 2) then
		-- local d = (0.5 - z) * 0.5
		-- rover.drive.inertia = rover.drive.inertia + d
	-- end
	if rx == 3 and y == 1 then
		rover.hold = rover.hold + (z == 1 and 1 or -1)
	elseif rx == 3 and y == 2 then
		rover.hold = rover.hold + (z == 1 and 1 or -1)
	elseif rx == 2 and y == 2 then
		rover.hold = rover.hold + (z == 1 and 1 or -1)
	elseif rx == 2 and y == 1 then
		rover.hold = rover.hold + (z == 1 and 1 or -1)
	elseif (rx == 2 or rx == 3) and y == 3 then
		held_keys[r].div = z == 1
	elseif (rx == 2 or rx == 3) and y == 4 then
		held_keys[r].drift = z == 1
	elseif rx == 1 and y == 6 then
		held_keys[r].map = z == 1
	elseif rx == 2 and y == 6 then
		held_keys[r].map_edit = z == 1
	elseif rx == 3 and y == 6 and z == 1 then
		rover.map:insert(cursors[r])
		local o, p = rover.map:read(cursors[r])
		cursor_ps[r] = p
	elseif rx == 4 and y == 6 and z == 1 then
		rover.map:delete(cursors[r])
		local o, p = rover.map:read(cursors[r])
		cursor_ps[r] = p
	end
	-- TODO: nudge drive using far left + right buttons
	-- ...and adjust nudge force by holding nudge buttons + touching arc?
end

function init()
	crow.clear()
	for o = 1, 4 do
		crow.output[o].slew = 1/20
	end
	rover_clock = metro.init{
		time = 1/20,
		event = tick
	}

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
	if k == 1 then
		-- TODO: stop drift, allow manual scrubbing
		-- for r = 1, 4 do
		-- end
	end
end

function redraw()
	screen.clear()
	for r = 1, 4 do
		local rover = rovers[r]
		local x = 23 + (r - 1) * 25

		screen.rect(x - 3, 21, 2, 2)
		screen.level(math.floor(rover.values.b * rover.values.b * 15 + 0.5))
		screen.fill()

		screen.rect(x + 3, 43, 2, 2)
		screen.level(math.floor(rover.values.a * rover.values.a * 15 + 0.5))
		screen.fill()
	end
	screen.update()
end

function cleanup()
	if rover_clock ~= nil then
		rover_clock:stop()
	end
end