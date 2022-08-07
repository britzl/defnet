--- Simple, non-blocking, TCP socket server that listens for
-- clients on a specific port and for each connection
-- polls for data.
--
-- @usage
--
--	local function on_data(data, ip, port, client)
--		print("Received", data, "from", ip)
--		return "My response"
--	end
--	
--	local function on_client_connected(ip, port, client)
--		print("Client", ip, "connected")
--	end
--	
--	local function on_client_disconnected(ip, port, client)
--		print("Client", ip, "disconnected")
--	end
--	
--	function init(self)
--		self.server = tcp_server.create(8190, on_data, on_client_connected, on_client_disconnected)
--		self.server.start()
--	end
--	
--	function final(self)
--		self.server.stop()
--	end
--	
--	function update(self, dt)
--		self.server.update()
--	end
--

local tcp_send_queue = require "defnet.tcp_send_queue"
local socket = require "builtins.scripts.socket"

local M = {}

M.TCP_SEND_CHUNK_SIZE = 8192

M.log = print

local log = function(...) M.log(...) end

--- Creates a new TCP socket server
-- @param port
-- @param on_data Function to call when data is received. The
-- function will be called with the following args: data, ip
-- Any value returned from this function will be sent as response.
-- @param on_client_connected Function to call when a client has
-- connected. The function will be called with the following args: ip
-- @param on_client_disconnected Function to call when a client has
-- disconnected. The function will be called with the following args: ip
-- @return Server instance
function M.create(port, on_data, on_client_connected, on_client_disconnected)
	assert(port, "You must provide a port")
	assert(on_data, "You must provide an on_data function")

	log("Creating TCP server")
	
	local server = {}

	local co = nil
	local server_socket = nil

	local clients = {}
	local queues = {}

	local function remove_client(connection_to_remove)
		for i,connection in pairs(clients) do
			if connection == connection_to_remove then
				table.remove(clients, i)
				queues[connection_to_remove] = nil
				if on_client_disconnected then
					local client_ip, client_port = connection:getpeername()
					on_client_disconnected(client_ip, client_port, connection)
				end
				break
			end
		end
	end

	server.on_data = function(fn)
		on_data = fn
	end

	server.on_client_connected = function(fn)
		on_client_connected = fn
	end

	server.on_client_disconnected = function(fn)
		on_client_disconnected = fn
	end
	
	server.start = function()
		log("Starting TCP server on port " .. port)
		local ok, err = pcall(function()
			local skt, err = socket.bind("*", port)
			assert(skt, err)
			server_socket = skt
			server_socket:settimeout(0)
		end)
		if not server_socket or err then
			log("Unable to start TCP server", err)
			return false, err
		end
		return true
	end

	server.stop = function()
		log("Stopping TCP server")
		if server_socket then
			server_socket:close()
		end
		while #clients > 0 do
			local client = table.remove(clients)
			queues[client] = nil
			client:close()
		end
	end
	
	server.receive = function(client)
		return client:receive("*l")
	end
	
	server.broadcast = function(data)
		log("Broadcasting")
		for client,queue in pairs(queues) do
			queue.add(data)
		end
	end

	server.send = function(data, client)
		log("Sending data to", client)
		for c,queue in pairs(queues) do
			if c == client then
				queue.add(data)
				break
			end
		end
	end
	
	server.update = function()
		if not server_socket then
			return
		end
		
		-- new connection?
		local client, err = server_socket:accept()
		if client then
			client:settimeout(0)
			table.insert(clients, client)
			queues[client] = tcp_send_queue.create(client, M.TCP_SEND_CHUNK_SIZE)
			if on_client_connected then
				local client_ip, client_port = client:getpeername()
				on_client_connected(client_ip, client_port, client)
			end
		end
		
		-- read from client sockets that has data
		local read, write, err = socket.select(clients, nil, 0)
		for _,client in ipairs(read) do
			coroutine.wrap(function()
				local data, err = server.receive(client)
				if data and on_data then
					local client_ip, client_port = client:getpeername()
					local response = on_data(data, client_ip, client_port, client, function(response)
						if not queues[client] then
							return false
						end
						queues[client].add(response)
						return true
					end)
					if response then
						queues[client].add(response)
					end
				end
				if err and err == "closed" then
					remove_client(client)
				end
			end)()
		end
		
		-- send to client sockets that are writable
		local read, write, err = socket.select(nil, clients, 0)
		for _,client in ipairs(write) do
			coroutine.wrap(function()
				local ok, err = queues[client].send()
			end)()
		end
	end

	return server
end


--- Start the TCP socket server and listen for clients
-- Each connection is run in it's own coroutine
-- @param server
-- @return success
-- @return error_message
function M.start(server)
	assert(server)
	return server.start()
end

--- Stop the TCP socket server. The socket and all
-- clients will be closed
-- @param server
function M.stop(server)
	assert(server)
	return server.stop()
end

--- Receive data from a client
-- Override with your own implementation if necessary
-- @param server
-- @param client
function M.receive(server, client)
	assert(server)
	assert(client)
	return server.receive(client)
end

--- Broadcast data to all connected clients
-- @param server
-- @param data
function M.broadcast(server, data)
	assert(server)
	assert(data)
	return server.broadcast(data)
end

--- Send data to a connected client
-- @param server
-- @param data
-- @param client
function M.send(server, data, client)
	assert(server)
	assert(data)
	assert(client)
	return server.send(data, client)
end

--- Update the TCP socket server. This will resume all
-- the spawned coroutines in order to check for new
-- clients and data on existing clients
-- @param server
function M.update(server)
	assert(server)
	return server.update()
end

--- Set data callback
-- @param server
-- @param fn Function to call when data is received (args: data, ip, port, client)
function M.on_data(server, fn)
	return server.on_data(fn)
end

--- Set client connect callback
-- @param server
-- @param fn Function to call when a client connects (args: ip, port, client)
function M.on_client_connected(server, fn)
	return server.on_client_connected(fn)
end

--- Set client disconnect callback
-- @param server
-- @param fn Function to call a client disconnects (args: ip, port, client)
function M.on_client_disconnected(server, fn)
	return server.on_client_disconnected(fn)
end

return M
