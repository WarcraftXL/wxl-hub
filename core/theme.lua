--[[
  Design tokens and the shared stylesheet.

  The restraint is the design: one warm accent on neutral greys, 1px borders, no ornament.

  Vertical rhythm comes from one rule, `section { margin-top }`, rather than from each block setting
  its own. Zeroing it with `.sec:first-child` is the tempting shortcut and the wrong one: it strips
  the margin from every section header that opens a block, and those headers then collide.

  Anything that needs to sit at the end of a header row uses an explicit `.spacer`. Two competing
  `margin-left:auto` in one flex row fight over the same space.
]]

return [[
:root {
  --bg:        #101216;
  --panel:     #181b21;
  --panel-2:   #1c2028;
  --line:      #252932;
  --line-soft: #1f232b;

  --gold:      #d4a24c;
  --gold-2:    #a87c33;

  --text:      #e6e8ee;
  --dim:       #9aa1b1;
  --dimmer:    #646c7c;

  --green:     #7fd88f;
  --red:       #e0736d;

  --r:  10px;
  --r-lg: 14px;
  --ui: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
}

* { box-sizing: border-box }
html { background: var(--bg) }
body { margin: 0; padding-top: 84px; background: var(--bg); color: var(--text);
  font: 15px/1.6 var(--ui); -webkit-font-smoothing: antialiased }
a { color: inherit; text-decoration: none }
img { display: block }

/* ---------- floating top bar ---------- */
.top {
  position: fixed; top: 14px; left: 50%; transform: translateX(-50%);
  width: calc(100% - 3rem); max-width: 1280px; z-index: 100;
  display: flex; align-items: center; gap: 1.4rem;
  padding: 0 .7rem 0 1.2rem; height: 54px; border-radius: 12px;
  background: rgba(24,27,33,.78); border: 1px solid var(--line);
  backdrop-filter: blur(16px) saturate(1.3);
  box-shadow: 0 10px 34px -14px rgba(0,0,0,.9);
}
.brand { display: flex; align-items: center; gap: .6rem; font-weight: 600;
  letter-spacing: -.01em; flex: none }
.brand img { width: 26px; height: 26px; flex: none }
.brand em { font-style: normal; color: var(--gold) }
.nav { display: flex; gap: .15rem }
.nav a { padding: .4rem .8rem; border-radius: 7px; color: var(--dim); font-size: .9rem }
.nav a:hover { color: var(--text); background: rgba(255,255,255,.05) }
.nav a.on { color: var(--text); background: rgba(255,255,255,.07) }
.top .spacer { flex: 1 }

/* ---------- tray: notifications and downloads ---------- */
.tray { display: flex; align-items: center; gap: .1rem; flex: none }
.tray summary, .tray .dl { position: relative; display: flex; align-items: center;
  padding: .42rem; border-radius: 8px; color: var(--dim); cursor: pointer; list-style: none }
.tray summary::-webkit-details-marker { display: none }
.tray summary:hover, .tray .dl:hover { color: var(--text); background: rgba(255,255,255,.05) }
.tray .dl.on, .tray details[open] summary { color: var(--gold); background: rgba(212,162,76,.11) }
.tray svg { width: 18px; height: 18px }
.tray .pip { position: absolute; top: 1px; right: 0; min-width: 15px; height: 15px; padding: 0 3px;
  border-radius: 999px; background: var(--gold); color: #1b1405;
  font: 700 9.5px/15px var(--ui); font-style: normal; text-align: center;
  box-shadow: 0 0 0 2px rgba(24,27,33,.95) }

.tray details { position: relative }
.traypanel { position: absolute; top: calc(100% + 12px); right: -6px; width: 348px;
  max-height: 62vh; overflow-y: auto; padding: .4rem;
  background: var(--panel); border: 1px solid var(--line); border-radius: var(--r);
  box-shadow: 0 18px 44px -14px rgba(0,0,0,.92); z-index: 120 }
.tphead { display: flex; align-items: center; gap: .5rem; padding: .5rem .6rem .55rem;
  font-size: .84rem }
.tphead .spacer { flex: 1 }
.tphead .clear { cursor: pointer; font-size: .81rem; color: var(--dimmer) }
.tphead .clear:hover { color: var(--gold) }
.tpempty { margin: 0; padding: 1.6rem .8rem; text-align: center; color: var(--dimmer);
  font-size: .84rem }
.tpitem { display: flex; align-items: flex-start; gap: .55rem; padding: .55rem .6rem;
  border-radius: 8px; font-size: .84rem }
.tpitem:hover { background: rgba(255,255,255,.045) }
.tpitem .dot { width: 7px; height: 7px; margin-top: .42rem; border-radius: 50%; flex: none;
  background: var(--dimmer) }
.tpitem.good .dot { background: var(--green) }
.tpitem.bad  .dot { background: var(--red) }
.tpitem .t { flex: 1; min-width: 0 }
.tpitem a.t:hover b { color: var(--gold) }
.tpitem .t b { display: block; font-weight: 600 }
.tpitem .t span { display: block; color: var(--dimmer); font-size: .81rem }
.tpitem .when { flex: none; color: var(--dimmer); font-size: .78rem; margin-top: .1rem }

/* Only on hover, so a dozen crosses do not read as the point of the list. */
.tpitem .x { flex: none; width: 18px; height: 18px; border-radius: 5px; cursor: pointer;
  display: flex; align-items: center; justify-content: center;
  color: var(--dimmer); font-size: .7rem; opacity: 0; transition: opacity .12s }
.tpitem:hover .x { opacity: 1 }
.tpitem .x:hover { background: rgba(224,115,109,.16); color: var(--red) }

/* ---------- toasts ----------
   Raised by the response that caused them and removed by the animation itself: it ends collapsed,
   transparent and click-through, so nothing has to run a timer or spend a request tidying up. */
#toasts { position: fixed; top: 84px; right: 20px; z-index: 200;
  display: flex; flex-direction: column; align-items: flex-end; gap: .55rem;
  pointer-events: none }

.toast { position: relative; overflow: hidden;
  display: flex; align-items: center; gap: .7rem; width: 340px;
  padding: .8rem .95rem .8rem 1.05rem; border-radius: 11px;
  background: linear-gradient(180deg, rgba(32,36,45,.99), rgba(24,27,34,.99));
  border: 1px solid var(--line); color: var(--text);
  box-shadow: 0 20px 46px -14px rgba(0,0,0,.95), 0 0 0 1px rgba(0,0,0,.35);
  animation: toastin .22s cubic-bezier(.16,1,.3,1), toastout .4s ease-in 4.8s forwards }

/* A stripe down the edge carries the outcome, so the colour is legible before the words are. */
.toast::before { content: ""; position: absolute; left: 0; top: 0; bottom: 0; width: 3px;
  background: var(--dimmer) }
.toast.good::before { background: var(--green) }
.toast.bad::before  { background: var(--red) }

/* The countdown is the animation itself: it drains over the same delay the toast waits out, so the
   bar cannot disagree with when the thing actually leaves. */
.toast::after { content: ""; position: absolute; left: 0; bottom: 0; height: 2px;
  background: rgba(255,255,255,.14); width: 100%;
  transform-origin: left; animation: toastdrain 4.8s linear forwards }

.toast .ico { flex: none; width: 24px; height: 24px; border-radius: 50%;
  display: flex; align-items: center; justify-content: center;
  font-size: .74rem; background: rgba(255,255,255,.06); color: var(--dim) }
.toast.good .ico { background: rgba(127,216,143,.14); color: var(--green) }
.toast.bad  .ico { background: rgba(224,115,109,.16); color: var(--red) }

.toast .t { min-width: 0 }
.toast .t b { display: block; font-weight: 600; font-size: .89rem; letter-spacing: -.005em;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap }
.toast .t span { display: block; color: var(--dimmer); font-size: .81rem; margin-top: .12rem;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap }

@keyframes toastin   { from { opacity: 0; transform: translateX(18px) scale(.97) } }
@keyframes toastdrain { to { transform: scaleX(0) } }
@keyframes toastout {
  to { opacity: 0; transform: translateX(18px);
       max-height: 0; padding-top: 0; padding-bottom: 0; margin-top: -.55rem; border-width: 0 }
}
.profile { display: flex; align-items: center; gap: .5rem; font-size: .88rem; color: var(--dim);
  padding: .4rem .8rem; border-radius: 7px }
.profile:hover { color: var(--text); background: rgba(255,255,255,.05) }
.profile.on { color: var(--text); background: rgba(255,255,255,.07) }
.profile .dot { width: 7px; height: 7px; border-radius: 50%; background: var(--green) }
.play {
  padding: .45rem 1.25rem; border: 0; border-radius: 8px;
  background: var(--gold); color: #1b1405; font: 600 .88rem/1 var(--ui); cursor: pointer;
}
.play:hover { background: #e0b05f }

/* ---------- stale-data warning ----------
   Sits above the content rather than floating over it: this is a statement about everything on the
   page, so it should push the page down and be impossible to mistake for a toast that will vanish. */
.stalebar {
  /* Aligned with the page content, which is 1280px capped minus its own 1.5rem gutters. */
  width: calc(100% - 3rem); max-width: 1232px; margin: 0 auto 1.6rem; padding: .7rem 1rem;
  display: flex; align-items: center; gap: .65rem;
  border: 1px solid var(--gold-2); border-radius: var(--r);
  background: rgba(212,162,76,.09); color: var(--gold);
  font-size: .88rem;
}
.stalebar svg { width: 17px; height: 17px; flex: none }

/* ---------- page rhythm ----------
   One rule owns vertical spacing between blocks. Nothing else sets a top margin. */
.page { max-width: 1280px; margin: 0 auto; padding: 0 1.5rem 5rem }
section { margin-top: 3.6rem }
section.first { margin-top: 0 }

/* A hairline before a section, faded at both ends so it reads as breathing room rather than a rule.
   Opt-in, not automatic: it marks the boundary between groups of sections, and drawing one between
   every pair would chop a group into slices. */
section.divide::before {
  content: ""; display: block; height: 1px; margin: 0 0 3.6rem;
  background: linear-gradient(90deg, transparent, var(--line) 12%, var(--line) 88%, transparent);
}

.sec { display: flex; align-items: center; gap: .8rem; margin-bottom: 1.15rem }
.sec h2 { margin: 0; font-size: 1.12rem; font-weight: 600; letter-spacing: -.01em }
.sec .aside { font-size: .86rem; color: var(--dimmer) }
.sec .aside a:hover { color: var(--gold) }
.sec .spacer { flex: 1 }

.panel { background: var(--panel); border: 1px solid var(--line); border-radius: var(--r) }

/* ---------- hero ---------- */
.hero {
  position: relative; min-height: 372px; display: flex; align-items: flex-end;
  overflow: hidden; border-radius: var(--r-lg); border: 1px solid var(--line);
}
.hero .bg { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover }
.hero .veil {
  position: absolute; inset: 0;
  background:
    linear-gradient(90deg, rgba(16,18,22,.97) 0%, rgba(16,18,22,.82) 42%, rgba(16,18,22,.15) 100%),
    linear-gradient(0deg, rgba(16,18,22,.92) 0%, rgba(16,18,22,0) 55%);
}
.hero .inner { position: relative; padding: 2.4rem 2.6rem; max-width: 62ch }
.kind { font-size: .78rem; color: var(--gold); letter-spacing: .02em }
.hero h1 { margin: .55rem 0 .6rem; font-size: 1.95rem; font-weight: 600; letter-spacing: -.025em;
  line-height: 1.2 }
.hero p { margin: 0; color: #c3c9d5 }
.hero .meta { margin-top: 1.4rem; display: flex; align-items: center; gap: 1rem }
.btn {
  display: inline-block; padding: .48rem 1.1rem; border: 1px solid var(--line);
  border-radius: 8px; font-size: .88rem; color: var(--text); background: rgba(24,27,33,.7);
}
.btn:hover { border-color: var(--gold-2); color: var(--gold) }
.btn.primary { background: var(--gold); color: #1b1405; border-color: transparent; font-weight: 600 }
.btn.primary:hover { background: #e0b05f; color: #1b1405 }
.when { color: var(--dimmer); font-size: .84rem }

/* ---------- secondary announcements ----------
   Given real presence instead of a two-line strip: a thin band under the hero read as an accident
   rather than a section. Each item carries its body, so there is something to actually read. */
.announce { display: grid; grid-template-columns: 1fr 1fr; gap: .9rem }
.announce .item { padding: 1.3rem 1.4rem; display: flex; flex-direction: column }
.announce .item .kind { font-size: .76rem }
.announce .item h3 { margin: .5rem 0 .4rem; font-size: 1rem; font-weight: 600 }
.announce .item p { margin: 0 0 1rem; color: var(--dim); font-size: .89rem; flex: 1 }
.announce .item .when { font-size: .82rem }

/* ---------- sort chips ---------- */
.sorts { display: flex; gap: .25rem }
.sorts a { padding: .32rem .75rem; border-radius: 7px; font-size: .85rem; color: var(--dim);
  border: 1px solid transparent }
.sorts a:hover { color: var(--text) }
.sorts a.on { color: var(--text); border-color: var(--line); background: var(--panel) }

/* ---------- the one carousel ---------- */
.railx { position: relative }
.railx .track {
  display: flex; gap: .9rem; overflow-x: auto; overflow-y: hidden;
  scroll-snap-type: x proximity; scroll-behavior: smooth;
  padding: 2px 2px 1rem; margin: 0 -2px;
  scrollbar-width: thin; scrollbar-color: var(--line) transparent;
}
.railx .track::-webkit-scrollbar { height: 8px }
.railx .track::-webkit-scrollbar-thumb { background: var(--line); border-radius: 4px }
.railx .track::-webkit-scrollbar-track { background: transparent }
.railx .track > * { flex: 0 0 292px; scroll-snap-align: start }
.arrows { display: flex; gap: .35rem }
.arrows button {
  width: 30px; height: 30px; border-radius: 8px; border: 1px solid var(--line);
  background: var(--panel); color: var(--dim); font-size: .9rem; line-height: 1; cursor: pointer;
}
.arrows button:hover { color: var(--text); border-color: #343b4a }

/* ---------- module card ----------
   The whole card is the link, so its children are spans; each one that should occupy a line has to
   be told to. */
.card { position: relative; overflow: hidden; padding: 1.15rem 1.25rem;
  display: flex; flex-direction: column; transition: border-color .12s, transform .12s }
/* A hairline of the module's own colour. Enough to stop a wall of cards reading as a spreadsheet,
   not enough to become decoration. */
.card::before { content: ""; position: absolute; top: 0; left: 0; right: 0; height: 2px;
  background: var(--accent, transparent); opacity: .5; transition: opacity .12s }
.card:hover::before { opacity: 1 }
.card:hover { border-color: #343b4a; transform: translateY(-2px) }
.card:hover .get { border-color: var(--gold-2); color: var(--gold) }
.card .head { display: flex; align-items: center; gap: .6rem; margin-bottom: .15rem }
.card .mark { width: 28px; height: 28px; flex: none; border-radius: 8px; display: flex;
  align-items: center; justify-content: center; font-size: .82rem; font-weight: 600;
  color: rgba(255,255,255,.75) }
.card h3 { margin: 0; font-size: .95rem; font-weight: 600; min-width: 0;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap }
.card .official { font-size: .72rem; color: var(--gold); flex: none }
.card .by { display: block; color: var(--dimmer); font-size: .82rem; margin: 0 0 .6rem 2.2rem }
.card .desc { display: block; margin: 0 0 .95rem; color: var(--dim); font-size: .88rem; flex: 1 }
.cats { display: flex; flex-wrap: wrap; gap: .3rem; margin-bottom: .95rem }
.cats span { font-size: .76rem; padding: .1rem .45rem; border-radius: 5px;
  background: rgba(255,255,255,.05); color: var(--dim) }
.card .foot { display: flex; align-items: center; gap: 1rem; font-size: .84rem; color: var(--dimmer) }
.card .foot .get { margin-left: auto; padding: .34rem .85rem; border-radius: 7px;
  border: 1px solid var(--line); color: var(--text); font-size: .84rem; transition: .12s }

/* ---------- breadcrumbs ---------- */
.crumbs { display: flex; align-items: center; gap: .45rem; font-size: .85rem;
  color: var(--dimmer); margin-bottom: 1.3rem }
.crumbs a:hover { color: var(--text) }
.crumbs .sep { opacity: .45 }
.crumbs .cur { color: var(--dim) }

/* ---------- store ---------- */
.storehead { position: relative; overflow: hidden; border-radius: var(--r-lg);
  border: 1px solid var(--line); padding: 1.7rem 1.9rem; margin-bottom: 1.8rem;
  background:
    radial-gradient(720px 220px at 88% -30%, rgba(212,162,76,.13), transparent 70%),
    linear-gradient(160deg, var(--panel-2), var(--panel) 62%) }
/* Same picture treatment as the shared band, so the store does not become the one page whose
   header behaves differently. */
.storehead.hasimg::before { content: ""; position: absolute; inset: 0;
  background-image: var(--phead-img); background-size: cover; background-position: center center;
  opacity: .48 }
.storehead.hasimg.flip::before { transform: scaleX(-1) }
.storehead.hasimg::after { content: ""; position: absolute; inset: 0;
  background: linear-gradient(90deg, rgba(16,18,22,.95) 38%, rgba(16,18,22,.4) 100%) }
.storehead.hasimg > * { position: relative; z-index: 1 }

.storehead h1 { margin: 0 0 .35rem; font-size: 1.5rem; font-weight: 600; letter-spacing: -.02em }
.storehead p { margin: 0; color: var(--dim); font-size: .92rem; max-width: 70ch }
.storehead .big { margin-top: 1.2rem; max-width: 460px }
.storehead .big input { width: 100%; padding: .68rem .9rem; border-radius: 9px;
  border: 1px solid var(--line); background: rgba(16,18,22,.7); color: var(--text);
  font: inherit; font-size: .92rem }
.storehead .big input::placeholder { color: var(--dimmer) }
.storehead .big input:focus { outline: 0; border-color: var(--gold-2);
  box-shadow: 0 0 0 3px rgba(212,162,76,.12) }

.store { display: grid; grid-template-columns: 240px minmax(0,1fr); gap: 2.2rem;
  align-items: start }
.filters { position: sticky; top: 84px; display: flex; flex-direction: column; gap: 1.4rem;
  padding: 1.15rem 1rem; background: var(--panel); border: 1px solid var(--line);
  border-radius: var(--r) }
.filters .grp h4 { margin: 0 0 .55rem; font-size: .76rem; text-transform: uppercase;
  letter-spacing: .09em; color: var(--dimmer); font-weight: 600 }
.filters .grp a { display: flex; align-items: center; justify-content: space-between; gap: .6rem;
  padding: .3rem .55rem; border-radius: 7px; font-size: .87rem; color: var(--dim) }
.filters .grp a:hover { background: rgba(255,255,255,.045); color: var(--text) }
.filters .grp a.on { background: rgba(212,162,76,.11); color: var(--gold) }
.filters .grp a i { font-style: normal; color: var(--dimmer); font-size: .79rem }
.filters .grp a.on i { color: var(--gold-2) }
.clear { font-size: .82rem; color: var(--dimmer) }
.clear:hover { color: var(--gold) }

.resbar { display: flex; align-items: center; gap: .8rem; margin-bottom: 1.15rem }
.resbar .count { font-size: .88rem; color: var(--dim) }
.results { display: grid; grid-template-columns: repeat(auto-fill, minmax(292px,1fr)); gap: .9rem }
.noresult { padding: 3rem 0; text-align: center; color: var(--dimmer) }

/* Active filters, echoed above the results so the current view is legible without reading the
   sidebar, and each one removable where you are looking. */
.active { display: flex; flex-wrap: wrap; gap: .4rem; margin-bottom: 1rem }
.active a { display: inline-flex; align-items: center; gap: .45rem; padding: .22rem .5rem .22rem .7rem;
  border-radius: 999px; border: 1px solid var(--gold-2); background: rgba(212,162,76,.1);
  color: var(--gold); font-size: .82rem }
.active a:hover { background: rgba(212,162,76,.18) }
.active a i { font-style: normal; opacity: .7; font-size: .95rem; line-height: 1 }

/* ---------- tools ---------- */
.tools { display: grid; grid-template-columns: repeat(auto-fill, minmax(268px,1fr)); gap: .9rem }
.tool { display: flex; gap: .85rem; align-items: flex-start; padding: 1.15rem 1.25rem;
  transition: border-color .12s }
.tool:hover { border-color: #343b4a }
.tool .ico { width: 32px; height: 32px; flex: none; border-radius: 8px; border: 1px solid var(--line);
  display: flex; align-items: center; justify-content: center; color: var(--gold); font-size: .95rem }
.tool .t { min-width: 0; flex: 1 }
.tool .t b { display: block; font-size: .92rem; font-weight: 600 }
.tool .t span { font-size: .85rem; color: var(--dim) }
.pill { flex: none; font-size: .74rem; color: var(--dimmer) }
.pill.live { color: var(--green) }
.pill.soon { opacity: .65 }

/* ---------- history ---------- */
.hist { display: grid; grid-template-columns: repeat(auto-fill, minmax(268px,1fr)); gap: .7rem }
.hist a { display: flex; gap: .7rem; align-items: center; padding: .7rem .85rem;
  border: 1px solid var(--line); border-radius: var(--r); background: var(--panel);
  transition: border-color .12s }
.hist a:hover { border-color: #343b4a }
.hist .mark { width: 28px; height: 28px; flex: none; border-radius: 8px; display: flex;
  align-items: center; justify-content: center; font-size: .8rem; font-weight: 600;
  color: rgba(255,255,255,.75) }
.hist .ico { width: 28px; height: 28px; flex: none; border-radius: 8px;
  border: 1px solid var(--line); display: flex; align-items: center; justify-content: center;
  color: var(--dim); font-size: .82rem }
.hist .t { min-width: 0; flex: 1 }
.hist .t b { display: block; font-size: .87rem; font-weight: 500;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap }
.hist .t span { font-size: .79rem; color: var(--dimmer) }
.hist .when { font-size: .77rem; color: var(--dimmer); flex: none }
.empty { color: var(--dimmer); font-size: .89rem; padding: 1.6rem 0 }

/* ---------- support ----------
   The art carries a figure on its right, so the copy sits left and the veil has to be gone before it
   reaches them; an even overlay would flatten the one thing the image is for. */
.support { position: relative; min-height: 286px; display: flex; align-items: center;
  overflow: hidden; border-radius: var(--r-lg); border: 1px solid var(--line) }
/* Framing unchanged; the mirror is the whole edit. The art has its figure on the left, and flipping
   it puts them opposite the copy instead of underneath it. */
.support .bg { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover;
  object-position: 72% 28%; transform: scaleX(-1) }
.support .veil { position: absolute; inset: 0; background:
  linear-gradient(90deg, rgba(16,18,22,.97) 0%, rgba(16,18,22,.9) 34%,
                  rgba(16,18,22,.35) 66%, rgba(16,18,22,0) 88%) }
.support .inner { position: relative; padding: 2.2rem 2.6rem; max-width: 68ch }
.support h3 { margin: 0 0 .55rem; font-size: 1.55rem; font-weight: 600; letter-spacing: -.025em;
  line-height: 1.15 }
.support p { margin: 0; color: #c3c9d5; font-size: .95rem }
.support .acts { margin-top: 1.5rem; display: flex; gap: .55rem }

/* ---------- footer ----------
   The catalogue figures live here rather than in a row of big numbers on the page. They are
   reference, not a headline. */
footer { max-width: 1280px; margin: 0 auto; padding: 1.4rem 1.5rem 3rem;
  border-top: 1px solid var(--line-soft);
  display: flex; flex-wrap: wrap; gap: .4rem 1.6rem;
  color: #4b5262; font-size: .8rem }
footer .figs { display: flex; gap: 1.1rem }
footer .figs b { color: var(--dim); font-weight: 500 }
footer .note { margin-left: auto }

/* ---------- not found / not built ----------
   Full bleed, sliding under the floating bar. The veil is transparent across the middle so the
   artwork keeps its subject, and opaque at the bottom where the copy sits. */
.notfound { position: relative; margin-top: -84px; min-height: calc(100vh - 84px);
  display: flex; align-items: flex-end; overflow: hidden }
.notfound .bg { position: absolute; inset: 0; width: 100%; height: 100%;
  object-fit: cover; object-position: center center }
.notfound .veil { position: absolute; inset: 0; background:
  linear-gradient(180deg, rgba(16,18,22,.62) 0%, rgba(16,18,22,.12) 32%,
                  rgba(16,18,22,.72) 74%, rgba(16,18,22,.98) 100%) }
.notfound .inner { position: relative; width: 100%; max-width: 1280px; margin: 0 auto;
  padding: 0 1.5rem 4.5rem }
.notfound .code { font-size: .78rem; letter-spacing: .16em; text-transform: uppercase;
  color: var(--gold) }
.notfound h1 { margin: .65rem 0 .65rem; font-size: 2.15rem; font-weight: 600;
  letter-spacing: -.03em; line-height: 1.15 }
.notfound p { margin: 0; max-width: 58ch; color: #c3c9d5 }
.notfound .acts { margin-top: 1.7rem; display: flex; gap: .6rem }

/* ---------- settings ----------
   Same two-column shape as the store, deliberately: a sticky rail on the left and one page of
   content on the right is already the app's idea of "browse a set of things". */
.prefs { display: grid; grid-template-columns: 232px minmax(0,1fr); gap: 2.2rem;
  align-items: start }
.prefnav { position: sticky; top: 84px; display: flex; flex-direction: column; gap: .12rem;
  padding: 1.15rem 1rem; background: var(--panel); border: 1px solid var(--line);
  border-radius: var(--r) }
.prefnav h4 { margin: 1.15rem 0 .5rem; font-size: .76rem; text-transform: uppercase;
  letter-spacing: .09em; color: var(--dimmer); font-weight: 600 }
.prefnav h4:first-child { margin-top: 0 }
.prefnav a { padding: .38rem .55rem; border-radius: 7px; font-size: .88rem; color: var(--dim) }
.prefnav a:hover { background: rgba(255,255,255,.045); color: var(--text) }
.prefnav a.on { background: rgba(212,162,76,.11); color: var(--gold) }

.settings { display: flex; flex-direction: column; gap: 1rem }
.set.notice { padding: .85rem 1.6rem; border-color: var(--gold-2) }
.set { padding: 1.4rem 1.6rem }
.set h3 { margin: 0 0 .3rem; font-size: 1.02rem; font-weight: 600 }
.set .hint { margin: 0 0 1.1rem; color: var(--dimmer); font-size: .86rem }
.field { display: grid; grid-template-columns: 200px minmax(0,1fr); gap: 1.2rem;
  align-items: center; padding: .75rem 0; border-top: 1px solid var(--line-soft) }
.field:first-of-type { border-top: 0; padding-top: 0 }
.field > label { font-size: .88rem; color: var(--dim) }
.field .val { display: flex; align-items: center; gap: .6rem; min-width: 0 }
.field .val input[type=text] { flex: 1; min-width: 0; padding: .5rem .7rem; border-radius: 8px;
  border: 1px solid var(--line); background: #0e1015; color: var(--text);
  font: inherit; font-size: .87rem }
.field .val input:focus { outline: 0; border-color: var(--gold-2) }
.field .val .browse { padding: .5rem .8rem; border-radius: 8px; border: 1px solid var(--line);
  color: var(--dim); font-size: .84rem; flex: none; cursor: pointer; user-select: none }
.field .val .browse:hover { color: var(--text); border-color: #343b4a }
/* A submit button is a <button>, which does not inherit the page font on its own. */
.field .val button.browse { font: inherit; font-size: .84rem; background: transparent }
.field .val .browse.danger:hover { color: var(--red); border-color: var(--red) }
.field > label .pill { margin-left: .45rem; vertical-align: 1px }
.field .ok { color: var(--green); font-size: .83rem; flex: none }
.field .warn { color: var(--gold); font-size: .83rem; flex: none }
.field .bad { color: var(--red); font-size: .83rem; flex: none }
.field .note { color: var(--dimmer); font-size: .83rem }
.switch { width: 38px; height: 22px; border-radius: 999px; background: var(--line);
  position: relative; flex: none; transition: background .12s }
.switch.on { background: var(--gold) }
.switch::after { content: ""; position: absolute; top: 3px; left: 3px; width: 16px; height: 16px;
  border-radius: 50%; background: #fff; transition: left .12s }
.switch.on::after { left: 19px }
.switch { cursor: pointer }

/* ---------- floating action ----------
   Sits above the page on every screen. Blurple, because the point is that it is recognisably
   Discord before anyone reads it. */
.fab {
  position: fixed; right: 22px; bottom: 22px; z-index: 90;
  display: flex; align-items: center; gap: .55rem;
  padding: .7rem 1.15rem; border-radius: 999px;
  background: #5865f2; color: #fff; font: 600 .88rem/1 var(--ui);
  box-shadow: 0 12px 30px -10px rgba(88,101,242,.65), 0 2px 10px rgba(0,0,0,.45);
  transition: background .12s, transform .12s;
}
.fab:hover { background: #4752c4; transform: translateY(-2px) }
.fab svg { width: 18px; height: 18px; flex: none }

/* ---------- splash ---------- */
.splash { position: fixed; inset: 0; display: flex; flex-direction: column;
  align-items: center; justify-content: center; gap: 1.1rem; background: var(--bg) }
.splash .logo { width: 96px; height: 96px; margin-bottom: .4rem }
.splash .name { font-size: 1.15rem; font-weight: 600; letter-spacing: -.01em }
.splash .name em { font-style: normal; color: var(--gold) }
.spinner { width: 30px; height: 30px; border-radius: 50%;
  border: 2px solid var(--line); border-top-color: var(--gold);
  animation: spin .75s linear infinite }
@keyframes spin { to { transform: rotate(360deg) } }
/* Fixed height and no transform: the block must not move when its text changes, or every swap reads
   as a jump. The fade is opacity only, and the server answers 204 when nothing changed so it does
   not replay on every poll. */
.splash #flavour { width: 34rem; text-align: center; height: 6.4rem }
.splash .say { margin: .2rem 0 .3rem; font-size: 1.05rem; line-height: 1.5; color: var(--text);
  animation: fade .45s ease-out }
.splash .who { margin: 0; font-size: .84rem; color: var(--gold); opacity: .8 }
.splash .step { margin: 1.5rem 0 0; font-size: .76rem; color: #4b5262 }
@keyframes fade { from { opacity: 0 } to { opacity: 1 } }

/* ---------- listing ---------- */
.listing-hero { position: relative; height: 420px; overflow: hidden;
  border-bottom: 1px solid var(--line); margin-top: -84px }
/* Explicitly centred on both axes: a cover is composed around its middle, and letting the crop
   drift to a corner is how a good piece of art ends up showing a shoulder. */
.listing-hero img { position: absolute; inset: 0; width: 100%; height: 100%;
  object-fit: cover; object-position: center center }
.listing-hero .veil { position: absolute; inset: 0;
  background: linear-gradient(180deg, rgba(16,18,22,.55) 0%, rgba(16,18,22,.25) 38%,
                              rgba(16,18,22,.97) 100%) }
.listing-hero .txt { position: absolute; left: 0; right: 0; bottom: 0;
  max-width: 1280px; margin: 0 auto; padding: 1.8rem 1.5rem }
.listing-hero h1 { margin: 0 0 .3rem; font-size: 1.85rem; font-weight: 600; letter-spacing: -.025em }
.listing-hero .tag { margin: 0; color: var(--dim) }
.chips { margin-top: .95rem; display: flex; flex-wrap: wrap; gap: .35rem }
.chip { font-size: .8rem; padding: .18rem .62rem; border: 1px solid var(--line);
  border-radius: 999px; background: rgba(24,27,33,.7); color: var(--dim) }
.chip.ok { border-color: var(--gold-2); color: var(--gold) }

.cols { display: grid; grid-template-columns: minmax(0,1fr) 300px; gap: 2rem; align-items: start;
  padding-top: 2.4rem }
.gallery { display: grid; grid-template-columns: repeat(auto-fill, minmax(240px,1fr));
  gap: .7rem; margin: 0 0 2rem }
.gallery img { width: 100%; aspect-ratio: 16/10; object-fit: cover; border-radius: var(--r);
  border: 1px solid var(--line) }

/* The side panel's lists. Each row is a flex line rather than inline text: the name takes whatever
   is left and wraps if it must, and the value beside it never does. Letting both wrap is what put
   "priority" and "default" on two lines and knocked every row out of alignment. */
.cols aside { padding: 1.3rem 1.4rem }
.cols aside h3 { margin: 1.5rem 0 .55rem; font-size: .74rem; text-transform: uppercase;
  letter-spacing: .09em; color: var(--dimmer); font-weight: 600 }
.cols aside h3:first-child { margin-top: 0 }
/* The column label for the values beside each name, sitting in the heading so the rows do not have
   to repeat it. */
.cols aside h3 .hint { float: right; text-transform: none; letter-spacing: 0; font-weight: 400 }
.cols aside ul { list-style: none; padding: 0; margin: 0 }
.cols aside li { display: flex; align-items: baseline; gap: .7rem; padding: .38rem 0;
  border-top: 1px solid var(--line-soft); font-size: .82rem }
.cols aside li:first-child { border-top: 0; padding-top: 0 }
.cols aside li code { flex: 1; min-width: 0; color: var(--dim); overflow-wrap: anywhere }
.cols aside li > span { flex: none; white-space: nowrap; color: var(--dimmer);
  font-size: .77rem }
.cols aside li.bad code { color: var(--red) }

.mdbody h1, .mdbody h2, .mdbody h3 { font-weight: 600; letter-spacing: -.015em; margin: 1.9rem 0 .5rem }
.mdbody h1 { font-size: 1.35rem } .mdbody h2 { font-size: 1.12rem } .mdbody h3 { font-size: 1rem }
.mdbody p, .mdbody ul { color: #cbd0da }
.mdbody ul { padding-left: 1.2rem }
.mdbody code { background: #0c0e12; border: 1px solid var(--line); border-radius: 5px;
  padding: .1rem .35rem; font-size: .88em }
.mdbody pre { background: #0c0e12; border: 1px solid var(--line); border-radius: var(--r);
  padding: 1rem; overflow-x: auto }
.mdbody pre code { border: 0; padding: 0; background: none }
.mdbody blockquote { margin: 1rem 0; padding: .5rem 1rem; border-left: 2px solid var(--gold-2);
  color: var(--dim) }
.mdbody table { border-collapse: collapse; width: 100%; margin: 1rem 0; font-size: .92rem }
.mdbody th, .mdbody td { border: 1px solid var(--line); padding: .45rem .7rem; text-align: left }
.mdbody th { background: rgba(255,255,255,.03) }
.mdbody a { color: var(--gold) }
/* Faded at both ends, like the section divider elsewhere in the app: a rule in a listing marks a
   change of subject, and a hard line across the column reads as a table that lost its rows. */
.mdbody hr { height: 1px; border: 0; margin: 2rem 0;
  background: linear-gradient(90deg, transparent, var(--line) 18%, var(--line) 82%, transparent) }

aside.panel { padding: 1.3rem }
aside.panel h3 { font-size: .82rem; font-weight: 600; color: var(--dim); margin: 1.3rem 0 .45rem }
aside.panel h3:first-child { margin-top: 0 }
aside.panel ul { list-style: none; margin: 0; padding: 0 }
aside.panel li { padding: .28rem 0; font-size: .86rem; display: flex;
  justify-content: space-between; gap: .5rem }
aside.panel li span { color: var(--dimmer) }
aside.panel li.bad code { color: var(--red) }
.install { display: block; margin-top: 1.4rem; padding: .62rem; border-radius: 8px;
  background: var(--gold); color: #1b1405; font: 600 .9rem/1 var(--ui); text-align: center;
  cursor: pointer; user-select: none }
.install.is-on  { background: transparent; border: 1px solid var(--green); color: var(--green) }
.install.is-off { background: transparent; border: 1px solid var(--line); color: var(--dimmer);
  cursor: default }

/* ---------- download centre ---------- */
.dlnow { padding: 1.35rem 1.55rem 1.2rem }
.dlnow.busy {
  background:
    radial-gradient(640px 200px at 90% -40%, rgba(212,162,76,.10), transparent 70%),
    var(--panel);
}
.dlrow { display: flex; align-items: center; gap: .85rem }
.dlrow .mark { width: 38px; height: 38px; flex: none; border-radius: 10px; display: flex;
  align-items: center; justify-content: center; font-weight: 700; color: #fff }
.dlrow .t { flex: 1; min-width: 0 }
.dlrow .t b { display: block; font-size: 1rem; letter-spacing: -.01em }
.dlrow .t span { display: block; color: var(--dimmer); font-size: .84rem }
.dlrow .figs { flex: none; text-align: right }
.dlrow .figs b { display: block; font-size: 1.32rem; font-weight: 600; color: var(--gold);
  letter-spacing: -.02em; font-variant-numeric: tabular-nums }
.dlrow .figs span { display: block; color: var(--dimmer); font-size: .79rem;
  font-variant-numeric: tabular-nums }

.dlbar { position: relative; height: 10px; margin: 1.15rem 0 .8rem; border-radius: 999px;
  background: rgba(14,16,20,.75); border: 1px solid var(--line-soft); overflow: hidden }
.dlbar i { display: block; height: 100%; border-radius: 999px;
  background: linear-gradient(90deg, var(--gold-2), var(--gold));
  transition: width .3s linear; position: relative }

/* A slow sheen travelling along the filled part, so a bar that is barely moving still reads as
   alive. Purely decorative, and it stops with the download because the element goes with it. */
.dlbar i::after { content: ""; position: absolute; inset: 0;
  background: linear-gradient(90deg, transparent, rgba(255,255,255,.28), transparent);
  animation: sheen 1.8s ease-in-out infinite }
@keyframes sheen { from { transform: translateX(-100%) } to { transform: translateX(100%) } }

.dlbar.idle i { width: 34% !important; animation: sweep 1.2s ease-in-out infinite }
.dlbar.idle i::after { animation: none }

.dlstats { display: flex; flex-wrap: wrap; align-items: center; gap: .5rem 1.4rem;
  font-size: .83rem; color: var(--dimmer); font-variant-numeric: tabular-nums }
.dlstats b { color: var(--text); font-weight: 600 }
.dlstats span { display: flex; align-items: baseline; gap: .3rem }

.dlqueue { display: flex; flex-wrap: wrap; gap: .35rem; margin-top: .9rem;
  padding-top: .9rem; border-top: 1px solid var(--line-soft) }
.dlqueue .qitem { padding: .2rem .55rem; border-radius: 999px; border: 1px solid var(--line);
  font-size: .78rem; color: var(--dimmer) }

.dlempty { display: flex; flex-direction: column; align-items: center; gap: .3rem;
  padding: 2.1rem 0 1.9rem; text-align: center }
.dlempty svg { width: 30px; height: 30px; color: var(--dimmer); opacity: .55;
  margin-bottom: .4rem }
.dlempty b { font-weight: 600 }
.dlempty span { color: var(--dimmer); font-size: .86rem; max-width: 42ch }

/* Rows shared by the pending queue and the history, so both read like the rest of the app. */
.hist .row { display: flex; align-items: center; gap: .8rem; padding: .75rem .95rem;
  border-radius: var(--r); border: 1px solid var(--line); background: var(--panel);
  margin-bottom: .5rem }
.hist .row .mark { width: 32px; height: 32px; flex: none; border-radius: 9px; display: flex;
  align-items: center; justify-content: center; font-weight: 700; color: #fff;
  font-size: .88rem }
.hist .row .t { flex: 1; min-width: 0 }
.hist .row .t b { display: block; font-size: .92rem }
.hist .row .t span { display: block; color: var(--dimmer); font-size: .82rem;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap }
.hist .row .acts { flex: none; display: flex; align-items: center; gap: .5rem;
  font-size: .82rem; color: var(--dimmer) }
.hist .row .acts .browse { padding: .34rem .7rem; border-radius: 7px;
  border: 1px solid var(--line); color: var(--dim); cursor: pointer }
.hist .row .acts .browse:hover { color: var(--text); border-color: #343b4a }
.hist .row .acts .browse.ghost { border-color: transparent }
.hist .row .acts .dot { width: 7px; height: 7px; border-radius: 50%; background: var(--dimmer) }
.hist .row .acts .dot.done { background: var(--green) }
.hist .row .acts .dot.failed { background: var(--red) }
.hist .row .acts .warn { color: var(--gold) }
.hist .row .acts .browse.gold { border-color: var(--gold-2); color: var(--gold) }
.hist .row .acts .browse.gold:hover { border-color: var(--gold); color: var(--gold) }
.hist .row .acts .browse.danger:hover { color: var(--red); border-color: var(--red) }
.hist .row .t b .pill { margin-left: .4rem; vertical-align: 1px }
.hist .row .t b { display: flex; align-items: center }

/* ---------- profile choice ----------
   Its own screen, so it borrows the splash's shape rather than the app's: nothing behind it has been
   decided yet. */
.choose { position: fixed; inset: 0; display: flex; align-items: center; justify-content: center;
  padding: 2rem }
.cbox { width: 100%; max-width: 420px; padding: 2rem 2rem 1.4rem; text-align: center }
.cbox img { width: 46px; height: 46px; margin: 0 auto .9rem }
.cbox h1 { margin: 0; font-size: 1.3rem; font-weight: 600; letter-spacing: -.02em }
.cbox > p { margin: .4rem 0 1.5rem; color: var(--dimmer); font-size: .87rem }

.clist { display: flex; flex-direction: column; gap: .4rem; text-align: left }
.citem { display: flex; align-items: center; gap: .6rem; width: 100%; cursor: pointer;
  padding: .7rem .85rem; border-radius: 9px; font: inherit; font-size: .92rem;
  color: var(--text); background: var(--panel-2); border: 1px solid var(--line) }
.citem:hover { border-color: var(--gold-2); background: rgba(212,162,76,.07) }
.citem .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--line); flex: none }
.citem.on .dot { background: var(--gold) }
.citem .t { flex: 1; text-align: left }
.citem .last { font-size: .74rem; color: var(--dimmer) }

.cremember { display: flex; align-items: center; gap: .5rem; margin-top: 1.2rem;
  cursor: pointer; font-size: .84rem; color: var(--dim); text-align: left }
.cremember input { width: 15px; height: 15px; accent-color: var(--gold); cursor: pointer }
.cfoot { margin: 1.3rem 0 0; font-size: .78rem; color: var(--dimmer) }

/* ---------- page band ----------
   Shared by the working pages. Short on purpose: the content below it is the reason you came. */
.phead { position: relative; overflow: hidden; display: flex; align-items: center; gap: 1.4rem;
  padding: 1.5rem 1.7rem; margin-bottom: 1.6rem;
  border: 1px solid var(--line); border-radius: var(--r-lg);
  background:
    radial-gradient(680px 200px at 88% -40%, rgba(212,162,76,.13), transparent 70%),
    linear-gradient(180deg, var(--panel-2), var(--panel));
}
.phead .pt { flex: 1; min-width: 0 }
.phead h1 { margin: 0; font-size: 1.45rem; font-weight: 600; letter-spacing: -.02em }
.phead p { margin: .3rem 0 0; color: var(--dim); font-size: .9rem; max-width: 68ch }
.phead .pa { flex: none; display: flex; align-items: center; gap: .5rem }
.phead .figbig { font-size: .88rem; color: var(--dim); white-space: nowrap }
.phead .figbig b { font-size: 1.5rem; font-weight: 600; color: var(--text);
  letter-spacing: -.02em; margin-right: .25rem }

/* Covered and centred rather than sized: the band has to take whatever artwork it is given, at
   whatever aspect ratio, without anyone measuring anything. The scrim behind the text is what makes
   that safe, so a bright picture cannot take the title with it. */
.phead.hasimg::before { content: ""; position: absolute; inset: 0;
  background-image: var(--phead-img); background-size: cover; background-position: center center;
  opacity: .5 }
.phead.hasimg.flip::before { transform: scaleX(-1) }
.phead.hasimg::after { content: ""; position: absolute; inset: 0;
  background: linear-gradient(90deg, rgba(16,18,22,.94) 34%, rgba(16,18,22,.35) 100%) }
.phead.hasimg > * { position: relative; z-index: 1 }

/* ---------- library ----------
   Cards in a grid, not a stack: a full-width card per module turns twenty modules into a very long
   scroll for information that fits in a third of the width. */
.libcards { display: grid; grid-template-columns: repeat(auto-fill, minmax(330px, 1fr));
  gap: .8rem; align-items: start }
.libcard { padding: 1.05rem 1.2rem; border-radius: var(--r);
  border: 1px solid var(--line); background: var(--panel) }
.libcard:hover { border-color: #343b4a }

.libcard .lhead { display: flex; align-items: center; gap: .8rem }
.libcard .mark { width: 38px; height: 38px; flex: none; border-radius: 10px; display: flex;
  align-items: center; justify-content: center; font-weight: 700; color: #fff }
.libcard .lhead .t { flex: 1; min-width: 0 }
.libcard .lhead .t b { display: block; font-size: 1rem; font-weight: 600; letter-spacing: -.01em }
.libcard .lhead .t span { display: block; color: var(--dimmer); font-size: .85rem;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap }

.libcard .lmeta { display: flex; flex-wrap: wrap; gap: .35rem; margin-top: .85rem }
.libcard .lmeta span { padding: .2rem .55rem; border-radius: 999px; border: 1px solid var(--line);
  font-size: .76rem; color: var(--dimmer); font-variant-numeric: tabular-nums }
.libcard .lmeta span.up { border-color: var(--gold-2); color: var(--gold) }
.libcard .lmeta span.src { max-width: 100%; overflow: hidden; text-overflow: ellipsis;
  white-space: nowrap }

.libcard .lacts { display: flex; justify-content: flex-end; gap: .45rem;
  margin-top: .9rem; padding-top: .85rem; border-top: 1px solid var(--line-soft) }
.libcard .lacts .browse { padding: .38rem .8rem; border-radius: 7px;
  border: 1px solid var(--line); color: var(--dim); font-size: .83rem; cursor: pointer }
.libcard .lacts .browse:hover { color: var(--text); border-color: #343b4a }
.libcard .lacts .browse.gold { border-color: var(--gold-2); color: var(--gold) }
.libcard .lacts .browse.gold:hover { border-color: var(--gold) }
.libcard .lacts .browse.danger:hover { color: var(--red); border-color: var(--red) }

/* A disabled module is still installed, so it stays legible rather than greyed into a placeholder.
   Only the colour drops; the card keeps its size and every one of its controls. */
.libcard.off { background: rgba(24,27,33,.5) }
.libcard.off .mark { filter: saturate(.25); opacity: .55 }
.libcard.off .lhead .t b { color: var(--dim) }

.libnote { margin: 1.2rem 0 0; color: var(--dimmer); font-size: .82rem; max-width: 72ch }

/* ---------- job progress ----------
   One element, whatever the outcome: running, finished or refused all render here, so the page
   never has to make room for a state it did not expect. */
.job { display: flex; align-items: center; gap: .55rem; min-height: 1.5rem;
  margin-top: .6rem; font-size: .83rem; color: var(--dimmer) }
.job:empty { display: none }
.job .phase { min-width: 0; overflow: hidden; text-overflow: ellipsis }
.job .ok { color: var(--green) }
.job .bad { color: var(--red) }
.job .bar { flex: 1; height: 5px; border-radius: 999px; background: var(--line);
  overflow: hidden; min-width: 60px }
.job .bar i { display: block; height: 100%; border-radius: 999px; background: var(--gold);
  transition: width .25s linear }

/* No Content-Length means no honest percentage, so the bar sweeps rather than inventing one. */
.job .bar.idle i { width: 35% !important; animation: sweep 1.1s ease-in-out infinite }
@keyframes sweep {
  0%   { transform: translateX(-100%) }
  100% { transform: translateX(340%) }
}
.health { margin-top: 1.1rem; font-size: .84rem }
.health .ok { color: var(--green); margin: 0 }
.problems { list-style: none; padding: 0; margin: 0 }
.problems li { padding: .25rem 0; color: var(--gold); display: block }
.problems li.error { color: var(--red) }
]]
