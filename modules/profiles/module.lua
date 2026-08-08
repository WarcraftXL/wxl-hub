return {
  id    = "profiles",
  name  = "Profiles",
  mount = "/profiles",
  order = 85,

  -- No entry in the bar. It owns identity and settings values, not a destination: its page is a
  -- section contributed into Settings, and its one screen of its own only appears at startup.
  nav = nil,

  description = "Which client you launch, and every value that belongs to that answer.",
}
