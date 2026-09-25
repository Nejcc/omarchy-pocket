import QtQuick

// Pocket runs inside Hyprland, not the shell: pocket.lua holds the keybindings
// and window logic and is loaded from ~/.config/hypr/bindings.lua (see the
// README). This service is the plugin's entry point and does no work itself.
Item {
  // Injected by omarchy-shell (the generic service loader).
  property var shell: null
}
