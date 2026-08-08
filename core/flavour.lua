--[[
  Loading-screen flavour lines.

  Written in the register of Warcraft III unit responses rather than lifted from them: the tone is
  the point, and original lines carry it without shipping someone else's script inside the product.

  One line is shown at a time and rotates on a fixed cadence, so two people watching the same boot
  see the same thing. Flavour, not noise.
]]

local M = {}

M.INTERVAL_MS = 1500

M.lines = {
  { "Working. Always working.",                       "Peasant" },
  { "The master's manifests are being gathered.",     "Acolyte" },
  { "Yes, milord? …a moment.",                        "Footman" },
  { "The braziers are lit. Mostly.",                  "Cultist" },
  { "Counting the dead. There are a great many.",     "Necrolyte" },
  { "Something stirs in the terrain data.",           "Sentinel" },
  { "Runes align. Slowly. As runes do.",              "Cultist" },
  { "The whetstone turns.",                           "Blacksmith" },
  { "Provisions loaded. Mind the crates.",            "Peon" },
  { "Ley lines re-routed. Again.",                    "Archmage" },
  { "Who summoned this catalogue?",                   "Ghoul" },
  { "Ready when the omens are.",                      "Seer" },
  { "The shadows have been counted.",                 "Shade" },
  { "It is done. Nearly. Nearly done.",               "Acolyte" },
}

--- Which line a given moment lands on. Deterministic, so a poll every few hundred milliseconds keeps
--- returning the same index until the interval actually rolls over.
function M.index_at(elapsed_ms, seed)
  local i = math.floor(elapsed_ms / M.INTERVAL_MS) + (seed or 0)
  return (i % #M.lines) + 1
end

function M.at(elapsed_ms, seed)
  return M.lines[M.index_at(elapsed_ms, seed)]
end

return M
