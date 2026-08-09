--[[
  The workspace shell.

  Same tokens, same components, a different geometry. The consumer bar is a floating pill centred on
  a 1280px column; this one is flush and full width, and the tools hang off a rail down the left. The
  material is deliberately identical, blur and border and background all unchanged, so the change
  reads as another room in the same building rather than as a second program.

  Split out of core/ui/theme.lua rather than appended to it: nothing in here is loaded by a page that
  is not the workspace, and a sheet that is already 900 lines does not need a second subject.
]]

return [[
/* ---------- the bar ---------- */

/* The bar is flush rather than floating, so the room it takes is exactly its height. */
body.work { padding-top: 52px }

.worktop {
  position: fixed; top: 0; left: 0; right: 0; z-index: 100;
  display: flex; align-items: center; gap: 1rem;
  height: 52px; padding: 0 .7rem 0 1.1rem;
  background: rgba(24,27,33,.82); border-bottom: 1px solid var(--line);
  backdrop-filter: blur(16px) saturate(1.3);
}
.worktop .spacer { flex: 1 }
.worktop .brand { flex: none }
.worktop .btn.leave { flex: none; padding: .34rem .7rem; font-size: .82rem }

/* ---------- what is being operated on ---------- */

.wtarget {
  display: flex; align-items: center; gap: .55rem; min-width: 0;
  padding-left: 1rem; border-left: 1px solid var(--line); font-size: .85rem;
}
.wtarget .k { flex: none; font-size: .68rem; letter-spacing: .1em; text-transform: uppercase;
  color: var(--dimmer) }
.wtarget .build { flex: none; font-weight: 600 }
.wtarget .path { color: var(--dimmer); white-space: nowrap; overflow: hidden;
  text-overflow: ellipsis }
.wtarget .sep { flex: none; color: var(--line) }
/* The one alarm in the shell, and it earns the accent by being the only thing that can cost you the
   client you play on. */
.wtarget .playing { display: flex; align-items: center; gap: .35rem; flex: none; color: var(--gold) }
.wtarget .playing svg { width: 14px; height: 14px; flex: none }
.wtarget .unset { color: var(--gold) }
.wtarget a.change { flex: none; color: var(--dimmer); font-size: .8rem }
.wtarget a.change:hover { color: var(--gold) }

/* ---------- the rail ---------- */

/* Spans exactly the gap between the two bars and centres the rail inside it, which is both simpler
   than offsetting a 50% by half the status bar and, more importantly, free of a transform.

   That matters more than it looks: an ancestor carrying a `transform` cuts the child's backdrop off
   at that ancestor, and the child's `backdrop-filter` then has nothing to sample. The blur below was
   in the sheet and drawing nothing at all, because this element used to centre itself with
   translateY. Nothing between the viewport and a blurred surface may hold a transform.

   `pointer-events` because this box now covers the whole left edge of the window: it must not catch
   the clicks meant for the page behind it. */
.workrail { position: fixed; left: 14px; top: 52px; bottom: 40px; z-index: 90;
  display: flex; align-items: center; pointer-events: none }
/* One box that grows, not a box with panels flying out of it. `overflow: hidden` is what makes the
   collapsed state work: the names are always in the markup, the rail is simply too narrow to show
   them, so widening is the whole animation and nothing has to appear or be positioned. */
.workrail nav {
  pointer-events: auto;
  display: flex; flex-direction: column; gap: 2px; padding: 6px; width: 50px;
  /* Hidden across, scrollable down: the first is what clips the names, the second is what saves a
     rail with every category open on a short window. */
  overflow-x: hidden; overflow-y: auto; max-height: 100%;
  border-radius: 14px; background: rgba(24,27,33,.5); border: 1px solid var(--line);
  /* The blur and the brightness cut do the work of making this readable, so the surface itself does
     not have to: at .8 with both, the glass had stopped being glass. Half opacity gives the material
     back and the page still reads as colour rather than as shapes. */
  backdrop-filter: blur(28px) saturate(1.35) brightness(.78);
  box-shadow: 0 10px 34px -14px rgba(0,0,0,.9);
  transition: width .22s cubic-bezier(.16,1,.3,1), box-shadow .22s ease;
}
/* Open, it covers page content rather than empty margin, so it needs to look like it is above it.
   Hung off `nav` rather than off `.workrail`: that box is now full height and takes no pointer, so
   its own hover state is not a thing to depend on. */
.workrail nav:hover, .workrail nav:focus-within {
  width: 224px; box-shadow: 0 22px 52px -18px rgba(0,0,0,.95);
}
.wsep { height: 1px; margin: 4px 7px; background: var(--line) }

/* The row is the same shape whether it is a link or a summary, so the two read as one column. */
.wcat > summary, a.wcat {
  display: flex; align-items: center; gap: .55rem; height: 38px; padding: 0 7px; flex: none;
  border-radius: 9px; color: var(--dim); cursor: pointer; white-space: nowrap; outline: none;
  list-style: none; transition: background .16s ease, color .16s ease;
}
.wcat > summary::-webkit-details-marker { display: none }
.wcat > summary:hover, a.wcat:hover { background: rgba(255,255,255,.06); color: var(--text) }
.wcat.on > summary, a.wcat.on { background: rgba(212,162,76,.13); color: var(--gold) }

.wcat .wico { display: flex; align-items: center; justify-content: center; width: 24px; flex: none }
.wcat .wico svg { width: 18px; height: 18px }

/* Faded rather than hidden. A name that is only clipped by the rail's width would appear the instant
   the box starts moving and slide with it, which reads as the text arriving before the panel does. */
.wlabel { flex: 1; min-width: 0; font-size: .88rem; opacity: 0; transition: opacity .16s ease .04s }
.wchev  { display: flex; flex: none; color: var(--dimmer); opacity: 0;
  transition: opacity .16s ease .04s, transform .18s ease }
.wchev svg { width: 14px; height: 14px }
.workrail nav:hover .wlabel, .workrail nav:focus-within .wlabel,
.workrail nav:hover .wchev,  .workrail nav:focus-within .wchev { opacity: 1 }
.wcat[open] > summary .wchev { transform: rotate(90deg) }

/* Hidden while the rail is a column of icons: an open category would otherwise stack its tools in
   50 pixels and turn the rail into a ladder of clipped words. */
.wtools { display: none; padding: .15rem 0 .4rem 30px }
.workrail nav:hover .wcat[open] .wtools,
.workrail nav:focus-within .wcat[open] .wtools { display: block }

.wblurb { display: block; max-width: 24ch; padding: .1rem .45rem .45rem;
  color: var(--dimmer); font-size: .77rem; line-height: 1.45; white-space: normal }

.wtool { display: flex; align-items: center; gap: .5rem; padding: .32rem .45rem;
  border-radius: 7px; color: var(--dim); font-size: .86rem; white-space: nowrap }
.wtool > span { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis }
a.wtool:hover { background: rgba(255,255,255,.05); color: var(--text) }
.wtool.on { color: var(--gold); background: rgba(212,162,76,.1) }
.wtool.off { color: var(--dimmer); cursor: default }
.wtool .pen  { display: flex; flex: none; color: var(--gold-2) }
.wtool .pen svg { width: 13px; height: 13px }
.wtool .soon { flex: none; font-style: normal; font-size: .68rem; letter-spacing: .07em;
  text-transform: uppercase; color: var(--dimmer) }

/* ---------- the working surface ---------- */

/* The rail's lane, reserved on both sides rather than only on the one it sits in. Kept on the left
   only, the column below is centred on what is left of the window and therefore off-centre in it,
   which a wide screen makes obvious. Taking the same width back on the right costs nothing anyone
   can see and puts the column back on the middle of the glass.

   The column itself is the app's, unchanged: a workspace and a store opened side by side should not
   be reading at two different widths. */
body.work { padding-left: 86px; padding-right: 86px }

.wtitle { padding: 1.9rem 0 1.5rem }
.wtitle h1 { margin: 0; font-size: 1.45rem; font-weight: 650; letter-spacing: -.02em }
.wtitle p { margin: .4rem 0 0; max-width: 64ch; color: var(--dim); font-size: .92rem }

.wgrid { display: grid; grid-template-columns: repeat(auto-fit, minmax(230px, 1fr)); gap: 1rem }

/* ---------- the status strip ---------- */

/* One row that answers "can I start", with everything that explains a no folded under it. The whole
   strip is the summary of a <details>, so the folder, the field and the failing checks only take
   room on the screen when they are the reason you are looking. */
.wstatus { border: 1px solid var(--line); border-radius: var(--r); background: var(--panel) }
.wstatus > summary { display: flex; align-items: center; gap: .7rem; min-width: 0;
  padding: .8rem 1rem; cursor: pointer; list-style: none }
.wstatus > summary::-webkit-details-marker { display: none }

.wstatus .dot { width: 8px; height: 8px; flex: none; border-radius: 50%; background: var(--gold) }
.wstatus.ok   .dot { background: var(--green) }
.wstatus.warn .dot { background: var(--gold) }
.wstatus.bad  .dot { background: var(--red) }
.wstatus .verdict { flex: none; font-size: .94rem; font-weight: 600 }
.wstatus.bad .verdict { color: var(--red) }
.wstatus .facts { flex: none; color: var(--dim); font-size: .84rem }
/* The only thing allowed to shrink. Everything else in the row is a verdict, and half a verdict is
   worse than none. */
.wstatus .where { min-width: 0; color: var(--dimmer); font-size: .84rem;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap }
.wstatus .spacer { flex: 1 }
.wstatus .more { flex: none; display: flex; align-items: center; gap: .2rem;
  color: var(--dimmer); font-size: .82rem }
.wstatus .more svg { width: 14px; height: 14px; transition: transform .18s ease }
.wstatus[open] .more svg { transform: rotate(90deg) }
.wstatus > summary:hover .more { color: var(--gold) }

.wstatus .pick { padding: .9rem 1rem 1rem; border-top: 1px solid var(--line-soft) }
.wstatus .val { display: flex; align-items: center; gap: .55rem; min-width: 0 }
.wstatus .val input { flex: 1; min-width: 0; padding: .5rem .7rem; border-radius: 8px;
  border: 1px solid var(--line); background: #0e1015; color: var(--text);
  font: inherit; font-size: .87rem }
.wstatus .val input:focus { outline: 0; border-color: var(--gold-2);
  box-shadow: 0 0 0 3px rgba(212,162,76,.12) }
.wstatus .val .browse { flex: none; padding: .5rem .8rem; border-radius: 8px;
  border: 1px solid var(--line); background: none; color: var(--dim); font: inherit;
  font-size: .84rem; cursor: pointer; user-select: none }
.wstatus .val .browse:hover { border-color: var(--gold-2); color: var(--gold) }
.wstatus .hint { display: block; margin-top: .45rem; color: var(--dimmer); font-size: .8rem }
.wstatus .alarm { display: block; margin-top: .8rem; color: var(--gold); font-size: .86rem }
/* Inline with the sentence rather than above it: the mark and the words are one statement, and a
   glyph on its own line reads as a section heading for the paragraph under it. */
.wstatus .alarm svg { display: inline; width: 15px; height: 15px; vertical-align: -3px;
  margin-right: .35rem }
.wstatus .checks { display: flex; flex-direction: column; gap: .28rem; margin-top: .85rem;
  font-size: .86rem; color: var(--dim) }
.wstatus .checks span { display: flex; align-items: center; gap: .45rem }
.wstatus .checks .warn svg { color: var(--gold) }
.wstatus .checks .bad  svg { color: var(--red) }

/* ---------- the tools you keep ---------- */

.wfav { display: grid; grid-template-columns: repeat(auto-fill, minmax(232px, 1fr)); gap: .9rem }

.favcard { position: relative; display: flex; align-items: center; gap: .7rem;
  padding: .85rem .95rem; min-height: 72px; transition: border-color .12s }
.favcard:hover { border-color: #343b4a }
/* The link covers the card so the whole surface navigates, and it sits under the remove button
   rather than around it: a <button> inside an <a> is not markup a browser owes anyone a meaning for. */
.favcard .go { position: absolute; inset: 0; border-radius: inherit }
.favcard .ico { display: flex; align-items: center; justify-content: center; flex: none;
  width: 34px; height: 34px; border-radius: 9px; border: 1px solid var(--line); color: var(--gold) }
.favcard .ico svg { width: 17px; height: 17px }
.favcard .t { min-width: 0; flex: 1 }
.favcard .t b { display: block; font-size: .91rem; font-weight: 600;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap }
.favcard .t > span { font-size: .79rem; color: var(--dimmer) }
.favcard .pen { display: flex; flex: none; color: var(--gold-2) }
.favcard .pen svg { width: 14px; height: 14px }

/* Above the stretched link, and only there once the card is under the pointer: a row of remove
   buttons is a row of things to hit by accident. */
.favcard .drop { position: relative; z-index: 1; flex: none; display: flex; align-items: center;
  justify-content: center; width: 24px; height: 24px; border-radius: 7px; border: 0;
  background: none; color: var(--dimmer); cursor: pointer; opacity: 0; transition: opacity .12s }
.favcard:hover .drop, .favcard .drop:focus-visible { opacity: 1 }
.favcard .drop:hover { background: rgba(224,115,109,.16); color: var(--red) }
.favcard .drop svg { width: 13px; height: 13px }

.favcard.add { flex-direction: column; justify-content: center; gap: .3rem;
  border: 1px dashed var(--line); border-radius: var(--r); background: none; color: var(--dimmer);
  font: inherit; cursor: pointer; transition: border-color .12s, color .12s }
.favcard.add:hover { border-color: var(--gold-2); color: var(--gold) }
.favcard.add .plus { font-size: 1.5rem; line-height: 1; font-weight: 300 }
.favcard.add .lbl { font-size: .82rem }

/* ---------- the picker ---------- */

.favpick { padding: .9rem 1rem 1rem }
.favpick .head { display: flex; align-items: center; gap: .5rem; margin-bottom: .9rem }
.favpick .head b { font-size: .95rem; font-weight: 600 }
.favpick .head .spacer { flex: 1 }
.favpick .close { display: flex; align-items: center; justify-content: center; width: 26px;
  height: 26px; border-radius: 7px; border: 0; background: none; color: var(--dimmer);
  cursor: pointer }
.favpick .close:hover { background: rgba(255,255,255,.06); color: var(--text) }
.favpick .close svg { width: 14px; height: 14px }

.favpick .grp + .grp { margin-top: .9rem }
.favpick .lbl { display: flex; align-items: center; gap: .45rem; margin-bottom: .45rem;
  color: var(--dimmer); font-size: .74rem; letter-spacing: .08em; text-transform: uppercase }
.favpick .lbl svg { width: 14px; height: 14px }
.favpick .opts { display: flex; flex-wrap: wrap; gap: .45rem }
.favpick .opts > * { display: inline-flex; align-items: center; gap: .4rem;
  padding: .34rem .7rem; border-radius: 999px; border: 1px solid var(--line);
  background: none; color: var(--dim); font: inherit; font-size: .85rem }
.favpick .opts button { cursor: pointer }
.favpick .opts button:hover { border-color: var(--gold-2); color: var(--gold) }
.favpick .opts .off { color: var(--dimmer); border-style: dashed }
.favpick .opts .pen { display: flex; color: var(--gold-2) }
.favpick .opts .pen svg { width: 13px; height: 13px }
.favpick .opts .soon { font-style: normal; font-size: .66rem; letter-spacing: .07em;
  text-transform: uppercase; color: var(--dimmer) }

/* ---------- deploying the framework ---------- */

.wdeploy { padding: 1.1rem 1.2rem }
.wdeploy code { padding: .05rem .3rem; border-radius: 4px; background: rgba(255,255,255,.06);
  font-size: .9em }

.dstate { display: flex; flex-direction: column; gap: .5rem }
.dstate .row { display: flex; align-items: center; gap: .8rem; font-size: .88rem }
.dstate .k { flex: none; width: 8.5rem; color: var(--dimmer); font-size: .8rem }
.dstate .v { display: flex; align-items: center; gap: .4rem; min-width: 0; word-break: break-all }
.dstate .v.ok   { color: var(--green) }
.dstate .v.warn { color: var(--gold) }
.dstate .v.dim  { color: var(--dimmer) }

.wdeploy .alarm { display: block; margin-top: 1rem; color: var(--gold); font-size: .86rem }
.wdeploy .alarm svg { display: inline; width: 15px; height: 15px; vertical-align: -3px;
  margin-right: .35rem }
.wdeploy .acts { display: flex; align-items: center; gap: .85rem; flex-wrap: wrap;
  margin-top: 1.1rem }
.wdeploy .acts .note { color: var(--dimmer); font-size: .8rem }
/* No client, no button. Kept visible and inert rather than hidden: the reason it cannot run is in
   the bar above, and a control that vanishes is a control nobody goes looking for the reason for. */
.wdeploy .btn[disabled] { opacity: .45; cursor: default }
.wdeploy .btn[disabled]:hover { background: var(--gold); color: #1b1405 }
.wdeploy #wjob:not(:empty) { margin-top: .95rem }

/* ---------- the wiring table ---------- */

.wiring { width: 100%; border-collapse: collapse; font-size: .87rem }
.wiring th { padding: .5rem .7rem; text-align: left; font-weight: 500; color: var(--dimmer);
  font-size: .74rem; letter-spacing: .08em; text-transform: uppercase;
  border-bottom: 1px solid var(--line) }
.wiring td { padding: .45rem .7rem; border-bottom: 1px solid var(--line-soft); color: var(--dim) }
.wiring tr:last-child td { border-bottom: 0 }
.wiring code { font-size: .93em; color: var(--text) }
.wiring .n { text-align: right; color: var(--dimmer); width: 4rem }

/* ---------- entrance ---------- */

/* Their own keyframes rather than the bar's. A keyframe replaces the whole declared transform, and
   the consumer bar's carries the translateX(-50%) that centres it: borrowing it would start both of
   these half a window to the left. Each `from` here ends on the transform its element actually has,
   which is what the implicit `to` resolves to.

   The rail's runs on `nav` and not on `.workrail`. `both` leaves the last keyframe applied for good,
   so putting it on the parent would reinstate exactly the ancestor transform that stopped the blur
   from sampling anything. A transform an element carries itself is fine; one above it is not. */
@keyframes worktopin { from { opacity: 0; transform: translateY(-9px) } }
@keyframes railin    { from { opacity: 0; transform: translateX(-14px) } }

.wxl-shown .worktop      { animation: worktopin .34s cubic-bezier(.16,1,.3,1) both }
.wxl-shown .workrail nav { animation: railin .4s cubic-bezier(.16,1,.3,1) both; animation-delay: .1s }
]]
