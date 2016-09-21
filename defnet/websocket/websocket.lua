require('defnet.websocket.websocket.client_sync')
local frame = require'defnet.websocket.websocket.frame'
local client = require'defnet.websocket.websocket.client'

return {
  client = client,
  CONTINUATION = frame.CONTINUATION,
  TEXT = frame.TEXT,
  BINARY = frame.BINARY,
  CLOSE = frame.CLOSE,
  PING = frame.PING,
  PONG = frame.PONG
}
