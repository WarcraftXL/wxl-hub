return {
  -- Parked. The tool this page exists to host is moving into the launcher itself and will take a
  -- while, and six cards that all open onto "not built yet" say less than no page at all.
  --
  -- Nothing else has to be told: the navigation, the home section and the recent list all discover
  -- what they show, so deleting this one line puts the page back exactly as it was.
  parked   = true,

  id       = "tools",
  name     = "Tools",
  mount    = "/tools",
  order    = 40,
  nav      = { label = "Tools" },

  -- Hidden unless developer mode is on. It is the only difference between the player-facing and
  -- author-facing halves of the app.
  dev_only = true,

  -- Every tool here shells out to Python. Declaring it lets the hub grey the module out with a
  -- readable reason instead of failing in the middle of a conversion.
  requires_tools = { "python" },

  description = "Drive the asset pipeline without a terminal.",
}
