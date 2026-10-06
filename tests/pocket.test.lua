-- Offline checks against the real plugin with a small Hyprland stand-in.
-- Run: lua tests/pocket.test.lua [path/to/pocket.lua]
local source = arg[1] or "pocket.lua"
local passed = 0

local function fixture(home, provider)
  local window = { address = "0xa", class = "foot", pid = 123, tags = {},
    floating = false, fullscreen = 0, workspace = { name = home or "1" } }
  local state = { windows = { window }, active = window, workspace = "2", events = {}, calls = {} }
  local function lookup(selector)
    for _, w in ipairs(state.windows) do
      if selector == "address:" .. w.address then return w end
    end
  end
  local function action(kind)
    return function(options) return { kind = kind, options = options } end
  end
  local function load()
    -- A fresh environment models Hyprland replacing its Lua state on reload.
    local env = setmetatable({ io = { open = function() return nil end } }, { __index = _G })
    env.per_monitor_workspaces = provider
    env.dofile = function(path) return assert(loadfile(path, "t", env))() end
    env.o = { window = function() end, bind = function() end }
    env.hl = {
      get_windows = function() return state.windows end,
      get_active_window = function() return state.active end,
      get_active_workspace = function() return { name = state.workspace } end,
      get_active_monitor = function() return { width = 1920, height = 1080, scale = 1 } end,
      on = function(event, callback) state.events[event] = callback end,
      unbind = function() end, config = function() end,
      dsp = { focus = action("focus"), exec_cmd = action("exec"), window = {} },
      dispatch = function(call)
        state.calls[#state.calls + 1] = call
        local options = call.options
        local w = type(options) == "table" and lookup(options.window)
        if call.kind == "tag" then
          local tag = options.tag:sub(2)
          if options.tag:sub(1, 1) == "+" then
            w.tags[#w.tags + 1] = tag
          else
            for i = #w.tags, 1, -1 do
              if w.tags[i]:gsub("%*$", "") == tag then table.remove(w.tags, i) end
            end
          end
        elseif call.kind == "move" then
          w.workspace = { name = options.workspace }
        elseif call.kind == "float" then
          w.floating = options.action == "on"
        elseif call.kind == "focus" then
          if w then state.active = w end
          if options.workspace then state.workspace = options.workspace end
        end
      end,
    }
    for _, kind in ipairs({ "tag", "move", "float", "fullscreen", "resize", "center", "close", "swap" }) do
      env.hl.dsp.window[kind] = action(kind)
    end
    return assert(loadfile(source, "t", env))()
  end
  return window, state, load
end

local function check(name, run)
  run()
  passed = passed + 1
  print("PASS " .. name)
end

check("home survives a fresh Lua environment with no placeholder", function()
  local w, state, load = fixture()
  local pocket = load()
  pocket.adopt()
  pocket.show()
  assert(w.floating and w.workspace.name == "2")
  pocket = load()
  pocket.hide()
  assert(w.workspace.name == "1", "reload lost the adopted window's home")
  assert(not w.floating, "returning home should tile the window")
  assert(state.workspace == "2", "hiding should preserve the current workspace")
end)

check("workspace names round-trip without escaping or losing Unicode", function()
  local home = 'Display: "quoted" \\ ž:3\nline'
  local w, _, load = fixture(home)
  local pocket = load()
  pocket.adopt()
  pocket.show()
  for _, tag in ipairs(w.tags) do
    assert(not tag:find('["\\\n]'), "workspace text must be encoded in the tag")
  end
  load().hide()
  assert(w.workspace.name == home)
end)

check("switching pockets removes the old home tag", function()
  local w, state, load = fixture()
  local pocket = load()
  pocket.adopt()
  pocket.show()
  local other = { address = "0xb", class = "foot", tags = {}, floating = false, workspace = { name = "3" } }
  state.windows[#state.windows + 1] = other
  state.active = other
  pocket.adopt()
  for _, tag in ipairs(w.tags) do assert(not tag:find("pocket", 1, true), "released window retains a pocket tag") end
  assert(w.workspace.name == "1" and not w.floating)
  load().show()
  load().hide()
  assert(other.workspace.name == "3")
end)

check("a closed window cannot give its home to a reused address", function()
  local w, state, load = fixture()
  load().adopt()
  state.windows = {}
  state.events["window.destroy"]()
  local replacement = { address = w.address, class = "pocket", tags = { "pocket" }, floating = true, workspace = { name = "2" } }
  state.windows = { replacement }
  state.active = replacement
  load().hide()
  assert(replacement.workspace.name == "special:pocket")
end)

check("malformed home tags are ignored", function()
  for _, tag in ipairs({ "pocket-home-ws-f", "pocket-home-ws-nothex" }) do
    local w, _, load = fixture()
    w.tags = { "pocket", "pocket-home", tag }
    w.floating = true
    load().hide()
    assert(w.workspace.name == "special:pocket")
  end
end)

check("native terminal pockets still park on their hidden workspace", function()
  local w, _, load = fixture()
  w.class, w.tags, w.floating = "pocket", { "pocket" }, true
  load().hide()
  assert(w.workspace.name == "special:pocket" and w.floating)
end)

check("optional per-monitor adapter follows home through a swap and reload", function()
  local callback, registrations = nil, 0
  local provider = { integration = { version = 1, register = function(id, module)
    assert(id == "nejcc.pocket")
    callback = module.workspaces_remapped
    registrations = registrations + 1
  end } }
  local w, _, load = fixture("Left:1", provider)
  local pocket = load()
  pocket.adopt(); pocket.show()
  callback({ ["Left:1"] = "Right:1", ["Right:1"] = "Left:1" })
  pocket = load()
  pocket.hide()
  assert(w.workspace.name == "Right:1" and registrations == 2)
end)

check("absent or older provider keeps Pocket standalone", function()
  for _, provider in ipairs({ {}, { integration = { version = 99 } } }) do
    local w, _, load = fixture("1", provider)
    local pocket = load()
    assert(pocket.connect_workspaces() == false)
    pocket.adopt(); pocket.show(); pocket.hide()
    assert(w.workspace.name == "1")
  end
end)

check("explicit connection works when Pocket loads before the provider", function()
  local provider = {}
  local w, _, load = fixture("Left:1", provider)
  local pocket = load()
  pocket.adopt(); pocket.show()
  local callback
  provider.integration = { version = 1, register = function(_, module) callback = module.workspaces_remapped end }
  assert(pocket.connect_workspaces())
  callback({ ["Left:1"] = "Right:4" })
  pocket.hide()
  assert(w.workspace.name == "Right:4")
end)

print(passed .. " Pocket regression checks passed.")
