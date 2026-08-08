--[[
  The stylesheet, as something the browser can cache.

  core/theme.lua is the source and stays a Lua file, because it is written and commented like one.
  This file is about delivery. Interpolating the sheet into a <style> block makes every full page
  carry the whole thing again, with no way for the browser to know it already has it.

  Served instead at a URL ending in a digest of its own contents. The response can then be cached
  for a year without ever going stale: an edited theme is a different digest, which is a different
  URL, which is a fetch the browser has no answer for. Nothing has to be cleared and no version has
  to be bumped by hand.
]]

local ossl = require("openssl")

local M = {}

M.css = require("core.theme")

-- Ten hex characters. This names a file rather than proving anything about it, and the whole sheet
-- is a build input the user never supplies.
M.href = "/theme.css?v=" .. ossl.digest.digest("sha256", M.css):sub(1, 10)

M.mime = "text/css; charset=utf-8"

-- A year. Safe only because the digest is in the URL; on a plain /theme.css it would be a way to
-- ship a change nobody can see.
M.cache_control = "public, max-age=31536000, immutable"

return M
