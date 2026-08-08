return {
  id       = "tools",
  name     = "Tools",
  mount    = "/tools",
  order    = 40,
  nav      = { label = "Tools" },

  -- Hidden unless developer mode is on, and that setting starts off. It is the only difference
  -- between the player-facing and the author-facing halves of the app.
  dev_only = true,

  -- No `requires_tools` while the page is a placeholder. Declaring a dependency on Python would have
  -- the hub report the module unavailable, and describe a reason that is not the real one: there is
  -- nothing here to run yet, with or without Python.

  description = "Drive the asset pipeline without a terminal.",
}
