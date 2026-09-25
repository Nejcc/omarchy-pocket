#!/bin/bash
# Live stress test for Pocket. Needs pocket.lua loaded in Hyprland.
#
# Takes over workspaces 8 and 9 for about a minute: opens four test terminals
# (class pockettest) in a dwindle grid on 9, pockets each one in turn and
# shows/hides it from 8, checking after every round trip that the whole grid is
# back pixel for pixel. Then 40 toggles with no pause, and tabs. Whatever was
# in your pocket before is released onto workspace 8 (pocketing a window
# replaces the pocket). Test windows are closed at the end.

ev() { hyprctl repl "$1" >/dev/null; }
disp() { hyprctl dispatch "$1" >/dev/null; }
geom() { hyprctl clients -j | jq -c '[.[]|select(.class=="pockettest")|{a:.address[-4:],ws:.workspace.name,f:.floating,x:.at[0],y:.at[1],w:.size[0],h:.size[1]}]|sort_by(.a)'; }
fail=0
ok=0

[[ $(hyprctl repl 'return type(pocket)') == table ]] || { echo "pocket.lua is not loaded"; exit 1; }

disp 'hl.dsp.focus({ workspace = "9" })'
for i in 1 2 3 4; do disp 'hl.dsp.exec_cmd("xdg-terminal-exec --app-id=pockettest")'; sleep 0.7; done
sleep 1
mapfile -t T < <(hyprctl clients -j | jq -r '.[]|select(.class=="pockettest")|.address')

for B in "${T[@]}"; do
  base=$(geom)
  disp "hl.dsp.focus({ window = \"address:$B\" })"; sleep 0.2
  ev 'pocket.adopt()'; sleep 0.5
  for r in 1 2 3; do
    disp 'hl.dsp.focus({ workspace = "8" })'; sleep 0.15
    ev 'pocket.toggle()'; sleep 0.25
    s=$(hyprctl clients -j | jq -c ".[]|select(.address==\"$B\")|{ws:.workspace.name,f:.floating}")
    [[ $s == '{"ws":"8","f":true}' ]] || { echo "${B: -4} r$r: not shown on 8: $s"; fail=1; }
    ev 'pocket.toggle()'; sleep 0.3
    act=$(hyprctl activeworkspace -j | jq -r .name)
    [[ $act == 8 ]] || { echo "${B: -4} r$r: hiding left us on workspace $act"; fail=1; }
    if [[ $(geom) == "$base" ]]; then ok=$((ok + 1)); else echo "${B: -4} r$r: grid differs: $(geom)"; fail=1; fi
  done
done
echo "round trips exact: $ok/12"

base=$(geom)
disp 'hl.dsp.focus({ workspace = "8" })'
for _ in $(seq 1 40); do ev 'pocket.toggle()'; done
sleep 0.5
[[ $(geom) == "$base" ]] && echo "40 rapid toggles: grid ok" || { echo "rapid toggles: grid differs: $(geom)"; fail=1; }

# A tab on a pocketed grid window: hiding sends the window home and parks the tab.
ev 'pocket.new_tab()'; sleep 1.5
ev 'pocket.hide()'; sleep 0.5
[[ $(geom) == "$base" ]] && echo "tab hide: grid ok" || { echo "tab hide: grid differs: $(geom)"; fail=1; }
parked=$(hyprctl clients -j | jq '[.[]|select(.class=="pocket" and .workspace.name=="special:pocket")]|length')
[[ $parked -ge 1 ]] && echo "tab hide: terminal parked" || { echo "tab hide: terminal not parked"; fail=1; }

# Clean up: the test windows, the tab it opened, and the placeholder.
tab=$(hyprctl clients -j | jq -r '[.[]|select(.class=="pocket")]|sort_by(.pid)|last|.address')
for a in "${T[@]}" "$tab" $(hyprctl clients -j | jq -r '.[]|select(.class=="pocket-slot")|.address'); do
  disp "hl.dsp.window.close({ window = \"address:$a\" })"
done

echo "FAIL=$fail"
exit $fail
