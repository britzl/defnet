--- Simple Lua based HTTP server
-- This is a really bare bones HTTP server built using LuaSocket. It has a simple routing
-- system and support for unhandled pages.
--
-- @usage
-- 
--	function init(self)
--		self.server = http_server.create(9190)
--		self.server.router.get("^/$", function(matches, stream, headers, body)
--			return http_server.html("Hello World")
--		end)
--		self.server.router.get("^/foo/(.*)$", function(matches, stream, headers, body)
--			return http_server.html("bar" .. matches[1])
--		end)
--		self.server.router.get("^/stream$", function(matches, stream, headers, body)
--			return function()
--				stream("some data")
--			end
--		end)
--		self.server.router.unhandled(function(method, uri, stream, headers, body)
--			return http_server.html("Oops, couldn't find that one!", http_server.NOT_FOUND)
--		end)
--		self.server.start()
--	end
--	
--	function final(self)
--		self.server.destroy()
--	end
--	
--	function update(self, dt)
--		self.server.update()
--	end
--

local tcp_server = require "defnet.tcp_server"

local M = {}


M.OK = "200 OK"
M.NOT_FOUND = "404 Not Found"


-- receive data on a socket, according to the provided pattern
local function receive(conn, pattern)
	local buf = ""
	while true do
		local data, err, partial = conn:receive(pattern, buf)
		if err == "closed" then
			return data, err
		end
		if partial and partial ~= "" then
			buf = buf .. partial
		elseif data then
			return data, err
		end
	end
end


-- receive a line of data on a socket
local function receive_line(conn)
	return receive(conn, "*l")
end


-- receive the request part (line and headers)
local function receive_request(conn)
	assert(conn, "You must provide a connection")
	local request = {}
	local buf = ""
	while true do
		local line, err = receive_line(conn)
		if err == "closed" or line == "" then
			return request, err
		end
		request[#request + 1] = line
	end
end


-- receive the message body
local function receive_message_body(conn, method, headers)
	assert(conn, "You must provide a connection")
	assert(method, "You must provide a method")
	assert(headers, "You must provide headers")

	local body = nil
	if method == "POST" or method == "PUT" then
		local content_length = headers["content-length"] and tonumber(headers["content-length"]) or 0
		if content_length > 0 then
			body = receive(conn, content_length)
		end
	end
	return body
end


-- parse the request line into method, uri and protocol
local function parse_request_line(request_line)
	assert(request_line, "You must provide a request line")
	local method, uri, protocol_version = request_line:match("^(%S+)%s(%S+)%s(%S+)")
	return method, uri, protocol_version
end


-- parse headers, splitting them into key value pairs
local function parse_headers(request)
	assert(request, "You must provide a request")
	local headers = {}
	for _,line in ipairs(request) do
		local header, value = line:match("^(%S+):%s-(%S+)")
		headers[header:lower()] = value
	end
	return headers
end


--- Create a new HTTP server
-- @return Server instance
function M.create(port)
	local instance = {
		access_control = "*",		-- set to nil to not enable CORS
		server_header = "Server: Simple Lua Server v1",
	}

	local routes = {}
	
	local request_handlers = {}

	local unhandled_route_fn = nil

	local ss = tcp_server.create(port, function() end)

	-- Replace the underlying socket server's receive function
	-- Read lines until end of request
	function ss.receive(conn)
		assert(conn, "You must provide a connection")

		local ok, err = pcall(function()
			local request, err = receive_request(conn)
			if err then
				return err
			end

			local request_line = table.remove(request, 1) or ""
			local method, uri, protocol_version = parse_request_line(request_line)
			local header_only = (method == "HEAD")
			if header_only then
				method = "GET"
			end
			
			local headers = parse_headers(request)
			local message_body = receive_message_body(conn, method, headers)

			-- function for streaming chunked content
			local stream_fn = function(response, close)
				ss.send(response, conn)
				return close ~= false
			end
			
			-- handle request and get a response
			local response
			if uri then
				for _,route in ipairs(routes) do
					if not route.method or route.method == method then
						local matches = { uri:match(route.pattern) }
						if next(matches) then
							response = route.fn(matches, stream_fn, headers, message_body)
							break
						end
					end
				end
			end

			-- unhandled response
			if not response and unhandled_route_fn then
				response = unhandled_route_fn(method, uri, stream_fn, headers, message_body)
			end

			-- send response
			if response then
				if type(response) == "function" then
					table.insert(request_handlers, response)
				else
					stream_fn(response)
				end
			end
		end)
		if not ok then
			print(err)
		end
		return nil, err
	end

	instance.router = {}

	--- Route HTTP GET requests matching a specific pattern to a
	-- provided function.
	-- The function will receive a list of matches from the pattern as
	-- it's first arguments. The second argument is a stream function in case
	-- the response should be streamed.
	-- The function must either return the full response or a function that
	-- can be called multiple times to get more data to return.
	-- @param pattern Standard Lua pattern
	-- @param fn Function to call
	function instance.router.get(pattern, fn)
		assert(pattern, "You must provide a route pattern")
		assert(fn, "You must provide a route handler function")
		table.insert(routes, { method = "GET", pattern = pattern, fn = fn })
	end
	
	--- Route HTTP POST requests matching a specific pattern to a
	-- provided function.
	-- The function will receive a list of matches from the pattern as
	-- it's first arguments. The second argument is a stream function in case
	-- the response should be streamed.
	-- The function must either return the full response or a function that
	-- can be called multiple times to get more data to return.
	-- @param pattern Standard Lua pattern
	-- @param fn Function to call
	function instance.router.post(pattern, fn)
		assert(pattern, "You must provide a route pattern")
		assert(fn, "You must provide a route handler function")
		table.insert(routes, { method = "POST", pattern = pattern, fn = fn })
	end

	--- Route all HTTP requests matching a specific pattern to a
	-- provided function.
	-- The function will receive a list of matches from the pattern as
	-- it's first arguments. The second argument is a stream function in case
	-- the response should be streamed.
	-- The function must either return the full response or a function that
	-- can be called multiple times to get more data to return.
	-- @param pattern Standard Lua pattern
	-- @param fn Function to call
	function instance.router.all(pattern, fn)
		assert(pattern, "You must provide a route pattern")
		assert(fn, "You must provide a route handler function")
		table.insert(routes, { method = nil, pattern = pattern, fn = fn })
	end

	--- Add a handler for unhandled routes. This is typically where
	-- you would return a 404 page
	-- @param fn The function to call when an unhandled route is encountered. The
	-- function will receive the method and uri of the unhandled route as
	-- arguments.
	function instance.router.unhandled(fn)
		assert(fn, "You must provide an unhandled route function")
		unhandled_route_fn = fn
	end

	--- Start the server
	-- @return success
	-- @return error_message
	function instance.start()
		return ss.start()
	end

	--- Stop the server
	function instance.stop()
		ss.stop()
	end

	--- Stop the server
	function instance.update()
		ss.update()
		for k,handler in pairs(request_handlers) do
			print("calling request handler")
			if not handler() then
				print("removing request handler")
				request_handlers[k] = nil
			end
		end
	end

	--- Return a properly formatted HTML response with the
	-- appropriate response headers set
	-- If the document is omitted the response is assumed to be
	-- chunked 
	instance.html = {
		header = function(document, status)
			local headers = {
				"HTTP/1.1 " .. (status or M.OK),
				instance.server_header,
				"Content-Type: text/html",
				document and ("Content-Length: " .. tostring(#document)) or "Transfer-Encoding: chunked",
			}
			if instance.access_control then
				headers[#headers + 1] = "Access-Control-Allow-Origin: " .. instance.access_control
			end
			headers[#headers + 1] = ""
			headers[#headers + 1] = ""
			return table.concat(headers, "\r\n")
		end,
		response = function(document, status)
			return instance.html.header(document, status) .. (document or "")
		end
	}
	setmetatable(instance.html, { __call = function(_, document, status) return instance.html.response(document, status) end })

	--- Returns a properly formatted JSON response with the
	-- appropriate response headers set
	-- If the JSON data is omitted the response is assumed to be
	-- chunked 
	instance.json = {
		header = function(json, status)
			local headers = {
				"HTTP/1.1 " .. (status or M.OK),
				instance.server_header,
				"Content-Type: application/json; charset=utf-8",
				json and ("Content-Length: " .. tostring(#json)) or "Transfer-Encoding: chunked",
			}
			if instance.access_control then
				headers[#headers + 1] = "Access-Control-Allow-Origin: " .. instance.access_control
			end
			headers[#headers + 1] = ""
			headers[#headers + 1] = ""
			return table.concat(headers, "\r\n")
		end,
		response = function(json, status)
			return instance.json.header(json, status) .. (json or "")
		end
	}
	setmetatable(instance.json, { __call = function(_, json, status) return instance.json.response(json, status) end })

	--- Returns a properly formatted binary file response
	-- with the appropriate headers set
	-- If the file contents is omitted the response is assumed to be
	-- chunked 
	instance.file = {
		header = function(file, filename, status)
			local headers = {
				"HTTP/1.1 " .. (status or M.OK),
				instance.server_header,
				"Content-Type: application/octet-stream",
				"Content-Disposition: attachment; filename=" .. filename,
				file and ("Content-Length: " .. tostring(#file)) or "Transfer-Encoding: chunked",
			}
			if instance.access_control then
				headers[#headers + 1] = "Access-Control-Allow-Origin: " .. instance.access_control
			end
			headers[#headers + 1] = ""
			headers[#headers + 1] = ""
			return table.concat(headers, "\r\n")
		end,
		response = function(file, filename, status)
			return instance.file.header(file, filename, status) .. (file or "")
		end
	}
	setmetatable(instance.file, { __call = function(_, file, filename, status) return instance.file.response(file, filename, status) end })

	--- Create a properly formatted chunk
	-- @param data
	-- @return chunk
	function instance.to_chunk(data)
		return ("%x\r\n%s\r\n"):format(#data, data)
	end
	return instance
end

return M
