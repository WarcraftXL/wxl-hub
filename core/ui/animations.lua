--[[
  Motion.

  Split out of core/ui/theme.lua so the sheet has two halves read for different reasons: what things
  look like, and what they do when they arrive or when a pointer finds them. core/ui/style.lua joins the
  two strings, and a keyframe declared here is visible to a rule declared there: `@keyframes` are
  global whatever file they were written in.

  What lives here: every keyframe in the app, the entrance choreography, the answers to a pointer,
  and the policy for someone who asked their system to stop moving things. What stays in the theme is
  the one `animation:` line on a component, next to the rest of that component, because reading a
  spinner means reading its size and its spin together.

  Nothing here animates a property that costs layout. Opacity and transform only, so all of it stays
  on the compositor and none of it can make the page reflow while it plays.
]]

return [[
/* ---------- keyframes ----------
   Shared, and named for what they do rather than for who uses them. */
@keyframes fade    { from { opacity: 0 } to { opacity: 1 } }
@keyframes rise    { from { opacity: 0; transform: translateY(12px) } }
@keyframes settle  { from { opacity: 0; transform: translateY(7px) } }
@keyframes verdict { from { opacity: 0; transform: translateY(-3px) } }
@keyframes panelin { from { opacity: 0; transform: translateY(-6px) scale(.985) } }
@keyframes spin    { to { transform: rotate(360deg) } }
@keyframes sheen   { from { transform: translateX(-100%) } to { transform: translateX(100%) } }
@keyframes sweep   { 0% { transform: translateX(-100%) } 100% { transform: translateX(340%) } }

@keyframes toastin    { from { opacity: 0; transform: translateX(18px) scale(.97) } }
@keyframes toastdrain { to { transform: scaleX(0) } }
@keyframes toastout {
  to { opacity: 0; transform: translateX(18px);
       max-height: 0; padding-top: 0; padding-bottom: 0; margin-top: -.55rem; border-width: 0 }
}

/* The top bar carries a translateX of its own for centring, so its keyframes have to restate it: a
   transform in a keyframe replaces the declared one rather than adding to it, and the bar would
   swing to the left edge for the length of the animation. */
@keyframes barin {
  from { opacity: 0; transform: translateX(-50%) translateY(-9px) }
  to   { opacity: 1; transform: translateX(-50%) translateY(0) }
}

/* ---------- entrance ----------
   Every document settles the same way: the bar drops in, the page's blocks follow in reading order,
   the status bar last. Short and small on purpose. The point is that the window feels assembled
   rather than pasted, not that anything is worth watching.

   All of it hangs off `.wxl-shown`, which the shell sets once the window is actually on screen. A
   CSS animation starts its clock at the first style resolution, and the window is created hidden, so
   an animation written the ordinary way is already half spent before anyone can see it. Absent the
   class nothing animates and everything is simply there, which is also what a page opened in a plain
   browser gets. */
.wxl-shown .top { animation: barin .34s cubic-bezier(.16,1,.3,1) both }

/* Every direct child of the page, whatever it is: a band, a breadcrumb, a section. Six deep, because
   the seventh block is below the fold on any window and a delay it spends off screen is a delay
   nobody sees.

   This is also the transition between pages. A navigation replaces `#view` and nothing else, so its
   new blocks match this rule and cascade in while the bars around them hold still. Tighter than an
   opening, because a click is expected to have already happened: the first block is in at 40ms. */
.wxl-shown .page > * { animation: settle .3s cubic-bezier(.16,1,.3,1) both }
.wxl-shown .page > :nth-child(1) { animation-delay: .04s }
.wxl-shown .page > :nth-child(2) { animation-delay: .09s }
.wxl-shown .page > :nth-child(3) { animation-delay: .14s }
.wxl-shown .page > :nth-child(4) { animation-delay: .19s }
.wxl-shown .page > :nth-child(5) { animation-delay: .24s }
.wxl-shown .page > :nth-child(n+6) { animation-delay: .28s }

.wxl-shown footer { animation: settle .34s cubic-bezier(.16,1,.3,1) both; animation-delay: .2s }

/* The first-run card, and then its questions. Slower than a navigation: this screen is read once, by
   someone who has just opened the thing for the first time. */
.wxl-shown .welcome { animation: rise .5s cubic-bezier(.16,1,.3,1) both }
.wxl-shown .welcome .wstep,
.wxl-shown .welcome .install { animation: rise .55s cubic-bezier(.16,1,.3,1) both }
.wxl-shown .welcome .wstep:nth-of-type(1) { animation-delay: .14s }
.wxl-shown .welcome .wstep:nth-of-type(2) { animation-delay: .27s }
.wxl-shown .welcome .wstep:nth-of-type(3) { animation-delay: .40s }
.wxl-shown .welcome .install { animation-delay: .53s }

.wxl-shown .splash.launch { animation: rise .3s cubic-bezier(.16,1,.3,1) both }

/* ---------- the notification panel ----------
   It was there or it was not, with nothing in between, and a 348px box appearing under the cursor in
   one frame reads as a glitch rather than as an answer. Anchored to the corner it grows from, and
   short enough that it never stands between the click and the reading. */
.tray details[open] .traypanel {
  transform-origin: top right;
  animation: panelin .16s cubic-bezier(.16,1,.3,1) both;
}

/* ---------- the hand under the pointer ----------
   Nothing here moves on its own. These are answers to a pointer, which is the kind of motion that
   makes a surface feel like an object rather than a picture of one. */
.nav a, .profile, .brand, .tray .dl { transition: background .14s, color .14s, opacity .15s }

.play { transition: background .14s, transform .12s, box-shadow .14s }
.play:hover { transform: translateY(-1px); box-shadow: 0 9px 22px -9px rgba(212,162,76,.75) }
.play:active { transform: translateY(0); box-shadow: none }

/* The card already lifts and takes a lighter border. The shadow is what makes the lift read as
   height rather than as a nudge. Restated in full because this declaration replaces the one in the
   theme rather than adding to it. */
.card { transition: border-color .14s, transform .14s, box-shadow .14s }
.card:hover { box-shadow: 0 16px 34px -20px rgba(0,0,0,.95) }

/* ---------- a page on its way ----------
   htmx marks the element a request came from, so the sign that something is happening sits on the
   thing that was clicked rather than on a bar somewhere else on screen. Invisible on a fast answer,
   which is when there is nothing worth saying. */
.nav a.htmx-request, .brand.htmx-request, .tray .dl.htmx-request { opacity: .5 }

/* ---------- less motion ----------
   Every animation in this sheet is decoration: the toast still leaves, the bar still fills, the card
   still arrives. Turning them off costs nothing, and leaving them on for someone who asked their
   system not to move things costs them. */
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: .001ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: .001ms !important;
    /* The delays go too, and they are the reason this block is worth reading twice. Cutting the
       duration alone leaves a staggered entrance staggered: nothing fades, but each element still
       waits its turn and then appears in one frame. Four things popping into place in sequence is
       more movement than the animation it replaced, which is the opposite of what was asked for. */
    animation-delay: 0s !important;
    transition-delay: 0s !important;
  }
}
]]
