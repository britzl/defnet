--- Simple, non-blocking, TCP socket client
local socket = require "builtins.scripts.socket"
local tcp_send_queue = require "defnet.tcp_send_queue"

local M = {}

--- Create a TCP socket client and connect it to a server
-- @param server_ip
-- @param server_port
-- @param on_data Function to call when data is received from the server
-- @return instance
-- @return error
function M.create(server_ip, server_port, on_data)
	assert(server_ip, "You must provide a server_ip")
	assert(server_port, "You must provide a server_port")
	assert(on_data, "You must provide a callback function")
	
	print("Creating TCP client")
	
	local instance = {
		pattern = "*l",
	}
	
	local client = nil
	local send_queue = nil
	
	local ok, err = pcall(function()
		client = socket.tcp()
		assert(client:connect(server_ip, server_port))
		assert(client:settimeout(0))
		send_queue = tcp_send_queue.create(client)
	end)
	if not ok or not client or not send_queue then
		print("tcp_client.create() error", err)
		return nil, ("Unable to connect to %s:%d"):format(server_ip, server_port)
	end
	
	--- Send data to the server. This function will add the data to a send queue
	-- and the data will be sent when the @{update} function is called
	-- @param data
	function instance.send(data)
		send_queue.add(data)
	end
	
	--- Call this as often as possible. The function will do two things:
	--  1. Send data that has been added to the send queue using @{send}
	--  2. Receive data
	function instance.update()
		if not client then
			return
		end
		
		send_queue.send()
		
		local data, err = client:receive(instance.pattern or "*l")
		if data then
			local response = on_data(data)
			if response then
				instance.send(response)
			end
		end
	end

	--- Call when the socket client should be destroyed
	-- No other calls to the socket client can be done after it has
	-- been destroyed
	function instance.destroy()
		if client then
			client:close()
			client = nil
		end
	end
	
	return instance
end


return M