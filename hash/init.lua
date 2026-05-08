-- hash: SHA-256 and HMAC-SHA256 in pure Lua.
--
-- Originally lifted from the Postroom project's crypto.lua, validated against
-- FIPS 180-4 (SHA-256) and RFC 4231 (HMAC-SHA256) test vectors.

local M = {}

M.VERSION = "1.0.0"

-- Bit operations: prefer bit32 (CC default), fall back to native bitops on Lua 5.3+.
local band, bor, bxor, bnot, lshift, rshift, rrotate

if bit32 then
  band   = bit32.band
  bor    = bit32.bor
  bxor   = bit32.bxor
  bnot   = bit32.bnot
  lshift = bit32.lshift
  rshift = bit32.rshift
  rrotate = bit32.rrotate
else
  local ok, ops = pcall(load([[
    local function vfold(op, a, ...)
      local n = select("#", ...)
      for i = 1, n do a = op(a, (select(i, ...))) end
      return a & 0xffffffff
    end
    return {
      band   = function(...) return vfold(function(x,y) return x & y end, ...) end,
      bor    = function(...) return vfold(function(x,y) return x | y end, ...) end,
      bxor   = function(...) return vfold(function(x,y) return x ~ y end, ...) end,
      bnot   = function(a) return (~a) & 0xffffffff end,
      lshift = function(a, n) return (a << n) & 0xffffffff end,
      rshift = function(a, n) return (a & 0xffffffff) >> n end,
      rrotate = function(a, n)
        a = a & 0xffffffff
        return ((a >> n) | (a << (32 - n))) & 0xffffffff
      end,
    }
  ]]))
  if not ok or type(ops) ~= "table" then
    error("hash: no bit32 and no native bitops available")
  end
  band, bor, bxor, bnot = ops.band, ops.bor, ops.bxor, ops.bnot
  lshift, rshift, rrotate = ops.lshift, ops.rshift, ops.rrotate
end

-- Hex helpers.
local function toHex(s)
  return (s:gsub(".", function(c) return string.format("%02x", string.byte(c)) end))
end

local function fromHex(s)
  return (s:gsub("..", function(h) return string.char(tonumber(h, 16)) end))
end

M.toHex = toHex
M.fromHex = fromHex

-- SHA-256.
local SHA256_K = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function sha256_pad(msg)
  local len = #msg
  local bits = len * 8
  local pad = "\128"
  local extra = (56 - (len + 1)) % 64
  pad = pad .. string.rep("\0", extra)
  pad = pad .. "\0\0\0\0"
  pad = pad .. string.char(
    band(rshift(bits, 24), 0xff),
    band(rshift(bits, 16), 0xff),
    band(rshift(bits, 8), 0xff),
    band(bits, 0xff)
  )
  return msg .. pad
end

local function sha256_words(msg)
  local words = {}
  local n = #msg / 4
  for i = 1, n do
    local p = (i - 1) * 4
    local b1, b2, b3, b4 = string.byte(msg, p + 1, p + 4)
    words[i] = lshift(b1, 24) + lshift(b2, 16) + lshift(b3, 8) + b4
  end
  return words
end

function M.sha256(msg)
  local padded = sha256_pad(msg)
  local words = sha256_words(padded)
  local nblocks = #words / 16

  local h = {
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  }

  local w = {}

  for block = 0, nblocks - 1 do
    for t = 1, 16 do
      w[t] = words[block * 16 + t]
    end
    for t = 17, 64 do
      local s0 = bxor(rrotate(w[t-15], 7), rrotate(w[t-15], 18), rshift(w[t-15], 3))
      local s1 = bxor(rrotate(w[t-2], 17), rrotate(w[t-2], 19), rshift(w[t-2], 10))
      w[t] = band(w[t-16] + s0 + w[t-7] + s1, 0xffffffff)
    end

    local a, b, c, d, e, f, g, hh = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]

    for t = 1, 64 do
      local S1 = bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
      local ch = bxor(band(e, f), band(bnot(e), g))
      local temp1 = band(hh + S1 + ch + SHA256_K[t] + w[t], 0xffffffff)
      local S0 = bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
      local maj = bxor(band(a, b), band(a, c), band(b, c))
      local temp2 = band(S0 + maj, 0xffffffff)

      hh = g
      g = f
      f = e
      e = band(d + temp1, 0xffffffff)
      d = c
      c = b
      b = a
      a = band(temp1 + temp2, 0xffffffff)
    end

    h[1] = band(h[1] + a, 0xffffffff)
    h[2] = band(h[2] + b, 0xffffffff)
    h[3] = band(h[3] + c, 0xffffffff)
    h[4] = band(h[4] + d, 0xffffffff)
    h[5] = band(h[5] + e, 0xffffffff)
    h[6] = band(h[6] + f, 0xffffffff)
    h[7] = band(h[7] + g, 0xffffffff)
    h[8] = band(h[8] + hh, 0xffffffff)
  end

  local out = {}
  for i = 1, 8 do
    local v = h[i]
    out[i] = string.char(
      band(rshift(v, 24), 0xff),
      band(rshift(v, 16), 0xff),
      band(rshift(v, 8), 0xff),
      band(v, 0xff)
    )
  end
  return table.concat(out)
end

function M.sha256hex(msg)
  return toHex(M.sha256(msg))
end

-- HMAC-SHA256.
local SHA256_BLOCK = 64

function M.hmac_sha256(key, msg)
  if #key > SHA256_BLOCK then
    key = M.sha256(key)
  end
  if #key < SHA256_BLOCK then
    key = key .. string.rep("\0", SHA256_BLOCK - #key)
  end

  local opad, ipad = {}, {}
  for i = 1, SHA256_BLOCK do
    local b = string.byte(key, i)
    opad[i] = string.char(bxor(b, 0x5c))
    ipad[i] = string.char(bxor(b, 0x36))
  end
  opad = table.concat(opad)
  ipad = table.concat(ipad)

  return M.sha256(opad .. M.sha256(ipad .. msg))
end

function M.hmac_sha256_hex(key, msg)
  return toHex(M.hmac_sha256(key, msg))
end

return M
