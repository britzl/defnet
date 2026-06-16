--- Simple, non-blocking, TCP socket client
-- @usage
-- local tcp_client = require "defnet.tcp_client"
-- local IP = "localhost" -- perhaps get IP from P2P discovery?
-- local PORT = 9189
--
-- function init(self)
--	self.client = tcp_client.create(IP, PORT, function(data)
--		print("TCP client received data " .. data)
--	end,
--	function()
--		print("On disconnected")
--		self.client = nil
--	end)
-- end
--
-- function update(self, dt)
--	if self.client
--		self.client.update()
--	end
-- end
--
-- function on_input(self, action_id, action)
-- 	-- on some condition do:
-- 	self.client.send("Sending this to the server\n")
-- end

local tcp_data_queue = require "defnet.tcp_data_queue"

local M = {}

M.TCP_SEND_CHUNK_SIZE = 8192

M.log = print

local log = function(...) M.log(...) end

--- Create a TCP socket client and connect it to a server
-- @param server_ip
-- @param server_port
-- @param on_data Function to call when data is received from the server
-- @param on_disconnect Function to call when the connection to the server ends
-- @param options Table with options (keys: connection_timeout (s), binary, chunk_size)
-- @return client
-- @return error
function M.create(server_ip, server_port, on_data, on_disconnect, options)
	assert(server_ip, "You must provide a server_ip")
	assert(server_port, "You must provide a server_port")
	assert(on_data, "You must provide an on_data callback function")
	assert(on_disconnect, "You must provide an on_disconnect callback function")

	log("Creating TCP client", server_ip, server_port)

	local client = {}

	local client_socket = nil
	local data_queue = nil
	local client_socket_table = nil
	local connection_timeout = options and options.connection_timeout or nil
	local data_queue_options = {
		chunk_size = options and options.chunk_size or M.TCP_SEND_CHUNK_SIZE,
		binary = options and options.binary or false,
	}

	local ok, err = pcall(function()
		client_socket = socket.tcp()
		assert(client_socket:settimeout(connection_timeout))
		assert(client_socket:connect(server_ip, server_port))
		assert(client_socket:settimeout(0))
		client_socket_table = { client_socket }
		data_queue = tcp_data_queue.create(client_socket, data_queue_options)
	end)
	if not ok or not client_socket or not data_queue then
		log("tcp_client.create() error", err)
		return nil, ("Unable to connect to %s:%d"):format(server_ip, server_port)
	end

	client.on_data = function(fn)
		on_data = fn
	end

	client.on_disconnect = function(fn)
		on_disconnect = fn
	end

	client.send = function(data)
		data_queue.add(data)
	end

	client.update = function()
		if not client_socket then
			return
		end

		-- check if the socket is ready for reading and/or writing
		local receivet, sendt = socket.select(client_socket_table, client_socket_table, 0)

		if sendt[client_socket] then
			local ok, err = data_queue.send()
			if not ok and err == "closed" then
				client.destroy()
				on_disconnect()
				return
			end
		end

		if receivet[client_socket] then
			while client_socket do
				local data, err = data_queue.receive()
				if data then
					local response = on_data(data)
					if response then
						client.send(response)
					end
				elseif err == "closed" then
					client.destroy()
					on_disconnect()
				else
					break
				end
			end
		end
	end

	client.destroy = function()
		log("Destroying TCP client")
		if client_socket then
			client_socket:close()
			client_socket = nil
		end
	end

	return client
end


--- Set callback when data is received
-- @param client
-- @param fn The function to call when data is received
function M.on_data(client, fn)
	assert(client)
	return client.on_data(fn)
end

--- Set callback when disconnected
-- @param client
-- @param fn The function to call when disconnected
function M.on_disconnect(client, fn)
	assert(client)
	return client.on_disconnect(fn)
end

--- Send data to the server. This function will add the data to a send queue
-- and the data will be sent when the @{update} function is called
-- @param client
-- @param data
function M.send(client, data)
	assert(client)
	assert(data)
	return client.send(data)
end

--- Call this as often as possible. The function will do two things:
--  1. Send data that has been added to the send queue using @{send}
--  2. Receive data
-- @param client
function M.update(client)
	assert(client)
	return client.update()
end

--- Call when the socket client should be destroyed
-- No other calls to the socket client can be done after it has
-- been destroyed
-- @param client
function M.destroy(client)
	assert(client)
	return client.destroy()
end

return M
