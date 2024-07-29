local M = {}

local BxFF000000 = bit.lshift(255, 24)
local Bx00FF0000 = bit.lshift(255, 16)
local Bx0000FF00 = bit.lshift(255, 8)
local Bx000000FF = bit.lshift(255, 0)

local function encode_size(data)
	local length = #data
	-- split length into four bytes
	local b1 = bit.rshift(bit.band(length, BxFF000000), 24)
	local b2 = bit.rshift(bit.band(length, Bx00FF0000), 16)
	local b3 = bit.rshift(bit.band(length, Bx0000FF00), 8)
	local b4 = bit.rshift(bit.band(length, Bx000000FF), 0)
	-- convert the four bytes to a string
	return string.char(b1, b2, b3, b4)
end

local function decode_size(data)
	local b1, b2, b3, b4 = data:byte(1, 4)
	return bit.lshift(b1, 24) + bit.lshift(b2, 16) + bit.lshift(b3, 8) + b4
end

--- Create a TCP data queue instance
-- @param client The TCP client used when sending and receiving data
-- @param options Table with data options. Accepted options:
--   * chunk_size - The maximum size of any data that will be
--     sent. Defaults to 10000. If data is added that is larger than this value
--     it will be split into multiple "chunks". Note that there is no guarantee
--     that all data in a chunk is sent in a single call. Individual chunks may
--     still be split into multiple TCP send calls.
--   * binary - Data that is received and sent will be prefixed with the data
--     length. Use this mode when working with binary data (including 0x00).
-- @return The created data queue instance
function M.create(client, options)
	assert(client, "You must provide a TCP client")

	local chunk_size = options and options.chunk_size or 10000
	local binary = options and options.binary or false

	local instance = {}

	local send_queue = {}
	local received_data = ""
	local received_data_size = nil

	function instance.clear()
		send_queue = {}
	end

	function instance.add(data)
		assert(data, "You must provide some data")
		if binary then
			data = encode_size(data) .. data
		else
			data = data
		end
		for i=1,#data,chunk_size do
			table.insert(send_queue, { data = data:sub(i, i + chunk_size - 1), sent_index = 0 })
		end
	end

	function instance.send()
		while true do
			local first = send_queue[1]
			if not first then
				return true
			end

			local sent_index, err, sent_index_on_err = client:send(first.data, first.sent_index + 1, #first.data)
			if err then
				first.sent_index = sent_index_on_err
				return false, err
			end

			first.sent_index = sent_index
			if first.sent_index == #first.data then
				table.remove(send_queue, 1)
			end
		end
	end


	local function receive_binary()
		-- calculate number of bytes to receive
		-- 1) size: read 4 bytes to get the size of the data
		-- 2) data: read the data itself
		local n = nil
		if not received_data_size then
			n = 4 - #received_data
		else
			n = received_data_size - #received_data
		end

		-- receive some bytes (partially or all)
		local data, err, partial = client:receive(n)
		if partial then
			received_data = received_data .. partial
		end

		-- exepected number of bytes received
		if data then
			data = received_data .. data
			received_data = ""
			if not received_data_size then
				received_data_size = decode_size(data)
			else
				received_data_size = nil
				return data, nil
			end
		elseif err == "closed" then
			return nil, err
		end
		return nil, nil
	end

	local function receive_lines()
		-- receive some bytes (partially or all)
		local data, err, partial = client:receive("*l")
		if partial then
			received_data = received_data .. partial
		end

		-- all bytes received?
		if data then
			print("received ALL data")
			data = received_data .. data
			received_data = ""
			return data, nil
		elseif err == "closed" then
			return nil, err
		end
		return nil, nil
	end

	function instance.receive()
		if binary then
			return receive_binary()
		else
			return receive_lines()
		end
	end

	return instance
end


return M
