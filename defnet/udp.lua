--- Simple UDP connection
-- @usage
-- local udp = require "defnet.udp"
-- 
-- function init(self)
-- 		self.udp_server = udp.create(function(data, ip, port)
-- 			print("Received data", data, ip, port)
-- 		end, 9999)
--
-- 		self.udp1 = udp.create(function(data, ip, port)
-- 			print("Received data", data, ip, port)
-- 		end, nil, "127.0.0.1", 9999)
--		self.udp1.send("foobar to server")
--
-- 		self.udp2 = udp.create(function(data, ip, port)
-- 			print("Received data", data, ip, port)
-- 		end)
--		self.udp2.send("foobar to server", "127.0.0.1", 9990)
-- end
-- 
-- function final(self)
-- 		self.udp_server.destroy()
-- 		self.udp1.destroy()
-- 		self.udp2.destroy()
-- end
-- 
-- function update(self, dt)
-- 		self.udp_server.update()
-- 		self.udp1.update()
-- 		self.udp2.update()
-- end

local M = {}


--- Create UDP connection
-- @param on_data Function to call when data is received (data, ip, port)
-- @param port Optional. The port to bind this socket to
-- @param peer_ip Optional. IP to set as peer ip
-- @param peer_port Optional. Port number to use as peer port
-- @return UDP connection
function M.create(on_data, port, peer_ip, peer_port)
	assert(on_data, "You must provide a callback function")
	
	print("Creating UDP connection")
	
	local instance = {}
	
	local udp = nil

	local ok, err = pcall(function()
		udp = socket.udp()
		assert(udp:settimeout(0))

		if port then
			assert(udp:setsockname("*", port))
		end
		
		if peer_ip and peer_port then
			assert(udp:setpeername(peer_ip, peer_port))
		end
	end)
	if not ok or not udp then
		print("udp_client.create() error", err)
		return nil, "Unable to create client"
	end
	
	--- Send data
	-- @param data
	-- @param ip Destination IP to send data to. Must be nil if peer_ip was specified when creating this object
	-- @param port Destination port to send data to. Must be nil if peer_port was specified when creating this object
	function instance.send(data, ip, port)
		assert(data)
		assert((not peer_ip and ip) or (peer_ip and not ip), "You must either specify a peer IP when creating UDP socket or specify IP when calling this function")
		assert((not peer_port and port) or (peer_port and not port), "You must either specify a peer port when creating UDP socket or specify port when calling this function")
		if not udp then
			return nil, "No connected client"
		end
		if ip and port then
			return udp:sendto(data, ip, port)
		else
			return udp:send(data)
		end
	end

	--- Update the UDP client
	-- This will check for data on the UDP socket
	function instance.update()
		if not udp then
			return
		end
		
		if peer_ip and peer_port then
			local data = udp:receive()
			if data then
				on_data(data, peer_ip, peer_port)
			end
		else
			local data, ip, port = udp:receivefrom()
			if data then
				on_data(data, ip, port)
			end
		end
	end
	
	--- Destroy the UDP connection. The underlying socket will be closed
	-- and no additional operations can be made on the socket.
	function instance.destroy()
		if udp then
			udp:close()
		end
	end
		
	function instance.ip_and_port()
		local ip, port = udp:getsockname()
		port = tonumber(port)
		return ip, port
	end
	
	return instance
end


return M