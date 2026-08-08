return {
  id    = "store",
  name  = "Store",
  mount = "/store",
  order = 20,
  nav   = { label = "Store" },

  -- The catalogue is a fold over remote data and holds nothing of its own. With nothing fetched
  -- there is nothing to browse.
  requires_network = true,

  description = "Browse and install modules discovered from GitHub.",
}
