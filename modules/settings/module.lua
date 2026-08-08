return {
  id    = "settings",
  name  = "Settings",
  mount = "/settings",
  order = 90,

  -- Reached from the profile chip in the bar rather than from the nav, so the top row stays about
  -- where you are going rather than how the app is configured.
  nav   = nil,


  description = "Client paths, developer mode, storage and diagnostics, plus any page another "
             .. "module contributes to settings.section.",
}

