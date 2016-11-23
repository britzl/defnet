local flow = require "ludobits.m.flow"
local p2p_discovery = require "defnet.p2p_discovery"
local udp_server = require "defnet.udp_server"
local udp_client = require "defnet.udp_client"

local trickle = require "examples.multiplayer.trickle"

local M = {}

local P2P_PORT = 50000
local UDP_SERVER_PORT = 9192

local mp = {
	stream = trickle.create(),
	clients = {},
	message_signatures = {},
	message_handlers = {},
}


local join_signature = {
	{ "ip", "string" },
	{ "port", "float" },
}


local leave_signature = {
	{ "ip", "string" },
	{ "port", "float" },
}


M.HEARTBEAT = "HEARTBEAT"
M.JOIN = "JOIN"
M.LEAVE = "LEAVE"


local function get_ip()
	for _,network_card in pairs(sys.get_ifaddrs()) do
		if network_card.up and network_card.address then
			pprint(network_card)
			return network_card.address
		end
	end
	return nil
end


local function find_client(ip, port)
	for i,client in pairs(mp.clients) do
		if client.ip == ip and client.port == port then
			return client, i
		end
	end
end

local function remove_client(ip, port)
	print("remove_client", ip, port)
	local client, i = find_client(ip, port)
	if client then
		print("removed client")
		table.remove(mp.clients, i)
	end
end

local function add_client(ip, port)
	print("add_client", ip, port)
	local client = find_client(ip, port)
	if not client then
		print("added client")
		table.insert(mp.clients, { ip = ip, port = port, ts = socket.gettime() })
	end
end

local function refresh_client(ip, port)
	local client = find_client(ip, port)
	if client then
		client.ts = socket.gettime()
	end
end

local function send_to_clients(message)
	print("send_to_clients", message)
	for _,client in pairs(mp.clients) do
		print("sending to", client.ip, client.port)
		mp.udp_server.send(message, client.ip, client.port)
	end
end

local function create_join_message(ip, port)
	local join = trickle.create()
	join:writeString(JOIN)
	join:pack({ ip = ip, port = port }, join_signature)
	return tostring(join)
end

local function create_leave_message(ip, port)
	local leave = trickle.create()
	leave:writeString(LEAVE)
	leave:pack({ ip = ip, port = port }, leave_signature)
	return tostring(leave)
end

local function send_join_message(ip, port)
	send_to_clients(create_join_message(ip, port))
end

local function send_leave_message(ip, port)
	send_to_clients(create_leave_message(ip, port))
end

function M.register_message(message_type, message_signature)
	assert(message_type, "You must provide a message type")
	assert(message_signature, "You must provide a message signature")
	mp.message_signatures[message_type] = message_signature
end

function M.register_handler(message_type, handler_fn)
	assert(message_type, "You must provide a message type")
	mp.message_handlers[message_type] = mp.message_handlers[message_type] or {}
	table.insert(mp.message_handlers[message_type], handler_fn)
end

local function notify_handlers(message_type, stream)
	assert(message_type, "You must provide a message type")
	assert(stream, "You must provide a stream")
	if mp.message_handlers[message_type] and mp.message_signatures[message_type] then
		local message = stream:unpack(mp.message_signatures[message_type])
		for _,handler in ipairs(mp.message_handlers[message_type]) do
			handler(message)
		end
	end
end

function M.start()
	M.register_message(M.JOIN, join_signature)
	M.register_message(M.LEAVE, leave_signature)
	M.register_message(M.HEARTBEAT, {})
	
	M.register_handler(M.JOIN, function(join_message)
		add_client(join_message.ip, join_message.port)
	end)
	M.register_handler(M.LEAVE, function(leave_message)
		remove_client(leave_message.ip, leave_message.port)
	end)
	M.register_handler(M.HEARTBEAT, function(heartbeat_message)
	end)
	
	flow(function()
		-- let's start by listening if there's someone already looking for players
		-- wait for a while and if we don't find a server we start broadcasting
		mp.p2p_listen = p2p_discovery.create(P2P_PORT)
		mp.p2p_broadcast = p2p_discovery.create(P2P_PORT)
		
		print("LISTEN")
		mp.p2p_listen.listen("findme", function(ip, port)
			print("Found server", ip, port)
			mp.server_ip = ip
			mp.p2p_listen.stop()
			
			print("Creating UDP client")
			local data_stream = trickle.create()
			mp.udp_client = udp_client.create(ip, UDP_SERVER_PORT, function(data)
				local stream = trickle.create(data)
				local message_type = stream:readString()
				print("UDP client received response '" .. message_type .. "'")
				notify_handlers(message_type, stream)
			end)
			
			print("Sending join message")
			local join_message, err = create_join_message("", -1)
			mp.udp_client.send(join_message)
		end)

		flow.delay(5)
		
		while mp.server_ip do
			local heartbeat = trickle.create()
			heartbeat:writeString(M.HEARTBEAT)
			mp.udp_client.send(tostring(heartbeat))
			flow.delay(1)
		end
		
		if not mp.server_ip then
			print("BROADCAST")
			mp.p2p_listen.stop()
			mp.udp_server = udp_server.create(UDP_SERVER_PORT, function(data, ip, port)
				if not data or data == "" then
					return
				end
				print("UDP server received ", data, "from", ip .. ":" .. port)
				local stream = trickle.create(data)
				local message_type = stream:readString()
				print("UDP server received response '" .. message_type .. "'")
				if message_type == HEARTBEAT then
					refresh_client(ip, port)
				elseif message_type == JOIN then
					send_join_message(ip, port)
					add_client(ip, port)
					notify_handler(M.JOIN, ip, port)
				elseif message_type == LEAVE then
					remove_client(ip, port)
					send_leave_message(ip, port)
					notify_handler(M.LEAVE, ip, port)
				else
					notify_handler(message_type, tostring(stream))
				end
			end)
			mp.udp_server.start()
			mp.p2p_broadcast.broadcast("findme")
			
			while true do
				for i,client in pairs(mp.clients) do
					if (socket.gettime() - client.ts) > 10 then
						print("trying to remove old client")
						table.remove(mp.clients, i)
						send_leave_message(client.ip, client.port)
						notify_handler(M.LEAVE, client.ip, client.port)
					end
				end
				flow.delay(0.1)
			end
		end
	end)
end


function M.send(data)
	send_to_clients(data)
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
		mp.udp_client.send(tostring(mp.stream))
		mp.udp_client.update()
		mp.stream:clear()
	end
end

function M.on_message(message_id, message, sender)
	flow.on_message(message_id, message, sender)
end


return M