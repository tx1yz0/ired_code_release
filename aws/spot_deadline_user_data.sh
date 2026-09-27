#!/usr/bin/env bash
set -euo pipefail

# Persist one absolute deadline so Spot stop/restart events do not reset the
# configured runtime budget. The timer powers the instance off; the persistent
# Spot request is then disabled until explicitly started again.
RUN_HOURS="${SUDOKU_RUN_HOURS:-56}"
if [[ ! "$RUN_HOURS" =~ ^[1-9][0-9]*$ ]]; then
  echo "SUDOKU_RUN_HOURS must be a positive integer." >&2
  exit 1
fi
STATE_DIR="/var/lib/ired-sudoku"
DEADLINE_FILE="$STATE_DIR/deadline-utc"
install -d -m 0755 "$STATE_DIR"

if [[ ! -f "$DEADLINE_FILE" ]]; then
  date -u -d "+${RUN_HOURS} hours" '+%Y-%m-%d %H:%M:%S UTC' > "$DEADLINE_FILE"
fi
DEADLINE="$(cat "$DEADLINE_FILE")"

cat > /etc/systemd/system/ired-sudoku-deadline.service <<'EOF'
[Unit]
Description=Power off Sudoku training instance at its absolute deadline

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl poweroff
EOF

cat > /etc/systemd/system/ired-sudoku-deadline.timer <<EOF
[Unit]
Description=${RUN_HOURS}-hour deadline for Sudoku training instance

[Timer]
OnCalendar=$DEADLINE
Persistent=true
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now ired-sudoku-deadline.timer
