return {
  id    = "runiclab",
  name  = "Runic-Lab",
  order = 45,

  -- No mount and no nav entry. This module owns no URL space of its own: everything it offers is a
  -- tool inside the workspace, and the workspace already has the shell for that. A module that
  -- contributes and nothing else is a legitimate shape, not a half-finished one.

  dev_only = true,

  description = "The RunicLab generators, brought back as workspace tools.",
}
