--- Simple, non-blocking, TCP socket client
-- @usage
-- local tcp_client = require "defnet.tcp_client"
-- local IP = "localhost" -- perhaps get IP from P2P discovery?
-- local PORT = 9189
-- 
-- function init(self)
-- 	self.client = tcp_client.create(IP, PORT, function(data)
-- 		print("TCP client received data " .. data)
-- 	end
-- end
-- 
-- function update(self, dt)
-- 	self.client.update()
-- end
-- 
-- function on_input(self, action_id, action)
-- 	-- on some condition do:
-- 	self.client.send("Sending this to the server\n")
-- end

local socket = require "builtins.scripts.socket"
local tcp_send_queue = require "defnet.tcp_send_queue"

local M = {}

M.TCP_SEND_CHUNK_SIZE = 8192

--- Create a TCP socket client and connect it to a server
-- @param server_ip
-- @param server_port
-- @param on_data Function to call when data is received from the server
-- @return client
-- @return error
function M.create(server_ip, server_port, on_data)
	assert(server_ip, "You must provide a server_ip")
	assert(server_port, "You must provide a server_port")
	assert(on_data, "You must provide a callback function")
	
	print("Creating TCP client", server_ip, server_port)
	
	local client = {
		pattern = "*l",
	}
	
	local client_socket = nil
	local send_queue = nil
	
	local ok, err = pcall(function()
		client_socket = socket.tcp()
		assert(client_socket:connect(server_ip, server_port))
		assert(client_socket:settimeout(0))
		send_queue = tcp_send_queue.create(client_socket, M.TCP_SEND_CHUNK_SIZE)
	end)
	if not ok or not client_socket or not send_queue then
		print("tcp_client.create() error", err)
		return nil, ("Unable to connect to %s:%d"):format(server_ip, server_port)
	end
	
	--- Send data to the server. This function will add the data to a send queue
	-- and the data will be sent when the @{update} function is called
	-- @param data
	function client.send(data)
		send_queue.add(data)
	end
	
	--- Call this as often as possible. The function will do two things:
	--  1. Send data that has been added to the send queue using @{send}
	--  2. Receive data
	function client.update()
		if not client_socket then
			return
		end
		
		send_queue.send()
		
		local data, err = client_socket:receive(client.pattern or "*l")
		if data then
			local response = on_data(data)
			if response then
				client.send(response)
			end
		end
	end

	--- Call when the socket client should be destroyed
	-- No other calls to the socket client can be done after it has
	-- been destroyed
	function client.destroy()
		if client_socket then
			client_socket:close()
			client_socket = nil
		end
	end
	
	return client
end


return M
