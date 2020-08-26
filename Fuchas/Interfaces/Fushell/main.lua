local sh = require("shell")
local fs = require("filesystem")
local tasks = require("tasks")
local driver = require("driver")
local users = require("users")

-- Avoid killing (safely) system process with a custom quit handler
tasks.getCurrentProcess().safeKillHandler = function()
	io.stderr:write("cannot kill system process!\n")
	return false
end

tasks.getCurrentProcess().childErrorHandler = function(proc, err)
	local procType = "process"
	if proc.isService then
		procType = "service"
	end
	io.stderr:write("Error from " .. procType .. " \"" .. proc.name .. "\": " .. tostring(err) .. "\n")
end

tasks.getCurrentProcess().permissionGrant = function(perm, pid)
	local l = nil
	while l ~= "N" and l ~= "Y" do
		io.stdout:write("Grant permission \"" .. perm .. "\" to process? (Y/N) ")
		l = sh.read():upper()
		io.stdout:write(" \n")
	end
	if l == "Y" then
		return true
	else
		return false
	end
end

local rw, rh = driver.gpu.getResolution()

local function printCentered(str)
	io.write(string.rep(" ", math.floor(rw/2-str:len()/2)))
	print(str)
end

-- splash
if not os.getenv("INTERFACE") then -- if this is launched at boot
	print("Fushell in " .. _OSVERSION)
	os.setenv("PWD", "A:/")
	if OSDATA.CONFIG["SAFE_MODE"] then
		print("/!\\ Safe Mode has been enabled! Services and non-essential drivers aren't loaded!")
	else
		print("Type \"help\" if you're new! \"doc\" also helps.")
	end
	if computer.getArchitecture() == "Lua 5.2" then
		for k, v in pairs(computer.getArchitectures()) do
			if v == "Lua 5.3" then
					printCentered("/!\\ Fuchas has detected that the Lua 5.3 architecture is available but not in use.")
			  	if OSDATA.CONFIG["AUTO_SET_ARCH"] then
					printCentered("/!\\ Switching to the Lua 5.3 architecture in 3 seconds. Fuchas will restart.")
					os.sleep(3)
					computer.setArchitecture("Lua 5.3")
				end
				printCentered("/!\\ Please switch to Lua 5.3 by shift-clicking on your CPU or APU")
				printCentered("/!\\ You cannot log into a password protected account with Lua 5.2!")
				goto cont
			end
		end
		printCentered("/!\\ Fuchas has detected that the Lua 5.3 architecture is unavailable.")
		printCentered("/!\\ You will be unable to log in to any password protected accounts.")
	end
	::cont::
end

os.setenv("INTERFACE", "Fushell")

local function execCmd(l)
	local async = false
	if string.endsWith(l, "&") then
		l = l:sub(1, l:len()-1)
		async = true
	end
	local ok, commands = pcall(sh.parseCL, l)
	local chainStream = nil
	if not ok then
		io.stderr:write(commands .. "\n")
		goto continue
	end
	for i=1, #commands do
		local args = commands[i]
		if #args == 0 then
			args[1] = ""
		end
		if args[1] == "exit" then -- special case: exit cmd
			return false
		end
		if args[1]:len() == 2 then
			if args[1]:sub(2, 2) == ":" then
				if not fs.isMounted(args[1]:sub(1, 1)) then
					print("No such drive: " .. args[1]:sub(1, 1):upper())
					goto continue
				end
				os.setenv("PWD", args[1]:sub(1, 1):upper() .. ":/")
				goto continue
			end
		end
		
		if sh.getCommand(args[1]) ~= nil then
			args[1] = sh.getCommand(args[1])
		end

		local newargs = string.split(args[1])
		if #newargs > 1 then
			table.remove(args, 1)
			for i=#newargs, 1, -1 do
				table.insert(args, 1, newargs[i])
			end
		end
		
		local path = sh.resolve(args[1])
		local exists = true
		if not path then
			exists = false
		end
		
		if exists and args[1] ~= "" then
			local f, err = xpcall(function()
				local programArgs = {}
				if #args > 1 then
					for k, v in pairs(args) do
						if k > 1 then
							table.insert(programArgs, v)
						end
					end
				end
				local f, err = loadfile(path)
				if f == nil then
					print(err)
				end

				local func = function()
					if f ~= nil then
						xpcall(f, function(err)
							io.stderr:write(err .. "\n")
							io.stderr:write(debug.traceback(nil, 2) .. "\n")
						end, programArgs)
					end
				end
				local proc = nil

				if i == #commands then
					proc = tasks.newProcess(args[1], func)
					if chainStream then
						proc.io.stdin = chainStream
					end
					if not async then
						proc:join()
						driver.gpu.setForeground(0xFFFFFF)
						driver.gpu.setColor(0)
					end
				else
					local oldChainStream = chainStream
					chainStream, proc = io.pipedProc(func, args[1], "r")
					if oldChainStream then
						proc.io.stdin = oldChainStream
					end
				end
			end, function(err)
				print(debug.traceback(err))
			end)
		else
			print("No such command or external file found.")
			goto continue
		end
	end
	::continue::
	return true
end

local drive = "A"
local run = true
while run do
	::continue::
	local user = users.getUser()
	if user ~= nil then
		io.write(user.name .. "# ")
	end
	io.write(os.getenv("PWD") .. ">")
	local ok, l = pcall(sh.read, {
		["autocomplete"] = sh.fileAutocomplete
	})
	io.write("\n")
	if not ok and string.endsWith(l, "interrupted") then
		print("Ctrl+Alt+C: Restarting")
		computer.shutdown(true)
		return
	end
	run = execCmd(l)
end
