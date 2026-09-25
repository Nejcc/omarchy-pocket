-- Pocket (nejcc.pocket): one persistent window that goes wherever you go.
--
--   SUPER + M          show the pocket here / hide it again (it keeps running)
--   SUPER + CTRL + M   new terminal tab in the pocket
--   SUPER + SHIFT + M  put the focused window (browser, notes, ...) in the pocket
--
-- Pocket windows carry the "pocket" tag, so any app can be one. Terminals the
-- pocket opens itself hide on special:pocket. A window adopted from a tiled
-- grid hides by going back into that grid, in exactly the tile it came from:
-- while it is out, a placeholder window holds its place in the layout.
-- Tabs are a Hyprland group, which moves as one.
-- The functions are also global (`pocket.toggle()`) for `hyprctl eval`.

local M = {}

local HIDDEN = "special:pocket"
local SLOT_PARK = "special:pocket-slot"

-- Your default terminal (xdg-terminal-exec, as Omarchy launches it). tmux only
-- supplies the command bar along the bottom (see pocket.tmux.conf,
-- which sits next to this file wherever the plugin is installed).
local DIR = debug.getinfo(1, "S").source:match("^@(.*)/") or "."
M.terminal = "xdg-terminal-exec --app-id=pocket -e tmux -L pocket -f " .. DIR .. "/pocket.tmux.conf new-session"

-- The placeholder: a bare terminal that says where its window went.
M.slot = "[workspace " .. SLOT_PARK .. " silent] xdg-terminal-exec --app-id=pocket-slot -e sh -c "
  .. "'printf \"\\n   \\360\\237\\223\\214  In the pocket. Super+M brings it back here.\\n\"; exec sleep infinity'"

o.window("pocket", { float = true, center = true, size = { "(monitor_w*0.6)", "(monitor_h*0.6)" } })

local function sel(w)
  return "address:" .. w.address
end

local function here()
  return hl.get_active_workspace().name
end

local function has_tag(w, name)
  local tags = type(w.tags) == "table" and w.tags or { w.tags }
  for _, tag in ipairs(tags) do
    if tag and tag:gsub("%*$", "") == name then
      return true
    end
  end
  return false
end

local function find(pred)
  for _, w in ipairs(hl.get_windows()) do
    if pred(w) then
      return w
    end
  end
end

local function slot()
  return find(function(w) return w.class == "pocket-slot" end)
end

local function is_pocket(w)
  return has_tag(w, "pocket")
end

-- "pocket-home": adopted from a tiled grid, so it goes back there when hidden.
local function is_homed(w)
  return has_tag(w, "pocket-home")
end

function M.windows()
  local found = {}
  for _, w in ipairs(hl.get_windows()) do
    if is_pocket(w) then
      table.insert(found, w)
    end
  end
  return found
end

-- Tagged when they open, not by a window rule: rule tags are re-applied on
-- every rule refresh, so a terminal could never be taken out of the pocket.
hl.on("window.open", function(w)
  if w and w.class == "pocket" then
    hl.dispatch(hl.dsp.window.tag({ window = sel(w), tag = "+pocket" }))
  end
end)

-- A homed window closed while out: its placeholder has nothing left to hold.
hl.on("window.destroy", function()
  local ph = slot()
  if ph and not find(function(w) return is_homed(w) and w.address ~= ph.address end) then
    hl.dispatch(hl.dsp.window.close({ window = sel(ph) }))
  end
end)

-- Out of its grid and over here: floated, 60% of the monitor, centered. When
-- it leaves a grid, the placeholder is dropped in beside it and the two swap,
-- so the placeholder ends up in its tile and the gap that closes is the
-- placeholder's new one. The rest of the grid never moves.
-- Fullscreen windows refuse to swap, so a maximized pocket drops that first.
local function unfullscreen(w)
  if w.fullscreen and w.fullscreen ~= 0 then
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", window = sel(w) }))
  end
end

local function lift(w)
  local back = here()
  local ph = slot()
  unfullscreen(w)

  if not w.floating and ph then
    hl.dispatch(hl.dsp.focus({ window = sel(w) }))
    hl.dispatch(hl.dsp.window.move({ workspace = w.workspace.name, follow = false, window = sel(ph) }))
    hl.dispatch(hl.dsp.window.float({ action = "off", window = sel(ph) }))
    hl.dispatch(hl.dsp.window.swap({ window = sel(w), target = sel(ph) }))
  end
  if not w.floating then
    hl.dispatch(hl.dsp.window.float({ action = "on", window = sel(w) }))
  end

  local m = hl.get_active_monitor()
  hl.dispatch(hl.dsp.window.move({ workspace = back, follow = false, window = sel(w) }))
  hl.dispatch(hl.dsp.window.resize({
    x = math.floor(m.width / m.scale * 0.6), y = math.floor(m.height / m.scale * 0.6), window = sel(w),
  }))
  hl.dispatch(hl.dsp.window.center({ window = sel(w) }))
end

-- The same dance backwards: the window tiles in beside the placeholder, they
-- swap, and the placeholder leaves from the tile the window just vacated.
-- Everything runs in one Lua call, so the detour through the home workspace
-- is never drawn. Without a placeholder in a grid there is no tile to return
-- to, and it hides like any other pocket window.
local function send_home(w)
  local back = here()
  local ph = slot()
  if not ph or ph.floating or not ph.workspace or ph.workspace.name:match("^special:") then
    hl.dispatch(hl.dsp.window.move({ workspace = HIDDEN, follow = false, window = sel(w) }))
    return
  end

  unfullscreen(w)
  if w.group then
    hl.dispatch(hl.dsp.window.move({ out_of_group = true, window = sel(w) }))
  end
  hl.dispatch(hl.dsp.focus({ window = sel(ph) }))
  hl.dispatch(hl.dsp.window.move({ workspace = ph.workspace.name, follow = false, window = sel(w) }))
  hl.dispatch(hl.dsp.window.float({ action = "off", window = sel(w) }))
  hl.dispatch(hl.dsp.window.swap({ window = sel(w), target = sel(ph) }))
  hl.dispatch(hl.dsp.window.move({ workspace = SLOT_PARK, follow = false, window = sel(ph) }))
  if back ~= w.workspace.name then
    hl.dispatch(hl.dsp.focus({ workspace = back }))
  end
end

-- A homed window is "at home" while it is tiled in its grid.
local function at_home(w)
  return is_homed(w) and not w.floating
end

-- Brings the pocket here and focuses it. Homed windows are lifted out of their
-- grid; everything else (terminals and their tab group) just moves over.
-- Returns the first pocket window, or nil when the pocket is empty.
function M.show()
  local wins = M.windows()
  for _, w in ipairs(wins) do
    if at_home(w) then
      if w.workspace.name ~= here() then
        lift(w)
      end
    else
      hl.dispatch(hl.dsp.window.move({ workspace = here(), follow = false, window = sel(w) }))
    end
  end
  if wins[1] then
    hl.dispatch(hl.dsp.focus({ window = sel(wins[1]) }))
  end
  return wins[1]
end

-- Homed windows go back to their tile, the rest parks on the hidden workspace.
-- Homes first: they leave the tab group before the group is parked.
function M.hide()
  local rest
  for _, w in ipairs(M.windows()) do
    if is_homed(w) then
      if not at_home(w) then
        send_home(w)
      end
    else
      rest = rest or w
    end
  end
  if rest then
    hl.dispatch(hl.dsp.window.move({ workspace = HIDDEN, follow = false, window = sel(rest) }))
  end
end

function M.toggle()
  local active = hl.get_active_window()
  if active and is_pocket(active) and not at_home(active) then
    M.hide()
  elseif not M.show() then
    hl.dispatch(hl.dsp.exec_cmd(M.terminal))
  end
end

-- New terminal as a tab: the pocket becomes a Hyprland group (tabs) and the new
-- terminal auto-joins it because the group has focus when it opens.
function M.new_tab()
  local win = M.show()
  if win and at_home(win) then
    lift(win)
    hl.dispatch(hl.dsp.focus({ window = sel(win) }))
  end
  win = win and find(function(w) return w.address == win.address end)
  if win and not win.group then
    hl.dispatch(hl.dsp.group.toggle())
  end
  hl.dispatch(hl.dsp.exec_cmd(M.terminal))
end

-- Puts the focused window in the pocket without touching the grid: a tiled
-- window stays where it is until the pocket is shown somewhere else.
-- ponytail: one pocket at a time; the previous one is released where it
-- belongs (back in its tile, or here if it was a parked terminal).
function M.adopt()
  local active = hl.get_active_window()
  if not active or is_pocket(active) or active.class == "pocket-slot" then
    return
  end

  M.hide()
  for _, w in ipairs(M.windows()) do
    for _, tag in ipairs({ "-pocket", "-pocket*", "-pocket-home" }) do
      hl.dispatch(hl.dsp.window.tag({ window = sel(w), tag = tag }))
    end
    if w.workspace and w.workspace.name == HIDDEN then
      hl.dispatch(hl.dsp.window.move({ workspace = here(), follow = false, window = sel(w) }))
    end
  end

  hl.dispatch(hl.dsp.window.tag({ window = sel(active), tag = "+pocket" }))
  if not active.floating then
    hl.dispatch(hl.dsp.window.tag({ window = sel(active), tag = "+pocket-home" }))
    if not slot() then
      hl.dispatch(hl.dsp.exec_cmd(M.slot))
    end
  end
  hl.dispatch(hl.dsp.focus({ window = sel(active) }))
end

o.bind("SUPER + M", "Toggle pocket", M.toggle)
o.bind("SUPER + CTRL + M", "New tab in pocket", M.new_tab)
hl.unbind("SUPER + SHIFT + M") -- was Omarchy's Music launcher
o.bind("SUPER + SHIFT + M", "Put window in pocket", M.adopt)

-- Solid tab bar for window groups (the pocket's tabs), colored from the current
-- theme so it is readable over anything behind it. Applies to every group.
do
  local theme = {}
  local f = io.open(os.getenv("HOME") .. "/.local/state/omarchy/current/theme/colors.toml")
  if f then
    for line in f:lines() do
      local key, hex = line:match('^([%w_]+)%s*=%s*"#(%x+)"')
      if key then
        theme[key] = hex
      end
    end
    f:close()
  end
  local bg, fg, accent = theme.background or "1a1b26", theme.foreground or "c0caf5", theme.accent or "7aa2f7"

  hl.config({
    group = {
      groupbar = {
        height = 24,
        text_color = "rgb(" .. bg .. ")",
        text_color_inactive = "rgb(" .. fg .. ")",
        col = {
          active = "rgb(" .. accent .. ")",
          inactive = "rgb(" .. bg .. ")",
        },
      },
    },
  })
end

pocket = M
return M
