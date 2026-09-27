#!/usr/bin/env bash
set -euo pipefail

# Persist one absolute deadline so Spot stop/restart events do not reset the
# 24-hour budget. The timer powers the instance off; the persistent Spot
# request is then disabled until explicitly started again.
STATE_DIR="/var/lib/ired-sudoku"
DEADLINE_FILE="$STATE_DIR/deadline-utc"
install -d -m 0755 "$STATE_DIR"

if [[ ! -f "$DEADLINE_FILE" ]]; then
  date -u -d '+24 hours' '+%Y-%m-%d %H:%M:%S UTC' > "$DEADLINE_FILE"
fi
DEADLINE="$(cat "$DEADLINE_FILE")"

cat > /etc/systemd/system/ired-sudoku-deadline.service <<'EOF'
[Unit]
Description=Power off Sudoku training instance at its 24-hour deadline

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl poweroff
EOF

cat > /etc/systemd/system/ired-sudoku-deadline.timer <<EOF
[Unit]
Description=24-hour deadline for Sudoku training instance

[Timer]
OnCalendar=$DEADLINE
Persistent=true
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now ired-sudoku-deadline.timer
