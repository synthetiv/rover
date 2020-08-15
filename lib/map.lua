local Path = {}
Path.__index = Path

local tau = math.pi * 2

function Path.new()
	local p = setmetatable({}, Path)
	p.points = {
		{ i = 0, o = 0 }
	}
	p.count = 1
	return p
end

function Path:read(i)
	i = i % tau
	local lower_p = self.count
	local lower_i = self.points[self.count].i
	for p = 1, self.count do
		if i >= self.points[p].i then
			lower_p = p
			lower_i = self.points[p].i
		end
	end
	local upper_p = lower_p % self.count + 1
	local upper_i = self.points[upper_p].i
	if upper_i <= lower_i then -- handle segment that crosses over i=2pi back to i=0
		upper_i = upper_i + tau
	end
	local segment_size = upper_i - lower_i
	local lower_distance = math.abs(lower_i - i)
	local upper_distance = math.abs(upper_i - i)
	local lower_mix = 1 - (lower_distance / segment_size)
	local upper_mix = 1 - (upper_distance / segment_size)
	local o = self.points[lower_p].o * lower_mix + self.points[upper_p].o * upper_mix
	if lower_distance <= upper_distance then
		return o, lower_p
	else
		return o, upper_p
	end
end

local function sort_points(a, b)
	return a.i < b.i
end

function Path:insert(i, o)
	if o == nil then
		o = self:read(i)
	end
	table.insert(self.points, { i = i, o = o })
	table.sort(self.points, sort_points)
	self.count = self.count + 1
end

function Path:delete(i)
	local o, p = self:read(i)
	self.count = self.count - 1
	table.remove(self.points, p)
	if self.count < 1 then
		self:insert(0, 0)
	end
end

return Path
