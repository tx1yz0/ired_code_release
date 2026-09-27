#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_USER="$(id -un)"
cd "$REPO_DIR"

PYTHON_BIN="${PYTHON_BIN:-/opt/pytorch/bin/python}"
"$PYTHON_BIN" -m venv --system-site-packages .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt

SERVICE_FILE="/etc/systemd/system/ired-sudoku.service"
sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=IRED Sudoku training
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$RUN_USER
WorkingDirectory=$REPO_DIR
ExecStart=$REPO_DIR/aws/run_sudoku.sh
Restart=on-failure
RestartSec=30
StartLimitIntervalSec=0

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now ired-sudoku.service
echo "Training logs: sudo journalctl -u ired-sudoku.service -f"
