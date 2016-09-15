local M = {}

function M.create(client)
	assert(client, "You must provide a TCP client")

	local instance = {}
	
	local queue = {}
	
	function instance.clear()
		queue = {}
	end
	
	function instance.add(data)
		assert(data, "You must provide some data")
		table.insert(queue, { data = data, bytes_sent = 0 })
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