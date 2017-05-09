local flow = require "ludobits.m.flow"
local p2p_discovery = require "defnet.p2p_discovery"
local udp = require "defnet.udp"

local trickle = require "multiplayer.trickle"

local M = {}

local P2P_PORT = 50000
local UDP_SERVER_PORT = 9192

local STATE_LISTENING = "STATE_LISTENING"
local STATE_JOINED_GAME = "STATE_JOINED_GAME"
local STATE_HOSTING_GAME = "STATE_HOSTING_GAME"

local function generate_unique_id()
	return tostring(socket.gettime()) .. tostring(os.clock()) .. tostring(math.random(99999,10000000))
end

local mp = {
	id = nil,
	state = nil,
	clients = {},
	message_signatures = {},
	message_handlers = {},
	stream = trickle.create(),
}


M.HEARTBEAT = "HEARTBEAT"
M.CLIENT_JOINED = "CLIENT_JOINED"
M.CLIENT_LEFT = "CLIENT_LEFT"
M.JOIN_SERVER = "JOIN_SERVER"
M.LEAVE_SERVER = "LEAVE_SERVER"

local client_joined_signature = {
	{ "ip", "string" },
	{ "port", "float" },
	{ "id", "string" },
}

local client_left_signature = {
	{ "id", "string" },
}

local join_server_signature = {
	{ "id", "string" },
}

local leave_server_signature = {
	{ "id", "string" },
}

local heartbeat_signature = {
	{ "id", "string" },
}

local function create_client_joined_message(ip, port, id)
	assert(ip, "You must provide an ip")
	assert(port, "You must provide a port")
	assert(id, "You must provide an id")
	local message = trickle.create()
	message:writeString(M.CLIENT_JOINED)
	message:pack({ ip = ip, port = port, id = id }, client_joined_signature)
	return tostring(message)
end

local function create_client_left_message(id)
	assert(id, "You must provide an id")
	local message = trickle.create()
	message:writeString(M.CLIENT_LEFT)
	message:pack({ id = id }, client_left_signature)
	return tostring(message)
end

local function create_join_server_message(id)
	assert(id, "You must provide an id")
	local message = trickle.create()
	message:writeString(M.JOIN_SERVER)
	message:pack({ id = id }, join_server_signature)
	return tostring(message)
end

local function create_leave_server_message(id)
	local message = trickle.create()
	message:writeString(M.LEAVE_SERVER)
	message:pack({ id = id }, leave_server_signature)
	return tostring(message)
end

local function create_heartbeat_message(id)
	assert(id, "You must provide an id")
	local message = trickle.create()
	message:writeString(M.HEARTBEAT)
	message:pack({ id = id }, heartbeat_signature)
	return tostring(message)
end


function M.register_message(message_type, message_signature)
	assert(message_type, "You must provide a message type")
	assert(message_signature, "You must provide a message signature")
	mp.message_signatures[message_type] = message_signature
end

function M.register_handler(message_type, handler_fn)
	assert(message_type, "You must provide a message type")
	assert(handler_fn, "You must provide a handler function")
	mp.message_handlers[message_type] = mp.message_handlers[message_type] or {}
	table.insert(mp.message_handlers[message_type], handler_fn)
end

local function handle_message(message_type, stream, from_ip, from_port)
	assert(message_type, "You must provide a message type")
	assert(stream, "You must provide a stream")
	if mp.message_handlers[message_type] and mp.message_signatures[message_type] then
		local message = stream:unpack(mp.message_signatures[message_type])
		for _,handler in ipairs(mp.message_handlers[message_type]) do
			handler(message, from_ip, from_port)
		end
	end
end


--- Remove a client from the list of clients
-- @param id Id of the client to remove
local function remove_client(id)
	assert(id, "You must provide an id")
	mp.clients[id] = nil
end

--- 
-- Add a client to the list of clients
-- Can be called multiple times without risking duplicates
-- @param ip Client ip
-- @param port Client port
-- @param id Client id
local function add_client(ip, port, id)
	assert(ip, "You must provide an ip")
	assert(port, "You must provide a port")
	assert(id, "You must provide an id")
	mp.clients[id] = { ip = ip, port = port, ts = socket.gettime(), id = id }
end

--- Update the timestamp for a client
-- @param id
local function refresh_client(id)
	assert(id, "You must provide an id")
	if mp.clients[id] then
		mp.clients[id].ts = socket.gettime()
	end
end

--- Send a message to all clients
-- @param message The message to send
local function send_to_clients(message)
	assert(message, "You must provide a message")
	for _,client in pairs(mp.clients) do
		mp.udp_client.send(message, client.ip, client.port)
	end
end



local function send_client_joined_message(ip, port, id)
	assert(ip, "You must provide an ip")
	assert(port, "You must provide a port")
	assert(id, "You must provide an id")
	send_to_clients(create_client_joined_message(ip, port, id))
end

local function send_client_left_message(id)
	assert(id, "You must provide an id")
	send_to_clients(create_client_left_message(id))
end

--- Start the multiplayer module
-- The module will begin listening for servers on the local network
-- If no server is found it will create one and start broadcasting
-- @param on_connected The function to call when connected to a server
function M.start(on_connected)
	assert(on_connected)
	mp.id = generate_unique_id()
	M.register_message(M.JOIN_SERVER, join_server_signature)
	M.register_message(M.LEAVE_SERVER, leave_server_signature)
	M.register_message(M.CLIENT_JOINED, client_joined_signature)
	M.register_message(M.CLIENT_LEFT, client_left_signature)
	M.register_message(M.HEARTBEAT, heartbeat_signature)
	
	M.register_handler(M.CLIENT_JOINED, function(message, from_ip, from_port)
		add_client(message.ip, message.port, message.id)
	end)
	M.register_handler(M.CLIENT_LEFT, function(message, from_ip, from_port)
		remove_client(message.id)
	end)
	M.register_handler(M.HEARTBEAT, function(message, from_ip, from_port)
		refresh_client(message.id)
	end)
	M.register_handler(M.JOIN_SERVER, function(message, from_ip, from_port)
		-- notify client of already joined clients
		for _,client in pairs(mp.clients) do
			if client.id ~= message.id then
				mp.udp_client.send(create_client_joined_message(client.ip, client.port, client.id), from_ip, from_port)
			end
		end
		add_client(from_ip, from_port, message.id)
		send_client_joined_message(from_ip, from_port, message.id)
	end)
	M.register_handler(M.LEAVE_SERVER, function(message, from_ip, from_port)
		remove_client(message.id)
		send_client_left_message(message.id)
	end)
	
	flow(function()
		mp.p2p_listen = p2p_discovery.create(P2P_PORT)
		mp.p2p_broadcast = p2p_discovery.create(P2P_PORT)

		-- create our UDP connection
		-- we use this to communicate with the server
		-- and the other clients
		mp.udp_client = udp.create(function(data, ip, port)
			local stream = trickle.create(data)
			local message_type = stream:readString()
			handle_message(message_type, stream, ip, port)
		end)
		
		-- let's start by listening if there's someone already looking for players
		-- wait for a while and if we don't find a server we start broadcasting
		print("LISTEN")
		mp.state = STATE_LISTENING
		mp.p2p_listen.listen("findme", function(ip, port)
			print("Found server", ip, port)
			mp.state = STATE_JOINED_GAME
			mp.host_ip = ip
			mp.p2p_listen.stop()
			
			-- send join message to server
			mp.udp_client.send(create_join_server_message(mp.id), mp.host_ip, UDP_SERVER_PORT)
			on_connected(mp.id)
		end)

		flow.delay(2)

		-- if we're still listening there probably is no server on the network
		-- let's create one and wait for connections
		if mp.state == STATE_LISTENING then
			print("BROADCAST")
			mp.state = STATE_HOSTING_GAME
			mp.host_ip = "127.0.0.1"
			
			mp.p2p_listen.stop()
			mp.udp_server = udp.create(function(data, ip, port)
				local stream = trickle.create(data)
				local message_type = stream:readString()
				while message_type and message_type ~= "" do
					handle_message(message_type, stream, ip, port)
					message_type = stream:readString()
				end
			end, UDP_SERVER_PORT)
			mp.p2p_broadcast.broadcast("findme")
			
			-- send a join message to our local server
			mp.udp_client.send(create_join_server_message(mp.id), mp.host_ip, UDP_SERVER_PORT)
			on_connected(mp.id)
		end

		while true do
			-- check for clients that haven't received a heartbeat for a while
			-- and consider those clients disconnected
			-- only the server should be checking for
			if mp.state == STATE_HOSTING_GAME then
				for k,client in pairs(mp.clients) do
					if (socket.gettime() - client.ts) > 5 then
						mp.clients[k] = nil
						send_client_left_message(client.id)
					end
				end
			end
			
			-- send heartbeat for this client to server
			mp.udp_client.send(create_heartbeat_message(mp.id), mp.host_ip, UDP_SERVER_PORT)

			flow.delay(1)
		end
	end)
end

--- Send data to all clients
-- @param data
function M.send(data)
	assert(data)
	send_to_clients(data)
end

--- Send a message to all clients
-- The message will be added to the message stream and sent the next time @{update} is called
-- @param message_type
-- @param message
function M.send_message(message_type, message)
	assert(message_type)
	assert(message)
	assert(mp.message_signatures[message_type])
	mp.stream:writeString(message_type)
	mp.stream:pack(message, mp.message_signatures[message_type])
end

--- Stop the multiplayer module and all underlying systems
function M.stop()
	if mp.p2p_listen then
		mp.p2p_listen.stop()
	end
	if mp.p2p_broadcast then
		mp.p2p_broadcast.stop()
	end
	if mp.udp_server then
		mp.udp_server.destroy()
	end
	if mp.udp_client then
		mp.udp_client.destroy()
	end
end

--- Update the multiplayer module and all underlying systems
-- Any data added to the stream will be sent at this time and the
-- stream will be cleared
-- @param dt
function M.update(dt)
	flow.update(dt)
	
	if mp.p2p_listen then
		mp.p2p_listen.update()
	end
	if mp.p2p_broadcast then
		mp.p2p_broadcast.update()
	end
	if mp.udp_server then
		mp.udp_server.update()
	end
	if mp.udp_client then
		mp.udp_client.update()
	end
	
	local data = tostring(mp.stream)
	if data and #data > 0 then
		send_to_clients(data)
		mp.stream:clear()
	end
end


--- Forward any received on_message calls
-- Needed for the flow module
function M.on_message(message_id, message, sender)
	flow.on_message(message_id, message, sender)
end


return M