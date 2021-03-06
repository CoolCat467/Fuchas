local spec = {}
local cp = ...

function spec.isCompatible(address)
	return cp.proxy(address).type == "tape_drive"
end

function spec.getRank()
	return -1 -- doesn't make sense for a filesystem
end

function spec.getName()
	return "Vexatos Computronics Inc. Tape Driver"
end

function spec.new(address)
	local pos = 0
	local drv = {}
	local tape = cp.proxy(address)

	local function sync(npos)
		if tape.getPosition then pos = tape.getPosition() end
		if pos ~= npos then
			tape.seek(npos - pos)
			pos = npos
		end
	end

	local function checkInsert()
		if not tape.isReady() then
			error("tape not inserted")
		end
	end

	function drv.getLabel()
		checkInsert()
		return tape.getLabel()
	end

	function drv.setLabel(label)
		checkInsert()
		tape.setLabel(label)
		return tape.getLabel()
	end

	function drv.readBytes(off, len)
		checkInsert()
		sync(off)
		return tape.read(len)
	end

	-- Should be used instdead of drv.writeByte when possible, as it *can be* optimized
	function drv.writeBytes(offset, data, len)
		checkInsert()
		if type(data) == "string" then
			local d = {}
			for i=1, #data do
				table.insert(d, data:sub(i, i))
			end
			data = d
		end
		sync(offset)
		tape.write(data)
	end

	function drv.readByte(off)
		checkInsert()
		sync(off)
		return tape.read()
	end

	function drv.writeByte(off, val)
		checkInsert()
		sync(off)
		tape.write(val)
	end

	return drv
end

return spec