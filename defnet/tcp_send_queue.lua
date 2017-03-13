local M = {}

--- Create a TCP send queue
-- @param client The TCP client used when sending data
-- @param chunk_size The maximum size of any data that will be
-- sent. Defaults to 10000. If data is added that is larger than this value it will
-- be split into multiple "chunks". Note that there is no guarantee
-- that all data in a chunk is sent in a single call. Individual
-- chunks may still be split into multiple TCP send calls.
-- @return The created queue instance
function M.create(client, chunk_size)
	assert(client, "You must provide a TCP client")

	chunk_size = chunk_size or 10000

	local instance = {}
	
	local queue = {}
	
	function instance.clear()
		queue = {}
	end
	
	function instance.add(data)
		assert(data, "You must provide some data")
		for i=1,#data,chunk_size do
			table.insert(queue, { data = data:sub(i, i + chunk_size - 1), bytes_sent = 0 })
		end
	end
	
	function instance.send()
		local first = queue[1]
		if not first then
			return
		end
		
		local sent, err = client:send(first.data, 1 + first.bytes_sent, #first.data)
		if not err then
			first.bytes_sent = first.bytes_sent + sent
			if first.bytes_sent == #first.data then
				table.remove(queue, 1)
			end
		end
	end
	
	return instance
end


return M