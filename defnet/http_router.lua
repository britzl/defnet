local M = {}

--- Create a router instance
-- @return instance
function M.create()

	local routes = {}

	local unhandled_route_fn = nil
	
	local instance = {}

	function instance.get(pattern, fn)
		assert(pattern, "You must provide a route pattern")
		assert(fn, "You must provide a route handler function")
		table.insert(routes, { method = "GET", pattern = pattern, fn = fn })
	end

	function instance.post(pattern, fn)
		assert(pattern, "You must provide a route pattern")
		assert(fn, "You must provide a route handler function")
		table.insert(routes, { method = "POST", pattern = pattern, fn = fn })
	end

	function instance.all(pattern, fn)
		assert(pattern, "You must provide a route pattern")
		assert(fn, "You must provide a route handler function")
		table.insert(routes, { method = nil, pattern = pattern, fn = fn })
	end

	function instance.unhandled(fn)
		assert(fn, "You must provide an unhandled route function")
		unhandled_route_fn = fn
	end

	function instance.match(method, uri)
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
		
		return response
	end

	return instance
end

--- Route HTTP GET requests matching a specific pattern to a
-- provided function.
-- The function will receive a list of matches from the pattern as
-- it's first arguments. The second argument is a stream function in case
-- the response should be streamed.
-- The function must either return the full response or a function that
-- can be called multiple times to get more data to return.
-- @param router
-- @param pattern Standard Lua pattern
-- @param fn Function to call
function M.get(router, pattern, fn)
	assert(router)
	return router.get(pattern, fn)
end

--- Route HTTP POST requests matching a specific pattern to a
-- provided function.
-- The function will receive a list of matches from the pattern as
-- it's first arguments. The second argument is a stream function in case
-- the response should be streamed.
-- The function must either return the full response or a function that
-- can be called multiple times to get more data to return.
-- @param router
-- @param pattern Standard Lua pattern
-- @param fn Function to call
function M.post(router, pattern, fn)
	assert(router)
	return router.post(pattern, fn)
end

--- Route all HTTP requests matching a specific pattern to a
-- provided function.
-- The function will receive a list of matches from the pattern as
-- it's first arguments. The second argument is a stream function in case
-- the response should be streamed.
-- The function must either return the full response or a function that
-- can be called multiple times to get more data to return.
-- @param router
-- @param pattern Standard Lua pattern
-- @param fn Function to call
function M.all(pattern, fn)
	assert(router)
	return router.all(pattern, fn)
end

--- Add a handler for unhandled routes. This is typically where
-- you would return a 404 page
-- @param router
-- @param fn The function to call when an unhandled route is encountered. The
-- function will receive the method and uri of the unhandled route as
-- arguments.
function M.unhandled(router, fn)
	assert(router)
	return router.unhandled(fn)
end

--- Match a method and uri with a route. If no match exists the unhandled route function is used
-- @param router
-- @param method
-- @param uri
-- @return response
function M.match(router, method, uri)
	assert(router)
	return router.match(method, uri)
end


return M