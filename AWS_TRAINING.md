# AWS Sudoku training

## Run configuration

On an 8-GPU EC2 host, run:

```bash
bash aws/bootstrap_sudoku.sh
```

`aws/run_sudoku.sh` starts the README Sudoku schedule: 1.3 million total steps, 64 examples per GPU, 10 diffusion steps, energy-landscape supervision, and inner-loop optimization. It resumes from the newest checkpoint in `results/ds_sudoku/model_sudoku_diffsteps_10/`. The launch payload started from `model-2.pt` (step 2,000); training saves every 1,000 steps and retains the two newest checkpoints. SATNet validation runs every 10,000 steps; the 18,000-puzzle RRN test is skipped during training.

The trainer now supports per-process batches under Accelerate, enables DDP unused-parameter detection for the Sudoku model's conditional branches, keeps validation on the main GPU over the full validation set, loads MPS checkpoints on CPU before moving state to CUDA, writes checkpoints atomically, and can retain a rolling checkpoint window. The Sudoku validation metric now scores every puzzle in each batch.

The systemd service restarts after a Spot interruption and resumes from the latest checkpoint. The launch user-data installs an absolute 24-hour power-off deadline that survives stop/restart cycles. When training completes successfully, the launcher also powers off the instance so it does not sit idle. Monitor with:

```bash
sudo journalctl -u ired-sudoku.service -f
```

## Instance and cost target

Target one `p4d.24xlarge` with 8 NVIDIA A100 40 GB GPUs in `us-east-1`. On 26 September 2026 the on-demand rate was about $21.96/hour. Recent Spot observations across offered zones were $15.05–$18.40/hour; Spot prices and capacity change over time. `us-east-1a` had the lowest observed price at $15.97/hour but lacked capacity. The launched instance is in `us-east-1c`, whose latest observed price was $18.2519/hour. The request is capped at $18.40/hour.

The revised schedule is estimated at about 18.8 hours: 12.3 hours for training, plus 6.5 hours for 130 full SATNet validations on the main GPU. These estimates assume 15× M4 speed per A100 for this small, launch-bound model and near-linear training scaling over eight GPUs. At the observed Spot rates that is about $283–$346, plus setup time and any interruption delay. On-demand for the same estimate is about $414. The hard 24-hour limit caps GPU compute at $441.60 at the request's maximum price, excluding EBS storage. These are planning estimates; observed throughput should replace them.

AWS approved the account’s P-class Spot quota at 96 vCPUs on 27 September 2026. The run is deployed as instance `i-04da43a860b64ad85` with Spot request `sir-yr3zm7kj`, using stop-on-interruption behavior and an $18.40/hour price cap. AWS resumes an interrupted stopped instance when capacity returns; a normal shutdown at completion disables the request until explicitly started again. The 24-hour deadline powers off the instance at the end of the window.

## Run status snapshot

At 09:22 UTC on 27 September 2026, the instance was running and `ired-sudoku.service` was active after the DDP conditional-branch fix. The newest checkpoint was `model-4.pt` (step 4,000); both checkpoint files were about 702 MiB, and all eight GPUs were reporting about 95% utilization. The fixed 24-hour shutdown deadline is 08:37:41 UTC on 28 September 2026. This is a point-in-time snapshot; check the instance and checkpoints for current status.

## What is excluded

RRN is an extra, harder evaluation, not a training stage. Running all 18,000 RRN puzzles every 10,000 steps would add substantial time and cost. Run that evaluation separately after training if needed.

The starting local checkpoint is `results/ds_sudoku/model_sudoku_diffsteps_10/model-2.pt` at step 2,000. The preceding checkpoint is `model-1.pt` at step 1,000. Both are included in the launch payload for initial recovery.
