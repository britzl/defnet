--- Simple UDP client
-- @usage
-- local udp = require "defnet.udp"
-- 
-- function init(self)
-- 	self.udp = udp_client.create(function(data)
-- 		print("Received data from peer", data)
-- 	end)
-- end
-- 
-- function final(self)
-- 	self.udp.destroy()
-- end
-- 
-- function update(self, dt)
-- 	self.udp.update()
-- end

local M = {}


--- Create UDP client
-- @param on_data Function to call when data is received (data, ip, port)
-- @return UDP client
function M.create(on_data)
	assert(on_data, "You must provide a callback function")
	
	print("Creating UDP client")
	
	local instance = {}
	
	local udp = nil

	local ok, err = pcall(function()
		udp = socket.udp()
		--assert(udp:setsockname("*", port))
		--assert(udp:setpeername(peer_ip, peer_port))
		assert(udp:settimeout(0))
	end)
	if not ok or not udp then
		print("udp_client.create() error", err)
		return nil, "Unable to create client"
	end
	
	--- Send data to the peer
	-- @param data
	function instance.send(data, ip, port)
		assert(data)
		assert(ip)
		assert(port)
		if not udp then
			return nil, "No connected client"
		end
		return udp:sendto(data, ip, port)
	end

	--- Update the UDP client. This will
	-- check for data on the UDP socket
	function instance.update()
		if not udp then
			return
		end

		local data, ip, port = udp:receivefrom()
		if data then
			on_data(data, ip, port)
		end
	end
	
	--- Destroy the UDP client. The underlying socket will be closed
	-- and no additional operations can be made on the socket.
	function instance.destroy()
		if udp then
			udp:close()
		end
	end
		
	function instance.ip_and_port()
		local ip, port = udp:getsockname()
		port = tonumber(port)
		ip = ip == "0.0.0.0" and "127.0.0.1" or ip
		return ip, port
	end
	
	return instance
end


return M