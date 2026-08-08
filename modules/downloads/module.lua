return {
  id    = "downloads",
  name  = "Downloads",
  mount = "/downloads",
  order = 40,

  -- Reached from the icon in the bar, next to the profile. Not in the top row: it is somewhere you
  -- go when something is happening, not one of the places the hub is about.
  nav = nil,

  -- Readable offline on purpose. What is queued and what already ran is local knowledge, and hiding
  -- it exactly when a download has just failed for want of a network is the worst possible moment.
  -- Accepting one still needs the network, and says so.
  description = "Active downloads, and the updates waiting for a yes.",
}
