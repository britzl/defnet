--- Simple Lua based HTTP server
-- This is a really bare bones HTTP server built using LuaSocket. It has a simple routing
-- system and support for unhandled pages.
--
-- @usage
-- 
--	function init(self)
--		self.server = http_server.create(9190)
--		self.server.router.get("/", function()
--			return http_server.html("Hello World")
--		end)
--		self.server.router.get("/foo", function()
--			return http_server.html("bar")
--		end)
--		self.server.router.unhandled(function(method, uri)
--			return http_server.html("Oops, couldn't find that one!", 404)
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

local SERVER_HEADER = "Server: Simple Lua Server v1"

--- Return a properly formatted HTML response with the
-- appropriate response headers set
M.html = {
	header = function(document, status)
		local resp = {
			"HTTP/1.1 " .. (status or "200 OK"),
			SERVER_HEADER,
			"Content-Type: text/html",
			"Content-Length: " .. tostring(#document),
			"",
			""
		}
		return table.concat(resp, "\r\n")
	end,
	response = function(document, status)
		return M.html.header(document, status) .. document
	end
}
setmetatable(M.html, { __call = function(self, document, status) return M.html.response(document, status) end })


--- Returns a properly formatted JSON response with the
-- appropriate response headers set
M.json = {
	header = function(json, status)
		local resp = {
			"HTTP/1.1 " .. (status or "200 OK"),
			SERVER_HEADER,
			"Content-Type: application/json; charset=utf-8",
			"Content-Length: " .. tostring(#json),
			"",
			""
		}
		return table.concat(resp, "\r\n")
	end,
	response = function(json, status)
		return M.json.header(json, status) .. json
	end
}
setmetatable(M.json, { __call = function(self, json, status) return M.json.response(json, status) end })


--- Returns a properly formatted binary file response
-- with the appropriate headers set
M.file = {
	header = function(file, filename, status)
		local resp = {
			"HTTP/1.1 " .. (status or "200 OK"),
			SERVER_HEADER,
			"Content-Type: application/octet-stream",
			"Content-Disposition: attachment; filename=" .. filename,
			"Content-Length: " .. tostring(#file),
			"",
			""
		}
		return table.concat(resp, "\r\n")
	end,
	response = function(file, filename, status)
		return M.file.header(file, filename, status) .. file
	end
}
setmetatable(M.file, { __call = function(self, file, filename, status) return M.file.response(file, filename, status) end })



--- Create a new HTTP server
-- @return Server instance
function M.create(port)
	local instance = {}

	local routes = {}

	local unhandled_route_fn = nil

	local ss = tcp_server.create(port, function(data, ip)
		if not data or #data == 0 then
			return
		end
		local ok, response_or_err = pcall(function()
			local request_line = data[1] or ""
			local method, uri, protocol_version = request_line:match("^(%S+)%s(%S+)%s(%S+)")
			local header_only = (method == "HEAD")
			if header_only then
				method = "GET"
			end
			local response
			if uri then
				for _,route in ipairs(routes) do
					if not route.method or route.method == method then
						local matches = { uri:match(route.pattern) }
						if next(matches) then
							response = route.fn(unpack(matches))
							break
						end
					end
				end
			end
			if not response and unhandled_route_fn then
				response = unhandled_route_fn(method, uri)
			end
			if method == "HEAD" then
				local s, e = response:find("\r\n\r\n")
				if s and e then
					response = response:sub(1, e)
				end
			end
			return response or ""
		end)
		if not ok then
			print(response_or_err)
			return nil
		end
		return response_or_err
	end)

	-- Replace the underlying socket server's receive function
	-- Read lines until end of request
	function ss.receive(conn)
		assert(conn, "You must provide a connection")
		local request = {}
		local buf = ""
		while true do
			local data, err, buf = conn:receive("*l", buf)
			local closed = (err == "closed")
			if closed or (err ~= "timeout" and (not data or data == "\r\n" or data == "")) then
				return request, err
			elseif data then
				table.insert(request, data)
				buf = ""
			end
		end
	end

	instance.router = {}

	--- Route HTTP GET requests matching a specific pattern to a
	-- provided function. The function will receive any matches from
	-- the pattern as it's arguments
	-- TODO Add query arg handling
	-- @param pattern Standard Lua pattern
	-- @param fn Function to call
	function instance.router.get(pattern, fn)
		assert(pattern, "You must provide a route pattern")
		assert(fn, "You must provide a route handler function")
		table.insert(routes, { method = "GET", pattern = pattern, fn = fn })
	end

	--- Route HTTP POST requests matching a specific pattern to a
	-- provided function. The function will receive any matches from
	-- the pattern as it's arguments
	-- TODO Add POST data handling
	-- @param pattern Standard Lua pattern
	-- @param fn Function to call
	function instance.router.post(pattern, fn)
		assert(pattern, "You must provide a route pattern")
		assert(fn, "You must provide a route handler function")
		table.insert(routes, { method = "POST", pattern = pattern, fn = fn })
	end

	--- Route all HTTP requests matching a specific pattern to a
	-- provided function. The function will receive any matches from
	-- the pattern as it's arguments
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
	end

	return instance
end

return M
