# AWS Sudoku training

> **Historical run configuration:** do not reuse this launcher as a paper reproduction. The IRED paper specifies 50,000 updates on one GPU with a total batch of 64. This launcher ran 1.3 million updates on eight GPUs with a total batch of 512. The recovered journal shows that the repeated test diagnostic peaked at step 10,000 (99.5534% blank-cell accuracy; 95.3% strict board consistency), then developed a widening generalization gap and collapsed near step 636,102. See [AWS_SUDOKU_RUN_REPORT.md](AWS_SUDOKU_RUN_REPORT.md) for the full curve, cost, and failure analysis.

The consolidated operational guide is [IRED Sudoku on AWS - Run Retrospective and Next-Run Playbook](output/pdf/IRED_Sudoku_AWS_Next_Run_Playbook.pdf).

## Run configuration

On an 8-GPU EC2 host, run:

```bash
bash aws/bootstrap_sudoku.sh
```

`aws/run_sudoku.sh` starts the README Sudoku schedule: 1.3 million total steps, 64 examples per GPU, 10 diffusion steps, energy-landscape supervision, and inner-loop optimization. It resumes from the newest checkpoint in `results/ds_sudoku/model_sudoku_diffsteps_10/`. The launch payload started from `model-2.pt` (step 2,000); training saves every 1,000 steps and retains the two newest checkpoints. SATNet validation runs every 10,000 steps; the 18,000-puzzle RRN test is skipped during training.

The trainer now supports per-process batches under Accelerate, enables DDP unused-parameter detection for the Sudoku model's conditional branches, keeps validation on the main GPU over the full validation set, loads MPS checkpoints on CPU before moving state to CUDA, writes checkpoints atomically, and can retain a rolling checkpoint window. The Sudoku validation metric now scores every puzzle in each batch.

The systemd service restarts after a Spot interruption and resumes from the latest checkpoint. The launch user-data installs an absolute 56-hour power-off deadline by default; set `SUDOKU_RUN_HOURS` to change it. The deadline survives stop/restart cycles. When training completes successfully, the launcher powers off the instance early. Monitor with:

```bash
sudo journalctl -u ired-sudoku.service -f
```

## Instance and cost target

Target one `p4d.24xlarge` with 8 NVIDIA A100 40 GB GPUs in `us-east-1`. On 26 September 2026 the on-demand rate was about $21.96/hour. Recent Spot observations across offered zones were $15.05–$18.40/hour; Spot prices and capacity change over time. `us-east-1a` had the lowest observed price at $15.97/hour but lacked capacity. The launched instance is in `us-east-1c`, whose latest observed price was $18.2519/hour. The request is capped at $18.40/hour.

The initial 18.8-hour estimate was too optimistic. From step 4,000 at 09:22 UTC to step 188,000 at 15:38 UTC on 27 September, observed progress was about 29,000 steps/hour, including periodic validations. At that rate, 1.3 million steps take about 44 hours from training start, with about 38 hours remaining at the 15:38 snapshot. The current 56-hour deadline leaves roughly 11 hours of headroom. At the request's $18.40/hour cap, 56 hours of GPU compute would cost at most $1,030.40, excluding EBS storage; actual Spot billing may be lower.

AWS approved the account’s P-class Spot quota at 96 vCPUs on 27 September 2026. The run is deployed as instance `i-04da43a860b64ad85` with Spot request `sir-yr3zm7kj`, using stop-on-interruption behavior and an $18.40/hour price cap. AWS resumes an interrupted stopped instance when capacity returns; a normal shutdown at completion disables the request until explicitly started again. The live shutdown deadline is 16:37:41 UTC on 29 September 2026.

## Run status snapshot

At 15:40 UTC on 27 September 2026, the instance was running, `ired-sudoku.service` was active with no service restarts, and the newest checkpoint was `model-188.pt` (step 188,000). All eight GPUs were active, with utilization ranging from 46% to 80% at the sample. The live deadline was extended to 16:37:41 UTC on 29 September 2026, 56 hours after the original deadline timer setup. This is a point-in-time snapshot; check the instance and checkpoints for current status.

## What is excluded

RRN is an extra, harder evaluation, not a training stage. Running all 18,000 RRN puzzles every 10,000 steps would add substantial time and cost. Run that evaluation separately after training if needed.

The starting local checkpoint is `results/ds_sudoku/model_sudoku_diffsteps_10/model-2.pt` at step 2,000. The preceding checkpoint is `model-1.pt` at step 1,000. Both are included in the launch payload for initial recovery.
