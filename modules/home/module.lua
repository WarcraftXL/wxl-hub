return {
  id    = "home",
  name  = "Home",
  mount = "/",
  order = 10,
  nav   = { label = "Home", href = "/" },

  -- News comes from wxl-core and the sections come from the catalogue. Offline there is nothing on
  -- this page, so it steps aside for the library instead of rendering an empty frame.
  requires_network = true,

  description = "Announcements, a slice of the catalogue, and what you last opened.",
}
