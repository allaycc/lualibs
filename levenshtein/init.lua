-- levenshtein: edit-distance between two strings.
--
-- Used for typo suggestions ("did you mean: install?"). Returns the minimum
-- number of single-character insertions/deletions/substitutions to turn the
-- first string into the second.
--
-- Iterative with two rolling rows -- O(min(#a, #b)) memory, O(#a * #b) time.

local M = {}

M.VERSION = "1.0.0"

function M.distance(a, b)
  if type(a) ~= "string" or type(b) ~= "string" then
    error("levenshtein.distance: both arguments must be strings", 2)
  end
  if #a == 0 then return #b end
  if #b == 0 then return #a end

  local prev, cur = {}, {}
  for j = 0, #b do prev[j] = j end

  for i = 1, #a do
    cur[0] = i
    for j = 1, #b do
      local cost = (a:sub(i, i) == b:sub(j, j)) and 0 or 1
      cur[j] = math.min(
        cur[j - 1] + 1,        -- insertion
        prev[j]   + 1,         -- deletion
        prev[j-1] + cost       -- substitution
      )
    end
    for j = 0, #b do prev[j] = cur[j] end
  end

  return cur[#b]
end

-- Convenience: pick the best match for `query` from `candidates`. Returns
-- (best_match, distance) or (nil, nil) if no candidate is within max_dist.
-- max_dist defaults to 2.
function M.suggest(query, candidates, max_dist)
  max_dist = max_dist or 2
  local best, best_d
  for _, c in ipairs(candidates) do
    local d = M.distance(query, c)
    if not best_d or d < best_d then
      best, best_d = c, d
    end
  end
  if best_d and best_d <= max_dist then return best, best_d end
  return nil, nil
end

setmetatable(M, { __call = function(_, a, b) return M.distance(a, b) end })

return M
