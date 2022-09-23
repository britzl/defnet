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
		if uri then
			for _,route in ipairs(routes) do
				if not route.method or route.method == method then
					local matches = { uri:match(route.pattern) }
					if next(matches) then
						return true, route.fn, matches
					end
				end
			end
		end
		return false, unhandled_route_fn
	end

	return instance
end

--- Route HTTP GET requests matching a specific pattern to a
-- provided function.
-- @param router
-- @param pattern Standard Lua pattern
-- @param fn Function to call when this route is matched
function M.get(router, pattern, fn)
	assert(router)
	return router.get(pattern, fn)
end

--- Route HTTP POST requests matching a specific pattern to a
-- provided function.
-- @param router
-- @param pattern Standard Lua pattern
-- @param fn Function to call when this route is matched
function M.post(router, pattern, fn)
	assert(router)
	return router.post(pattern, fn)
end

--- Route all HTTP requests matching a specific pattern to a
-- provided function.
-- @param router
-- @param pattern Standard Lua pattern
-- @param fn Function to call when this route is matched
function M.all(pattern, fn)
	assert(router)
	return router.all(pattern, fn)
end

--- Add a handler for unhandled routes. This is typically where
-- you would return a 404 page
-- @param router
-- @param fn The function to call when an unhandled route is encountered
-- arguments.
function M.unhandled(router, fn)
	assert(router)
	return router.unhandled(fn)
end

--- Match a method and uri with a route.
-- @param router
-- @param method
-- @param uri
-- @return handled Boolean indicating if the route was handled or not
-- @return fn Route function, or the unhandled route function if no route was found
-- @return matches Any matches captured from the route pattern
function M.match(router, method, uri)
	assert(router)
	return router.match(method, uri)
end


return M