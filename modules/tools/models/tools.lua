--[[
  The developer tools the hub can drive.

  Each one is a command-line program in tools/, not logic living here: a converter that cannot be run
  from a terminal is in the wrong repository. `command` is what the job runner will spawn at M3, and
  `requires` is what makes a tool show as unavailable with a reason instead of failing mid-job.
]]

return {
  tools = {
    { id = "adtsplit", name = "Terrain Split", icon = "▦", status = "ready",
      blurb = "Convert split terrain tiles for server-side map extraction.",
      command = { "python", "tools/adt-tools/make_map_split.py" }, requires = { "python" } },

    { id = "db2dbc", name = "DB2 → DBC", icon = "▤", status = "ready",
      blurb = "Bring modern data tables back to a format the emulator reads.",
      command = { "python", "tools/asset-inspect/cli.py", "db2dbc" }, requires = { "python" } },

    { id = "inspect", name = "Asset Inspect", icon = "◈", status = "ready",
      blurb = "Walk any M2, WMO or ADT chunk tree without leaving the hub.",
      command = { "python", "tools/asset-inspect/cli.py" }, requires = { "python" } },

    { id = "wdl", name = "WDL Regen", icon = "◭", status = "ready",
      blurb = "Rebuild low-detail world maps after a terrain pass.",
      command = { "python", "tools/regen_wdl.py" }, requires = { "python" } },

    { id = "logs", name = "Runtime Log", icon = "≡", status = "live",
      blurb = "Tail wxl-core.log with filtering, while the client runs.",
      command = nil, requires = {} },

    { id = "package", name = "Package & Sign", icon = "◆", status = "soon",
      blurb = "Build a release archive and a manifest from a working tree.",
      command = nil, requires = {} },
  },
}
