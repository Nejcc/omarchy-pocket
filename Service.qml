import QtQuick
import Quickshell
import Quickshell.Hyprland

// Pocket runs inside Hyprland, not the shell: pocket.lua holds the keybindings
// and window logic. This service loads it into Hyprland with `hyprctl eval`, so
// installing the plugin is the whole setup. Hyprland rebuilds its Lua state on
// every config reload, so it loads again after each one. pocket.lua sets the
// global `pocket`, so a config that still has the old dofile line (or a second
// load) is skipped instead of binding the keys twice.
Item {
  // Injected by omarchy-shell (the generic service loader).
  property var shell: null

  readonly property string luaPath: String(Qt.resolvedUrl("pocket.lua")).replace(/^file:\/\//, "")

  function load() {
    const path = luaPath.replace(/\\/g, "\\\\").replace(/"/g, "\\\"")
    // hyprctl eval prefixes "return", so wrap the statement in a function call.
    Quickshell.execDetached(["hyprctl", "eval",
      "(function() if not pocket then pcall(dofile, \"" + path + "\") end end)()"])
  }

  Component.onCompleted: load()

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && String(event.name) === "configreloaded") load()
    }
  }
}
