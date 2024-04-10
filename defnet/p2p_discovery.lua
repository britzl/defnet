--- Module to perform peer-to-peer discovery
-- The module can either broadcast it's existence or listen for others

local M = {}

local STATE_DISCONNECTED = "STATE_DISCONNECTED"
local STATE_BROADCASTING = "STATE_BROADCASTING"
local STATE_LISTENING = "STATE_LISTENING"


local function starts_with( str, start )
	if str == nil or start == nil then return false end
	return str:sub( 1, #start ) == start
end


local function get_ip()
	for _,network_card in pairs(sys.get_ifaddrs()) do
		if network_card.up and network_card.address then
			pprint(network_card)
			return network_card.address
		end
	end
	return nil
end

--- Create a peer to peer discovery instance
function M.create(port)
	local instance = {}

	local state = STATE_DISCONNECTED

	port = port or 50000

	local listen_co
	local broadcast_co

	--- Start broadcasting a message for others to discover
	-- @param message
	-- @return success
	-- @return error_message
	function instance.broadcast(message)
		assert(message, "You must provide a message to broadcast")
		local broadcaster
		local ok, err = pcall(function()
			broadcaster = socket.udp()
			assert(broadcaster:setsockname("*", 0))
			assert(broadcaster:setoption("broadcast", true))
			assert(broadcaster:settimeout(0))
		end)
		if not broadcaster or err then
			print("Error", err)
			return false, err
		end

		print("Broadcasting " .. message .. " on port " .. port)
		state = STATE_BROADCASTING
		broadcast_co = coroutine.create(function()
			while state == STATE_BROADCASTING do
				local ok, err = pcall(function()
					broadcaster:sendto(message, "255.255.255.255", port)
				end)
				if err then
					print("DISCONNECTED")
					state = STATE_DISCONNECTED
				else
					coroutine.yield()
				end
			end
			broadcaster:close()
			broadcast_co = nil
		end)
		return coroutine.resume(broadcast_co)
	end

	--- Start listening for a broadcasting server
	-- @param message The message to listen for
	-- @param callback Function to call when a broadcasting server has been found. The function
	-- must accept the broadcasting server's IP and port as arguments.
	-- @return success
	-- @return error_message
	function instance.listen(message, callback)
		assert(message, "You must provide a message to listen for")
		local listener
		local ok, err = pcall(function()
			listener = socket.udp()
			assert(listener:setsockname("*", port))
		end)
		if not listener then
			print("Error", err)
			return false, err
		end

		print("Listening for " .. message .. " on port ".. port)
		state = STATE_LISTENING
		listen_co = coroutine.create(function()
			while state == STATE_LISTENING do
				listener:settimeout(0)
				local data, server_ip, server_port = listener:receivefrom()
				if data and starts_with( data, message ) then
					-- pass on optional payload only
					callback(server_ip, server_port, data:sub(#message + 1))
				end
				coroutine.yield()
			end
			listener:close()
			listen_co = nil
		end)
		return coroutine.resume(listen_co)
	end

	--- Stop broadcasting or listening
	function instance.stop()
		state = STATE_DISCONNECTED
	end

	function instance.update()
		if broadcast_co then
			if coroutine.status(broadcast_co) == "suspended" then
				coroutine.resume(broadcast_co)
			end
		elseif listen_co then
			if coroutine.status(listen_co) == "suspended" then
				coroutine.resume(listen_co)
			end
		end
	end

	return instance
end


return M
