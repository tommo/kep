-- notebook.lua — vault-local Lua helpers, auto-loaded into EVERY notebook in
-- this workspace (after the built-in mindo/nb API). Available in code cells and
-- to the research agent. A second copy at
--   ~/Library/Application Support/Mindo/notebook.lua
-- loads globally for all workspaces. Edits take effect on the next Run All
-- (which restarts the kernel).

-- Count case-insensitive occurrences of `term` in `text`.
function mentions(text, term)
  local n = 0
  for _ in text:lower():gmatch(term:lower()) do n = n + 1 end
  return n
end

-- Espresso shot-time verdict from Grind.md's dial-in table (1:2 ratio).
function shotVerdict(seconds)
  if seconds < 20 then return "under-extracted (sour) — grind finer"
  elseif seconds > 35 then return "over-extracted (bitter) — grind coarser"
  else return "balanced (25–35s)" end
end

-- Example of EXTENDING the built-in namespace: mindo.headings(name) → the ATX
-- headings of a workspace doc.
function mindo.headings(name)
  local out = {}
  for line in (mindo.readDoc(name) or ""):gmatch("[^\n]+") do
    if line:match("^#+%s") then out[#out + 1] = line end
  end
  return out
end
