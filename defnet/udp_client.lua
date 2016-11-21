--- Simple UDP client
-- @usage
-- local udp_client = require "defnet.udp_client"
-- local PEER_IP = "localhost"	-- perhaps using p2p discovery?
-- local PEER_PORT = 9192
-- 
-- function init(self)
-- 	self.udp = udp_client.create(PEER_IP, PEER_PORT, function(data)
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
-- @param peer_ip IP to send data to
-- @param peer_port Port to send data to
-- @param on_data Function to call when data is received (data, ip, port)
-- @return UDP client
function M.create(peer_ip, peer_port, on_data)
	assert(peer_ip, "You must specify an IP")
	assert(peer_port, "You must specify a port")
	assert(on_data, "You must provide a callback function")
	
	print("Creating UDP client", peer_ip, peer_port)
	
	local client = {}
	
	local client_socket = nil

	local ok, err = pcall(function()
		client_socket = socket.udp()
		assert(client_socket:setpeername(peer_ip, peer_port))
		assert(client_socket:settimeout(0))
	end)
	if not ok or not client_socket then
		print("udp_client.create() error", err)
		return nil, "Unable to create client"
	end
	
	--- Send data to the peer
	-- @param data
	function client.send(data)
		if not client_socket then
			return nil, "No connected client"
		end
		return client_socket:send(data)
	end

	--- Update the UDP client. This will
	-- check for data on the UDP socket
	function client.update()
		if not client_socket then
			return
		end

		local data = client_socket:receive()
		if data then
			on_data(data)
		end
	end
	
	--- Destroy the UDP client. The underlying socket will be closed
	-- and no additional operations can be made on the socket.
	function client.destroy()
		if client_socket then
			client_socket:close()
		end
	end
	
	return client
end


return M