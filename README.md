# DefNet
Defold Networking modules and examples, provided as a Defold library project.

## Preface
I often get questions about networking in Defold from our forum users. Sometimes it is as easy as "How do I make an HTTP call?" and I can point to the documentation for [http.request()](http://www.defold.com/ref/http/#http.request:url-method-callback--headers---post_data---options-) and everyone is happy. Other times the questions are more complex (often relating to socket connections) and in those cases the Defold documentation isn't enough.

Luckily for us Defold comes bundles with the excellent [LuaSocket](http://w3.impa.br/~diego/software/luasocket/home.html) library. With LuaSocket it is fairly trivial to create TCP and UDP sockets. Here's a bare-bones TCP socket example:

	local client = socket.tcp()
	client:connect(server_ip, server_port)
	client:settimeout(0) -- non blocking socket
	client:send(data) -- send data like this
	local response = client:receive(*l) -- receive a "line" of data like this

The above snippet of code, some reading of the LuaSocket documentation and perhaps a couple of Google searches will get you quite far, but some concepts like peer to peer discovery is a bit trickier. The goal with this project is to collect some useful Lua networking modules that can be used either as-is or modified to suit your needs.

## Requirements
Most of the code can be used in a stand-alone version of Lua with the only requirement being LuaSocket. In the modules provided here I `require("builtins.scripts.socket")` which is equivalent to [socket.lua from the LuaSocket library](https://github.com/diegonehab/luasocket/blob/master/src/socket.lua).

## Installation
You can use the modules from this project in your own project by adding this project as a [Defold library dependency](http://www.defold.com/manuals/libraries/). Open your game.project file and in the `dependencies` field under `project` add:

	https://github.com/britzl/defnet/archive/master.zip

Or point to the ZIP file of a [specific release](https://github.com/britzl/defnet/releases).

## Included modules
### Peer to peer discovery
The `defnet/p2p_discovery` module can be used to perform peer to peer discovery using UDP sockets. The basic idea is that an app sets itself up as discoverable and starts sending a broadcast message on the network. Other clients can listen for broadcasted messages and get the IP of the app that wishes to be discovered. This is how an app can set itself up as discoverable:

	local p2p_discovery = require "defnet.p2p_discovery"
	local PORT = 50000

	function init(self)
		self.p2p = p2p_discovery.create(PORT)
		self.p2p.broadcast("findme")
	end

	function update(self, dt)
		self.p2p.update()
	end

And this is how another app would discover it:

	local p2p_discovery = require "defnet.p2p_discovery"
	local PORT = 50000

	function init(self)
		self.p2p = p2p_discovery.create(PORT)
		self.p2p.listen("findme", function(ip, port)
			print("Found server", ip, port)
		end)
	end

	function update(self, dt)
		self.p2p.update()
	end

Once discovery has been completed communication can take place over a socket of some kind.

### TCP socket server
The `defnet/tcp_server` module can be used to create a TCP socket server that accepts incoming TCP client connections and can send and receive data. Example:

	local function on_data(data, ip)
		print("Received", data, "from", ip)
		return "My response"
	end

	local function on_client_connected(ip)
		print("Client", ip, "connected")
	end

	local function on_client_disconnected(ip)
		print("Client", ip, "disconnected")
	end

	function init(self)
		self.server = tcp_server.create(8190, on_data, on_client_connected, on_client_disconnected)
		self.server.start()
	end

	function final(self)
		self.server.stop()
	end

	function update(self, dt)
		self.server.update()
	end

### TCP socket client
The `defnet/tcp_client` module can be used to create a TCP socket client and connect it. Example:

	local tcp_client = require "defnet.tcp_client"
	local IP = "localhost" -- perhaps get IP from P2P discovery?
	local PORT = 9189

	function init(self)
		self.client = tcp_client.create(IP, PORT, function(data)
		print("TCP client received data " .. data)
	end

	function update(self, dt)
		self.client.update()
	end

	function on_input(self, action_id, action)
		-- on some condition do:
		self.client.send("Sending this to the server\n")
	end
	
### UDP client
The `defnet/udp` module can be used to create an UDP connection. The connection can either be unconnected and send and receive data from any IP and port or connected and bound to a specific port and/or send only to a specific IP and port.

The module will simply forward any incoming data to a callback function. Example:

	local udp = require "defnet.udp"

	function init(self)
		self.udp_server = udp.create(function(data, ip, port)
			print("Received data", data, ip, port)
		end, 9999)

		self.udp1 = udp.create(function(data, ip, port)
			print("Received data", data, ip, port)
		end, nil, "127.0.0.1", 9999)
		self.udp1.send("foobar to server")

		self.udp2 = udp.create(function(data, ip, port)
			print("Received data", data, ip, port)
		end)
		self.udp2.send("foobar to server", "127.0.0.1", 9990)
	end

	function final(self)
		self.udp_server.destroy()
		self.udp1.destroy()
		self.udp2.destroy()
	end

	function update(self, dt)
		self.udp_server.update()
		self.udp1.update()
		self.udp2.update()
	end

### HTTP server
Since it's possible to create a TCP socket it's also possible to build more advanced things such as HTTP servers. The `defnet/http_server` module can be used to create a simple HTTP server with basic page routing support. Example:

	local http_sever = require "defnet/http_sever"
	local PORT = 9189

	function init(self)
		self.hs = http_server.create(PORT)
		self.hs.router.get("/foo/(.*)$", function(what)
			return http_server.html("boo" .. what)
		end)
		self.hs.router.get("/$", function()
			return http_server.html("Hello World")
		end)
		self.hs.router.unhandled(function(method, uri)
			return http_server.html("Oops, couldn't find that one!", 404)
		end)
		self.hs.start()
	end

	function update(self, dt)
		self.hs.update()
	end

### WebSockets
WebSocket connections are possible using the [lua-websocket](https://github.com/lipp/lua-websockets) project. There is however a couple of things to keep in mind when using a WebSocket in Defold. Please refer to the [README](defnet/websocket/README.md) for more details.

## Example
There's an example project in the [example folder](https://github.com/britzl/defnet/tree/master/example).

## Found a bug? Made an improvement?
There are probably bugs. Please report them!

Did you improve some of the code? Please create a Pull Request!

## License
This library is released under the same [Terms and Conditions as the Defold editor and service itself](http://www.defold.com/about-terms/).

## Credits
Assets in the example project are made by [Kenney](http://www.kenney.nl)
