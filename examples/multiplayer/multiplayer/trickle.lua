-- trickle v0.1.0 - Lua bitstream
-- https://github.com/bjornbytes/trickle
-- MIT License

local trickle = {}

local function byteExtract(x, a, b)
  b = b or a
  x = x % (2 ^ (b + 1))
  for i = 1, a do
    x = math.floor(x / 2)
  end
  return x
end

local function byteInsert(x, y, a, b)
  local res = x
  for i = a, b do
    local e = byteExtract(y, i - a)
    if e ~= byteExtract(x, i) then
      res = (e == 1) and res + (2 ^ i) or res - (2 ^ i)
    end
  end
  return res
end

function trickle.create(str)
  local stream = {
    str = str or '',
    byte = nil,
    byteLen = nil
  }

  return setmetatable(stream, trickle)
end

function trickle:truncate()
  if self.byte then
    self.str = self.str .. string.char(self.byte)
    self.byte = nil
    self.byteLen = nil
  end

  return self.str
end

function trickle:clear()
  self.str = ''
  self.byte = nil
  self.byteLen = nil
  return self
end

function trickle:write(x, sig)
  if sig == 'string' then self:writeString(x)
  elseif sig == 'bool' then self:writeBool(x)
  elseif sig == 'float' then self:writeFloat(x)
  else
    local n = sig:match('(%d+)bit')
    self:writeBits(x, n)
  end

  return self
end

function trickle:writeString(string)
  self:truncate()
  string = tostring(string)
  self.str = self.str .. string.char(#string) .. string
end

function trickle:writeBool(bool)
  local x = bool and 1 or 0
  self:writeBits(x, 1)
end

function trickle:writeFloat(float)
  self:writeString(float)
end

function trickle:writeBits(x, n)
  local idx = 0
  repeat
    if not self.byte then self.byte = 0 self.byteLen = 0 end
    local numWrite = math.min(n, (7 - self.byteLen) + 1)
    local toWrite = byteExtract(x, idx, idx + (numWrite - 1))
    self.byte = byteInsert(self.byte, toWrite, self.byteLen, self.byteLen + (numWrite - 1))
    self.byteLen = self.byteLen + numWrite

    if self.byteLen == 8 then
      self.str = self.str .. string.char(self.byte)
      self.byte = nil
      self.byteLen = nil
    end

    n = n - numWrite
    idx = idx + numWrite
  until n == 0
end

function trickle:read(kind)
  if kind == 'string' then return self:readString()
  elseif kind == 'bool' then return self:readBool()
  elseif kind == 'float' then return self:readFloat()
  else
    local n = tonumber(kind:match('(%d+)bit'))
    return self:readBits(n)
  end
end

function trickle:readString()
  if self.byte then
    self.str = self.str:sub(2)
    self.byte = nil
    self.byteLen = nil
  end
  local len = self.str:byte(1)
  local res = ''
  if len then
    self.str = self.str:sub(2)
    res = self.str:sub(1, len)
    self.str = self.str:sub(len + 1)
  end
  return res
end

function trickle:readBool()
  return self:readBits(1) > 0
end

function trickle:readFloat()
  return tonumber(self:readString())
end

function trickle:readBits(n)
  local x = 0
  local idx = 0
  while n > 0 do
    if not self.byte then self.byte = self.str:byte(1) or 0 self.byteLen = 0 end
    local numRead = math.min(n, (7 - self.byteLen) + 1)
    x = x + (byteExtract(self.byte, self.byteLen, self.byteLen + (numRead - 1)) * (2 ^ idx))
    self.byteLen = self.byteLen + numRead

    if self.byteLen == 8 then
      self.str = self.str:sub(2)
      self.byte = nil
      self.byteLen = nil
    end

    n = n - numRead
    idx = idx + numRead
  end

  return x
end

function trickle:pack(data, signature)
  local keys
  if signature.delta then
    keys = {}
    for _, key in ipairs(signature.delta) do
      if type(key) == 'table' then
        local has = 0
        for i = 1, #key do
          if data[key[i]] ~= nil then
            keys[key[i]] = true
            has = has + 1
          else
            keys[key[i]] = false
          end
        end
        if has == 0 then self:write(0, '1bit')
        elseif has == #key then self:write(1, '1bit')
        else error('Only part of message delta group "' .. table.concat(key, ', ') .. '" was provided.') end
      else
        self:write(data[key] ~= nil and 1 or 0, '1bit')
        keys[key] = data[key] ~= nil and true or false
      end
    end
  end

  for _, sig in ipairs(signature) do
    if not keys or keys[sig[1]] ~= false then
      if type(sig[2]) == 'table' then
        self:write(#data[sig[1]], '4bits')
        for i = 1, #data[sig[1]] do self:pack(data[sig[1]][i], sig[2]) end
      else
        self:write(data[sig[1]], sig[2])
      end
    end
  end
end

function trickle:unpack(signature)
  local keys
  if signature.delta then
    keys = {}
    for i = 1, #signature.delta do
      local val = self:read('1bit') > 0
      if type(signature.delta[i]) == 'table' then
        for j = 1, #signature.delta[i] do keys[signature.delta[i][j]] = val end
      else
        keys[signature.delta[i]] = val
      end
    end
  end

  local data = {}
  for _, sig in ipairs(signature) do
    if not keys or keys[sig[1]] ~= false then
      if type(sig[2]) == 'table' then
        local ct = self:read('4bits')
        data[sig[1]] = {}
        for i = 1, ct do table.insert(data[sig[1]], self:unpack(sig[2])) end
      else
        data[sig[1]] = self:read(sig[2])
      end
    end
  end
  return data
end

trickle.__tostring = trickle.truncate
trickle.__index = trickle

return { create = trickle.create }
