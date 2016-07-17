-- thread.lua code is written by Zer0Galaxy
-- Code:  http://pastebin.com/E0SzJcCx

local thread = require("thread")
local component = require("component")
local event = require("event")
local serialization = require("serialization")
local text = require("text")
local term = require("term")
local unicode = require("unicode")
local modem = component.modem
local primaryPort = math.random(512, 1024)
local restart = false

local users = io.open("users", "ab")
users:close(users)
local banlist = io.open("banlist", "ab")
banlist:close(banlist)


local function CheckLogFile()
	local fs = require("filesystem")
	if fs.size("log") > 500000 then
		fs.rename("log", "log_old")
		print("New log file created. Old log file saved as log_old")
	else print("Log file size — " .. fs.size("log") .. " bytes") end
end

local function Log(address, port, message)
	local log = io.open("log", "ab")
	io.input(log)
	log:seek("end")	
	log:write(address .. ':' .. port .. '\n' .. message .. '\n')
	log:close(log)
end

local function CheckBanList(nickname)
	local line
	local file = io.open("banlist", "rb")
	io.output(file)
	file:seek("set")
	while true do
		line = file:read()
		if nickname == line then return 0 end	
		if line == nil then return 1 end 		
	end
	file:close(file)	
end

local function AddToBanList(nickname)
	if CheckBanList(nickname) == 1 then
		local line
		local file = io.open("banlist", "ab")
		io.input(file)
		file:seek("end")
		file:write(string.format("%s\n", nickname))
		file:close(file)
		modem.broadcast(primaryPort, nickname .. " was banned")
	end
end

local function ModemSettings()
	modem.open(253)
	modem.open(254)
	modem.open(255) 
	modem.open(256)
	modem.open(primaryPort)
	modem.setStrength(5000)
end

local count, isFlooder, flooder = 0, false, nil
local function FloodReset()
	count = 0
	isFlooder = false
	flooder = nil
end

local function Manager()
	local _, _, address, port, _, message
	local lastaddress, nickname, mute
	while true do
		_, _, address, port, _, message = event.pull("modem_message")
		if 	port == primaryPort then 
			if isFlooder == true and flooder == address then address = "flood"
			else PrimaryLevel(message) end
		elseif	port == 256 then AuthenticationLevel(address, message)
		elseif	port == 255 then RegistrationLevel(address, message)
		elseif	port == 254 then modem.send(address, 254, 1) end
		Log(address, port, message)
		
		-- Anti-flood
		if lastaddress == address and port == primaryPort then
			count = count + 1 
			if count > 5 then 
				event.timer(10, FloodReset)
				isFlooder = true
				flooder = lastaddress
				nickname = string.sub(message, 1, string.find(message, ":") - 1)
				mute = "[Server] " .. nickname .. " muted for 10 seconds"
				modem.broadcast(primaryPort, mute)
			end
		else 
			lastaddress = address
			count = 0
		end
	end
end

local function PingUsers()
	while true do
		local online = {}
		local _, _, address, port, _, username, packet
		event.pull(30, "waiting")
		modem.broadcast(253, 'P')
		while true do
			_, _, address, port, _, username = event.pull(3, "modem_message")
			if port == nil then break end
			if port == 253 then table.insert(online, username) end
		end
		table.sort(online)
		packet = serialization.serialize(online)
		modem.broadcast(253, packet)
	end
end	

local function RegistrationLevel(address, message)
	local user = serialization.unserialize(message)
	if 	unicode.len(user[1]) < 3 or unicode.len(user[1]) > 15  or
		unicode.len(user[2]) < 3 or unicode.len(user[2]) > 10  then
		modem.send(address, 255, "Имя должно быть от 3 до 15 символов\nПароль должен быть от 3 до 10 символов")
	else if string.find(user[1], "[%p%c%d]") ~= nil then
		modem.send(address, 255, "Имя содержит запрещенные символы")
		else
			local line
			local file = io.open("users", "rb")
			io.output(file)
			while true do
				line = file:read()
				if user[1] == line then
					modem.send(address, 255, "Пользователь с таким именем уже существует")
					break end		
				file:read()
				line = file:read()
				if line == address then 
					modem.send(address, 255, "С Вашего адреса уже зарегестрирован пользователь")
					break end
				if line == nil then
					file:close(file)
					file = io.open("users", "ab")
					io.input(file)
					local c = file:seek("end")
					if c ~= 0 then file:write(string.format("\n%s\n%s\n%s", user[1], user[2], address))
					else file:write(string.format("%s\n%s\n%s", user[1], user[2], address)) end
					modem.send(address, 255, 1)				
					break
				end 	
			end
			file:close(file)
		end
	end
end

local function AuthenticationLevel(address, message)
	local user = serialization.unserialize(message)
	local line
	local file = io.open("users", "rb")
	io.output(file)
	file:seek("set")
	while true do
		line = file:read()
		if user[1] == line then
			if CheckBanList(user[1]) == 0 then 
				modem.send(address, 256, -1) break end -- user banned (-1)
			line = file:read()
			if user[2] == line then 				
				modem.send(address, 256, primaryPort)	
				modem.broadcast(primaryPort, user[1] .. " присоединился к чату")
			else modem.send(address, 256, "Неверный пароль") end
			break
		else file:read() file:read() end
		if line == nil then 	
			modem.send(address, 256, "Пользователя с таким именем не существует")
			break
		end 		
	end
	file:close(file)
end

local function PrimaryLevel(message)
	local check, nicklen, mlen
	check = text.trim(message)
	nicklen = string.find(check, ':')
	mlen = unicode.len(message) - nicklen - 2
	if mlen > 1 then modem.broadcast(primaryPort, message) end
end
	
local function Administration()
	local command 
	while true do
		command = term.read()
		command = text.trim(command)
		if command == "restart" then restart = true
			modem.broadcast(primaryPort, 'R') break end
		if command == "close" then 
			modem.broadcast(primaryPort, 'C') break end
		if unicode.sub(command, 1, 4) == "ban " then AddToBanList(unicode.sub(command, 5))
		else modem.broadcast(primaryPort, string.format("[Server] %s", command)) end 
	end
end


CheckLogFile()
thread.init()			
ModemSettings()
thread.create(PingUsers)
thread.create(Manager)
Administration()
thread.killAll()
thread.waitForAll()
modem.close()
if restart == true then os.execute("reboot") end