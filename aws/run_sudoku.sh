#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

source .venv/bin/activate

GPU_COUNT="${NPROC_PER_NODE:-$(nvidia-smi --list-gpus | wc -l | tr -d ' ')}"
if [[ "$GPU_COUNT" -lt 1 ]]; then
  echo "No CUDA GPUs detected." >&2
  exit 1
fi

ARGS=(
  --dataset sudoku
  --batch_size 64
  --train-steps 1300000
  --model sudoku
  --cond_mask True
  --supervise-energy-landscape True
  --use-innerloop-opt True
  --diffusion_steps 10
  --data-workers 4
  --split-batches False
  --evaluate-every 10000
  --skip-rrn-test
  --keep-last-checkpoints 2
)

CHECKPOINT_DIR="results/ds_sudoku/model_sudoku_diffsteps_10"
if compgen -G "$CHECKPOINT_DIR/model-*.pt" > /dev/null; then
  ARGS+=(--load-milestone latest)
fi

set +e
accelerate launch --multi_gpu --num_processes "$GPU_COUNT" train.py "${ARGS[@]}"
TRAIN_EXIT_CODE=$?
set -e

if [[ "$TRAIN_EXIT_CODE" -eq 0 ]]; then
  echo "Sudoku training completed; powering off the instance."
  sudo /usr/bin/systemctl poweroff
fi

exit "$TRAIN_EXIT_CODE"
