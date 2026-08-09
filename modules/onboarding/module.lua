return {
  id    = "onboarding",
  name  = "First run",
  order = 5,

  -- Nowhere to navigate to. It owns one screen, shown once, before the hub has opened: a destination
  -- in the bar would be a link to a question that has already been answered.
  nav = nil,

  description = "The questions asked once, before the hub opens for the first time.",
}
