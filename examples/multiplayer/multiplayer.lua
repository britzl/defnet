local flow = require "ludobits.m.flow"
local p2p_discovery = require "defnet.p2p_discovery"
local udp_server = require "defnet.udp_server"
local udp_client = require "defnet.udp_client"
local udp = require "defnet.udp"

local trickle = require "examples.multiplayer.trickle"

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
}


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

local leave_server_signature = {}

local heartbeat_signature = {
	{ "id", "string" },
}

M.HEARTBEAT = "HEARTBEAT"
M.CLIENT_JOINED = "CLIENT_JOINED"
M.CLIENT_LEFT = "CLIENT_LEFT"
M.JOIN_SERVER = "JOIN_SERVER"
M.LEAVE_SERVER = "LEAVE_SERVER"


local function get_ip()
	for _,network_card in pairs(sys.get_ifaddrs()) do
		if network_card.up and network_card.address then
			pprint(network_card)
			return network_card.address
		end
	end
	return nil
end


local function find_client(id)
	assert(id, "You must provide an id")
	return mp.clients[id]
end

local function remove_client(id)
	assert(id, "You must provide an id")
	mp.clients[id] = nil
end

local function add_client(ip, port, id)
	assert(ip, "You must provide an ip")
	assert(port, "You must provide a port")
	assert(id, "You must provide an id")
	mp.clients[id] = { ip = ip, port = port, ts = socket.gettime(), id = id }
end

local function refresh_client(id)
	assert(id, "You must provide an id")
	local client = find_client(id)
	if client then
		client.ts = socket.gettime()
	else
		print("unable to find client", id)
	end
end

local function send_to_clients(message, verbose)
	assert(message, "You must provide a message")
	for _,client in pairs(mp.clients) do
		if verbose then print("sending to", client.ip, client.port) end
		mp.udp_client.send(message, client.ip, client.port)
	end
end

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

local function create_leave_server_message()
	local message = trickle.create()
	message:writeString(M.LEAVE_SERVER)
	message:pack({}, leave_server_signature)
	return tostring(message)
end

local function create_heartbeat_message(id)
	assert(id, "You must provide an id")
	local message = trickle.create()
	message:writeString(M.HEARTBEAT)
	message:pack({ id = id }, heartbeat_signature)
	return tostring(message)
end

local function send_client_joined_message(ip, port, id)
	assert(ip, "You must provide an ip")
	assert(port, "You must provide a port")
	assert(id, "You must provide an id")
	send_to_clients(create_client_joined_message(ip, port, id), true)
end

local function send_client_left_message(id)
	assert(id, "You must provide an id")
	send_to_clients(create_client_left_message(id))
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

local function notify_handlers(message_type, stream, from_ip, from_port)
	assert(message_type, "You must provide a message type")
	assert(stream, "You must provide a stream")
	--print("notify handler", message_type, from_ip, from_port)
	if mp.message_handlers[message_type] and mp.message_signatures[message_type] then
		local message = stream:unpack(mp.message_signatures[message_type])
		for _,handler in ipairs(mp.message_handlers[message_type]) do
			handler(message, from_ip, from_port)
		end
	end
end


function M.start(on_connected)
	mp.id = generate_unique_id()
	print("MY ID", mp.id)
	M.register_message(M.JOIN_SERVER, join_server_signature)
	M.register_message(M.LEAVE_SERVER, leave_server_signature)
	M.register_message(M.CLIENT_JOINED, client_joined_signature)
	M.register_message(M.CLIENT_LEFT, client_left_signature)
	M.register_message(M.HEARTBEAT, heartbeat_signature)
	
	M.register_handler(M.CLIENT_JOINED, function(message, from_ip, from_port)
		print("CLIENT_JOINED handler")
		add_client(message.ip, message.port, message.id)
	end)
	M.register_handler(M.CLIENT_LEFT, function(message, from_ip, from_port)
		print("CLIENT_LEFT handler")
		remove_client(message.id)
	end)
	M.register_handler(M.HEARTBEAT, function(message, from_ip, from_port)
		--print("HEARTBEAT handler", from_ip, from_port, message.id)
		refresh_client(message.id)
	end)
	M.register_handler(M.JOIN_SERVER, function(message, from_ip, from_port)
		print("JOIN_SERVER handler", from_ip, from_port, message.id)
		-- notify client of already joined clients
		for _,client in pairs(mp.clients) do
			if client.id ~= message.id then
				mp.udp_client.send(create_client_joined_message(client.ip, client.port, client.id), from_ip, from_port)
			end
		end
		print("JOIN_SERVER adding client")
		add_client(from_ip, from_port, message.id)
		print("JOIN_SERVER send_client_joined_message")
		pprint(mp.clients)
		send_client_joined_message(from_ip, from_port, message.id)
	end)
	M.register_handler(M.LEAVE_SERVER, function(message, from_ip, from_port)
		print("LEAVE_SERVER handler")
		remove_client(message.id)
		send_client_left_message(message.id)
	end)
	
	flow(function()
		-- let's start by listening if there's someone already looking for players
		-- wait for a while and if we don't find a server we start broadcasting
		mp.p2p_listen = p2p_discovery.create(P2P_PORT)
		mp.p2p_broadcast = p2p_discovery.create(P2P_PORT)

		mp.udp_client = udp.create(function(data, ip, port)
			local stream = trickle.create(data)
			local message_type = stream:readString()
			notify_handlers(message_type, stream, ip, port)
		end)
		
		print("LISTEN")
		mp.state = STATE_LISTENING
		mp.p2p_listen.listen("findme", function(ip, port)
			print("Found server", ip, port)
			mp.state = STATE_JOINED_GAME
			mp.host_ip = ip
			mp.p2p_listen.stop()
			
			print("sending join to server")
			mp.udp_client.send(create_join_server_message(mp.id), ip, UDP_SERVER_PORT)
			on_connected(mp.id)
		end)

		flow.delay(2)
		
		if mp.state == STATE_LISTENING then
			print("BROADCAST")
			mp.state = STATE_HOSTING_GAME
			mp.host_ip = "127.0.0.1"
			
			mp.p2p_listen.stop()
			mp.udp_server = udp_server.create(UDP_SERVER_PORT, function(data, ip, port)
				local stream = trickle.create(data)
				local message_type = stream:readString()
				if message_type ~= M.HEARTBEAT then
					print("UDP server received response '" .. message_type .. "'", "from", ip .. ":" .. port)
				end
				notify_handlers(message_type, stream, ip, port)
			end)
			mp.udp_server.start()
			mp.p2p_broadcast.broadcast("findme")
			
			print("hosting server and sending join_server_message to self")
			mp.udp_client.send(create_join_server_message(mp.id), "127.0.0.1", UDP_SERVER_PORT)
			on_connected(mp.id)
			--add_client(mp.udp_client.ip_and_port(), mp.id)
		end
			
		while true do
			-- only the server should be checking
			if mp.state == STATE_HOSTING_GAME then
				for k,client in pairs(mp.clients) do
					if (socket.gettime() - client.ts) > 5 then
						mp.clients[k] = nil
						send_client_left_message(client.id)
					end
				end
			end
			
			mp.udp_client.send(create_heartbeat_message(mp.id), mp.host_ip, UDP_SERVER_PORT)

			flow.delay(1)
		end
	end)
end


function M.send(data)
	send_to_clients(data)
end

function M.send_message(message_type, message)
	assert(message_type)
	assert(message)
	assert(mp.message_signatures[message_type])
	local stream = trickle.create()
	stream:writeString(message_type)
	stream:pack(message, mp.message_signatures[message_type])
	send_to_clients(tostring(stream))
end

function M.stop()
	if mp.p2p_listen then
		mp.p2p_listen.stop()
	end
	if mp.p2p_broadcast then
		mp.p2p_broadcast.stop()
	end
	if mp.udp_server then
		mp.udp_server.stop()
	end
	if mp.udp_client then
		mp.udp_client.destroy()
	end
end


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
end

function M.on_message(message_id, message, sender)
	flow.on_message(message_id, message, sender)
end


return M