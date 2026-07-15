#!/bin/bash
# Play DuneScape on a headless box, viewable in your browser.
#
#   ./play.sh          start everything (game + VNC bridge on port 6080)
#   ./play.sh stop     tear it all down
#
# Then open:  http://localhost:6080/vnc.html  → "Connect" → play with WASD.
# (In VS Code the port is auto-forwarded; check the PORTS panel if the
#  link doesn't resolve.)

set -u
cd "$(dirname "$0")"

DISP=:99
NOVNC_PORT=6080

stop_all() {
  pkill -f '_build/default/bin/main.exe' 2>/dev/null
  pkill -f "x11vnc.*${DISP}" 2>/dev/null
  pkill -f "websockify.*${NOVNC_PORT}" 2>/dev/null
  echo "stopped."
}

if [ "${1:-}" = "stop" ]; then stop_all; exit 0; fi

# 1. virtual display
if ! pgrep -x Xvfb >/dev/null; then
  Xvfb $DISP -screen 0 960x720x24 >/dev/null 2>&1 &
  sleep 1
fi

# 2. the game
pkill -f '_build/default/bin/main.exe' 2>/dev/null
sleep 0.3
dune build 2>&1 | head -5
DISPLAY=$DISP nohup dune exec bin/main.exe -- "$@" >/dev/null 2>&1 &
sleep 2

# 3. VNC server on the virtual display (localhost only, no password)
if ! pgrep -f "x11vnc.*${DISP}" >/dev/null; then
  x11vnc -display $DISP -localhost -forever -shared -nopw -quiet \
    >/dev/null 2>&1 &
  sleep 1
fi

# 4. noVNC web bridge
if ! pgrep -f "websockify.*${NOVNC_PORT}" >/dev/null; then
  websockify --web=/usr/share/novnc $NOVNC_PORT localhost:5900 \
    >/dev/null 2>&1 &
  sleep 1
fi

echo
echo "DuneScape is running."
echo "Open:  http://localhost:6080/vnc.html   then click Connect."
echo "Controls: WASD slide - Z undo - R restart - Esc menu - Enter confirm"
echo "Stop with: ./play.sh stop"
