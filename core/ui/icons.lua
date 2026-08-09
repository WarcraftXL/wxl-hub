--[[
  The icon set, vendored.

  Lucide, which is what the SVGs hand-written across this app already were: 24 by 24, no fill,
  currentColor stroke, round joins. Adopting it is less a change than an admission.

  Not from a CDN, and the reason is not taste. The content security policy in core/ui/page.lua names
  every host the app may reach and grants no `font-src` at all, so an icon font or a stylesheet from
  elsewhere is refused by our own rules. Loosening them to let icons in opens the same door to
  anything a listing could inject. The second reason is worse: the hub treats being offline as a
  normal state, and a set of icons that disappears with the network turns every button into a blank.

  Only what is used is here. Adding one is pasting the inner markup of its .svg from
  https://github.com/lucide-icons/lucide/tree/main/icons and keeping the same name, so what a module
  declares is searchable upstream.

  The wrapper is written here rather than in each template: stroke width belongs to the set, not to
  the caller, and one place to change it is the difference between a consistent sheet and a drifting
  one. Size is not set here at all. `svg.ico` in the theme is one em, so a mark inside a sentence
  follows the text it is in and only the places that want a fixed size say so.
]]

local M = {}

local PATHS = {
  ["activity"] = [==[<path d="M22 12h-2.48a2 2 0 0 0-1.93 1.46l-2.35 8.36a.25.25 0 0 1-.48 0L9.24 2.18a.25.25 0 0 0-.48 0l-2.35 8.36A2 2 0 0 1 4.49 12H2" />]==],
  ["arrow-right"] = [==[<path d="M5 12h14" /> <path d="m12 5 7 7-7 7" />]==],
  ["bell"] = [==[<path d="M10.268 21a2 2 0 0 0 3.464 0" /> <path d="M3.262 15.326A1 1 0 0 0 4 17h16a1 1 0 0 0 .74-1.673C19.41 13.956 18 12.499 18 8A6 6 0 0 0 6 8c0 4.499-1.411 5.956-2.738 7.326" />]==],
  ["book"] = [==[<path d="M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H19a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1H6.5a1 1 0 0 1 0-5H20" />]==],
  ["check"] = [==[<path d="M20 6 9 17l-5-5" />]==],
  ["chevron-left"] = [==[<path d="m15 18-6-6 6-6" />]==],
  ["chevron-right"] = [==[<path d="m9 18 6-6-6-6" />]==],
  ["database"] = [==[<ellipse cx="12" cy="5" rx="9" ry="3" /> <path d="M3 5V19A9 3 0 0 0 21 19V5" /> <path d="M3 12A9 3 0 0 0 21 12" />]==],
  ["download"] = [==[<path d="M12 15V3" /> <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" /> <path d="m7 10 5 5 5-5" />]==],
  ["info"] = [==[<circle cx="12" cy="12" r="10" /> <path d="M12 16v-4" /> <path d="M12 8h.01" />]==],
  ["files"] =[==[<path d="M15 2h-4a2 2 0 0 0-2 2v11a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V8" /> <path d="M16.706 2.706A2.4 2.4 0 0 0 15 2v5a1 1 0 0 0 1 1h5a2.4 2.4 0 0 0-.706-1.706z" /> <path d="M5 7a2 2 0 0 0-2 2v11a2 2 0 0 0 2 2h8a2 2 0 0 0 1.732-1" />]==],
  ["flask-conical"] = [==[<path d="M14 2v6a2 2 0 0 0 .245.96l5.51 10.08A2 2 0 0 1 18 22H6a2 2 0 0 1-1.755-2.96l5.51-10.08A2 2 0 0 0 10 8V2" /> <path d="M6.453 15h11.094" /> <path d="M8.5 2h7" />]==],
  ["layout-dashboard"] = [==[<rect width="7" height="9" x="3" y="3" rx="1" /> <rect width="7" height="5" x="14" y="3" rx="1" /> <rect width="7" height="9" x="14" y="12" rx="1" /> <rect width="7" height="5" x="3" y="16" rx="1" />]==],
  ["message-circle"] = [==[<path d="M2.992 16.342a2 2 0 0 1 .094 1.167l-1.065 3.29a1 1 0 0 0 1.236 1.168l3.413-.998a2 2 0 0 1 1.099.092 10 10 0 1 0-4.777-4.719" />]==],
  ["mountain"] = [==[<path d="m8 3 4 8 5-5 5 15H2L8 3z" />]==],
  ["package"] = [==[<path d="M11 21.73a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73z" /> <path d="M12 22V12" /> <polyline points="3.29 7 12 12 20.71 7" /> <path d="m7.5 4.27 9 5.15" />]==],
  ["pencil"] = [==[<path d="M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z" /> <path d="m15 5 4 4" />]==],
  ["star"] = [==[<path d="M11.525 2.295a.53.53 0 0 1 .95 0l2.31 4.679a2.123 2.123 0 0 0 1.595 1.16l5.166.756a.53.53 0 0 1 .294.904l-3.736 3.638a2.123 2.123 0 0 0-.611 1.878l.882 5.14a.53.53 0 0 1-.771.56l-4.618-2.428a2.122 2.122 0 0 0-1.973 0L6.396 21.01a.53.53 0 0 1-.77-.56l.881-5.139a2.122 2.122 0 0 0-.611-1.879L2.16 9.795a.53.53 0 0 1 .294-.906l5.165-.755a2.122 2.122 0 0 0 1.597-1.16z" />]==],
  ["triangle-alert"] = [==[<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3" /> <path d="M12 9v4" /> <path d="M12 17h.01" />]==],
  ["wrench"] = [==[<path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.106-3.105c.32-.322.863-.22.983.218a6 6 0 0 1-8.259 7.057l-7.91 7.91a1 1 0 0 1-2.999-3l7.91-7.91a6 6 0 0 1 7.057-8.259c.438.12.54.662.219.984z" />]==],
  ["x"] = [==[<path d="M18 6 6 18" /> <path d="m6 6 12 12" />]==],
}

local OPEN = '<svg class="%s" viewBox="0 0 24 24" fill="none" stroke="currentColor" '
          .. 'stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'

--- One icon, as markup. An unknown name draws nothing rather than raising: a module naming an icon
--- this build does not carry should cost that module its picture, not the page it is on.
function M.svg(name, class)
  local body = PATHS[name]
  if not body then return "" end
  return OPEN:format(class or "ico") .. body .. "</svg>"
end

function M.has(name)
  return PATHS[name] ~= nil
end

return M
