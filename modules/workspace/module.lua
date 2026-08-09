return {
  id       = "workspace",
  name     = "Dev Workspace",
  mount    = "/workspace",
  order    = 40,
  -- `boundary` because this module replaces the shell instead of filling it. A boosted link swaps
  -- only `#view`, which would drop the workspace under the bar of the page it was opened from.
  nav      = { label = "Workspace", boundary = true },

  -- Hidden unless developer mode is on, and that setting starts off. It is the only difference
  -- between the player-facing and the author-facing halves of the app.
  dev_only = true,

  -- No `requires_tools`. The pipeline is being written in Lua against the SDK rather than wrapped
  -- around command-line programs, so there is nothing on PATH left for this module to depend on.

  description = "The WarcraftXL toolchain in one window, so building for it does not start with a "
             .. "terminal and a folder of scripts.",
}
