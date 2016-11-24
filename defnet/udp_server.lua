--- Super simple UDP socket server
-- @usage
--
-- local udp_server = require "defnet.udp_server"
-- 
-- function init(self)
-- 	self.udp = udp_server.create(9192, function(data, ip, port)
-- 		self.udp.send("echo", ip, port)
-- 	end)
-- end
-- 
-- function final(self)
-- 	self.udp.stop()
-- end
-- 
-- function update(self, dt)
-- 	self.udp.update()
-- end

local M = {}


--- Create an UDP socket server. The server can receive data from and send
-- data to UDP sockets. This is a minimal implementation without any connection
-- handling
-- @param port The port to listen to connections on
-- @param on_data The function to invoke when data is received (args: data, ip, port)
function M.create(port, on_data)
	assert(port, "You must provide a port")
	assert(on_data, "You must provide an on_data function")

	print("Creating UDP server")
	
	local server = {}

	local server_socket = nil

	--- Start the UDP socket server
	-- @return success
	-- @return error_message
	function server.start()
		print("Starting UDP server on port " .. port)
		local ok, err = pcall(function()
			server_socket = assert(socket.udp())
			assert(server_socket:setsockname("*", port))
		end)
		if not server_socket or err then
			print("Unable to start UDP server", err)
			server_socket = nil
			return false, err
		end

		server_socket:settimeout(0)
		return true
	end

	--- Stop the UDP socket server.
	-- The socket will be closed and cannot be used again.
	function server.stop()
		if server_socket then
			server_socket:close()
		end
	end
	
	--- Send a datagram to an UDP socket on a specific
	-- IP and port
	-- @param datagram
	-- @param ip
	-- @param port
	-- @return success
	-- @return error_message
	function server.send(datagram, ip, port)
		assert(datagram, "You must provide a datagram")
		assert(ip, "You must provide an IP adress")
		assert(port, "You must provide a port number")
		return server_socket:sendto(datagram, ip, port)
	end

	--- Update the UDP socket server.
	-- This will try to read data from socket
	function server.update()
		if not server_socket then
			return
		end
		local datagram, ip, port = server_socket:receivefrom()
		if datagram then
			local response = on_data(datagram, ip, port)
			if response then
				server.send(response, ip, port)
			end
		end
	end

	return server
end


return M