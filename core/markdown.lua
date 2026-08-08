--[[
  Markdown -> HTML for untrusted listing bodies.

  A deliberately small subset, allowlist-only: whatever this file does not understand is escaped and
  shown as text. There is no passthrough for raw HTML, and no configuration flag to enable one --
  this renders inside the WebView that holds the hub's token, so an author-supplied <script> is a
  privilege escalation, not a formatting choice.

  Escaping happens first, on the whole line, and inline markup is applied afterwards to already-safe
  text. Doing it the other way round is how renderers grow injection holes.
]]

local M = {}

local function esc(s)
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

-- Only http(s) links survive; javascript:, data: and friends degrade to plain text. Anchors carry
-- target/rel so a click leaves the WebView instead of navigating it off localhost.
--
-- Both arguments arrive already escaped, because `inline` escapes the whole line before any markup
-- is matched. Escaping again here would render `&lt;` as `&amp;lt;`.
local function link(text, href)
  if not href:match("^https?://") then return text .. " (" .. href .. ")" end
  return ('<a href="%s" target="_blank" rel="noopener noreferrer">%s</a>'):format(href, text)
end

local function inline(s)
  s = esc(s)
  -- Code spans first: their content must not then be read as emphasis.
  local codes = {}
  s = s:gsub("`([^`]+)`", function(c)
    codes[#codes + 1] = c
    return "\1" .. #codes .. "\1"
  end)

  s = s:gsub("%[([^%]]*)%]%((%S-)%)", function(text, href) return link(text, href) end)
  s = s:gsub("%*%*([^*]+)%*%*", "<strong>%1</strong>")
  s = s:gsub("%f[%w_]__([^_]+)__%f[^%w_]", "<strong>%1</strong>")
  s = s:gsub("%*([^*]+)%*", "<em>%1</em>")

  return (s:gsub("\1(%d+)\1", function(i) return "<code>" .. codes[tonumber(i)] .. "</code>" end))
end

--- Three or more of the same mark, alone on a line: a horizontal rule.
--
-- All the same mark, deliberately. `-*-` is not a rule in any Markdown anyone writes, and accepting
-- it would quietly eat lines that were meant as text.
local function is_rule(s)
  local mark = s:match("^%s*([-*_])")
  if not mark then return false end
  local body = s:gsub("%s", "")
  return #body >= 3 and body == string.rep(mark, #body)
end

local function row_cells(line)
  local cells = {}
  for cell in line:gsub("^%s*|", ""):gsub("|%s*$", ""):gmatch("([^|]*)") do
    cells[#cells + 1] = cell:match("^%s*(.-)%s*$")
  end
  -- gmatch on an empty-capable pattern yields a trailing empty match.
  if cells[#cells] == "" then cells[#cells] = nil end
  return cells
end

--- Render Markdown to an HTML fragment.
function M.render(src)
  local out, i = {}, 1
  local lines = {}
  for line in (src .. "\n"):gmatch("(.-)\r?\n") do lines[#lines + 1] = line end

  local function flush_list(tag) out[#out + 1] = "</" .. tag .. ">" end

  local list_open
  while i <= #lines do
    local line = lines[i]

    -- fenced code
    local fence = line:match("^```%s*(%S*)")
    if fence then
      if list_open then flush_list(list_open); list_open = nil end
      local body = {}
      i = i + 1
      while i <= #lines and not lines[i]:match("^```") do
        body[#body + 1] = esc(lines[i])
        i = i + 1
      end
      out[#out + 1] = "<pre><code>" .. table.concat(body, "\n") .. "</code></pre>"
      i = i + 1

    else
      local hashes, text = line:match("^(#+)%s+(.*)$")
      local bullet       = line:match("^%s*[-*+]%s+(.*)$")
      local quote        = line:match("^>%s?(.*)$")
      local is_table_row = line:match("^%s*|.*|%s*$")

      if hashes then
        if list_open then flush_list(list_open); list_open = nil end
        local n = math.min(#hashes, 6)
        out[#out + 1] = ("<h%d>%s</h%d>"):format(n, inline(text), n)
        i = i + 1

      -- Ahead of the bullet test on purpose: "* * *" is a rule, and a bullet list whose only item
      -- is an asterisk is not a thing anyone writes.
      elseif is_rule(line) then
        if list_open then flush_list(list_open); list_open = nil end
        out[#out + 1] = "<hr>"
        i = i + 1

      elseif is_table_row then
        if list_open then flush_list(list_open); list_open = nil end
        local rows = {}
        while i <= #lines and lines[i]:match("^%s*|.*|%s*$") do
          rows[#rows + 1] = lines[i]; i = i + 1
        end
        -- Row 2 is the alignment rule; drop it rather than render it.
        local sep = rows[2] and rows[2]:match("^[%s|:%-]+$")
        out[#out + 1] = "<table><thead><tr>"
        for _, c in ipairs(row_cells(rows[1])) do
          out[#out + 1] = "<th>" .. inline(c) .. "</th>"
        end
        out[#out + 1] = "</tr></thead><tbody>"
        for r = sep and 3 or 2, #rows do
          out[#out + 1] = "<tr>"
          for _, c in ipairs(row_cells(rows[r])) do
            out[#out + 1] = "<td>" .. inline(c) .. "</td>"
          end
          out[#out + 1] = "</tr>"
        end
        out[#out + 1] = "</tbody></table>"

      elseif bullet then
        if not list_open then out[#out + 1] = "<ul>"; list_open = "ul" end
        out[#out + 1] = "<li>" .. inline(bullet) .. "</li>"
        i = i + 1

      elseif quote then
        if list_open then flush_list(list_open); list_open = nil end
        local body = {}
        while i <= #lines and lines[i]:match("^>") do
          body[#body + 1] = lines[i]:match("^>%s?(.*)$"); i = i + 1
        end
        out[#out + 1] = "<blockquote>" .. inline(table.concat(body, " ")) .. "</blockquote>"

      elseif line:match("^%s*$") then
        if list_open then flush_list(list_open); list_open = nil end
        i = i + 1

      else
        if list_open then flush_list(list_open); list_open = nil end
        local para = {}
        while i <= #lines and not lines[i]:match("^%s*$")
              and not lines[i]:match("^#+%s") and not lines[i]:match("^%s*[-*+]%s")
              and not lines[i]:match("^>") and not lines[i]:match("^```")
              and not lines[i]:match("^%s*|.*|%s*$")
              and not is_rule(lines[i]) do
          para[#para + 1] = lines[i]; i = i + 1
        end
        out[#out + 1] = "<p>" .. inline(table.concat(para, " ")) .. "</p>"
      end
    end
  end
  if list_open then flush_list(list_open) end

  return table.concat(out, "\n")
end

return M
