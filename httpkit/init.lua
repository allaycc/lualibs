-- httpkit: HTTP fetching with retries and timeout for CC programs.
--
-- Wraps CC's http API. Adds retry on transient failures, configurable
-- timeout, and a tidy error model. All operations return (data, err)
-- where err is nil on success and a string on failure.

local M = {}

M.VERSION = "1.0.0"

M.DEFAULT_RETRIES = 2
M.DEFAULT_TIMEOUT_SECONDS = 30

local function http_available()
  return _G.http ~= nil and type(_G.http.get) == "function"
end

local function check_url(url)
  if type(url) ~= "string" then return false, "url must be a string" end
  if not (url:match("^https?://") or url:match("^http://")) then
    return false, "url must start with http:// or https://"
  end
  if http_available() and _G.http.checkURL then
    local ok, err = _G.http.checkURL(url)
    if not ok then return false, err or "url not allowed" end
  end
  return true
end

-- Sleep helper that works inside CC and standalone Lua.
local function sleep_for(seconds)
  if _G.os and type(_G.os.sleep) == "function" then
    _G.os.sleep(seconds)
  end
end

-- Get the contents of a URL. Returns (body, err).
function M.get(url, opts)
  opts = opts or {}
  local retries = opts.retries or M.DEFAULT_RETRIES
  local timeout = opts.timeout or M.DEFAULT_TIMEOUT_SECONDS
  local headers = opts.headers

  if not http_available() then
    return nil, "http API is not available (HTTP disabled or not running in CC?)"
  end

  local ok, err = check_url(url)
  if not ok then return nil, err end

  local last_err = nil
  for attempt = 0, retries do
    local response, http_err = _G.http.get({
      url = url,
      headers = headers,
      timeout = timeout,
    })
    if response then
      local status = response.getResponseCode and response.getResponseCode()
      local body = response.readAll()
      response.close()
      if status and status >= 400 then
        last_err = string.format("HTTP %d for %s", status, url)
        -- 4xx is not retryable, 5xx is.
        if status < 500 then
          return nil, last_err
        end
      else
        return body
      end
    else
      last_err = http_err or ("request failed: " .. url)
    end

    if attempt < retries then
      sleep_for(0.5 * (2 ^ attempt))
    end
  end
  return nil, last_err
end

-- Fetch a URL into a file. Uses the path's parent dir; caller is responsible
-- for writing atomically (use pathkit.write_atomic with the returned content
-- if you want atomicity).
function M.get_into(url, path, opts)
  local body, err = M.get(url, opts)
  if err then return nil, err end

  local pathkit = require("pathkit")
  local ok, write_err = pathkit.write_atomic(path, body)
  if not ok then return nil, write_err end
  return body
end

-- Quick HEAD-style availability check. Returns true if the URL responds
-- with any 2xx or 3xx status, false otherwise.
function M.reachable(url, opts)
  local body, err = M.get(url, opts)
  return body ~= nil, err
end

return M
