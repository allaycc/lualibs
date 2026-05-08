-- httpkit tests using a fake http module.
package.path = package.path .. ";../?/init.lua;../?.lua"

-- Fake http module. Tests can program responses by setting `responses` and
-- `errors` keyed on URL.
local responses = {}      -- url -> body
local statuses = {}       -- url -> http status (default 200)
local errors = {}         -- url -> err message (failure case)
local call_counts = {}    -- url -> number of times called

_G.http = {
  checkURL = function(url) return true end,
  get = function(opts)
    local url = type(opts) == "string" and opts or opts.url
    call_counts[url] = (call_counts[url] or 0) + 1
    if errors[url] then
      return nil, errors[url]
    end
    local status = statuses[url] or 200
    local body = responses[url] or ""
    return {
      readAll = function() return body end,
      getResponseCode = function() return status end,
      close = function() end,
    }
  end,
}

-- Stub os.sleep so retries don't actually wait.
_G.os = _G.os or {}
_G.os.sleep = function(_) end

local httpkit = require("httpkit")

local total, failed = 0, 0
local function check(name, expected, actual)
  total = total + 1
  if expected == actual then
    print("[PASS] " .. name)
  else
    failed = failed + 1
    print("[FAIL] " .. name)
    print("       expected: " .. tostring(expected))
    print("       actual:   " .. tostring(actual))
  end
end

local function reset()
  responses = {}
  statuses = {}
  errors = {}
  call_counts = {}
end

-- Successful GET.
reset()
responses["https://example.com/"] = "hello world"
local body, err = httpkit.get("https://example.com/")
check("GET 200 returns body", "hello world", body)
check("GET 200 no error", nil, err)
check("GET 200 single attempt", 1, call_counts["https://example.com/"])

-- 404 returns error, no retry.
reset()
statuses["https://example.com/missing"] = 404
responses["https://example.com/missing"] = "not found"
local body2, err2 = httpkit.get("https://example.com/missing", { retries = 3 })
check("GET 404 returns nil body", nil, body2)
check("GET 404 has error", true, err2 ~= nil and err2:find("404") ~= nil)
check("GET 404 not retried", 1, call_counts["https://example.com/missing"])

-- 500 retries.
reset()
statuses["https://example.com/500"] = 500
local _, err3 = httpkit.get("https://example.com/500", { retries = 2 })
check("GET 500 has error", true, err3 ~= nil and err3:find("500") ~= nil)
check("GET 500 retried 3 times", 3, call_counts["https://example.com/500"])  -- initial + 2 retries

-- Network error retries.
reset()
errors["https://example.com/down"] = "connection refused"
local _, err4 = httpkit.get("https://example.com/down", { retries = 1 })
check("network error retried", 2, call_counts["https://example.com/down"])
check("network error returns last err", true, err4 ~= nil)

-- URL validation.
local _, err5 = httpkit.get("not-a-url")
check("invalid url rejected", true, err5 ~= nil and err5:find("http") ~= nil)

-- 5xx that recovers on retry.
reset()
local attempts = 0
_G.http.get = function(opts)
  local url = type(opts) == "string" and opts or opts.url
  call_counts[url] = (call_counts[url] or 0) + 1
  attempts = attempts + 1
  if attempts == 1 then
    return { readAll = function() return "" end, getResponseCode = function() return 503 end, close = function() end }
  end
  return { readAll = function() return "ok" end, getResponseCode = function() return 200 end, close = function() end }
end

local body6, err6 = httpkit.get("https://example.com/flaky", { retries = 2 })
check("5xx recovers on retry body", "ok", body6)
check("5xx recovers on retry err", nil, err6)

print()
print(string.format("httpkit: %d/%d tests passed", total - failed, total))
if failed > 0 then os.exit(1) end
