# AWS Sudoku Training Run Report

**Report date:** 30 September 2026  
**Region:** us-east-1  
**Training status:** completed at step 1,300,000; final checkpoint verified  
**Performance verdict:** unsuccessful at solving Sudoku

## Executive summary

The AWS run reached its planned 1.3 million training steps and wrote the final checkpoint, `results/ds_sudoku/model_sudoku_diffsteps_10/model-1300.pt`. A follow-up evaluation of 256 held-out SATNet puzzles completed successfully, but measured only **11.1164% accuracy on blank cells**. The solver produced **0% fully consistent Sudoku boards** and a **0% SAT-Net board score**. The cell accuracy is effectively the 1-in-9 uniform-guess reference; the model did not demonstrate useful Sudoku-solving ability.

The run was not a reproduction of the paper's Sudoku protocol. The paper specifies 50,000 updates on one RTX 2080 with a total batch of 64 and Adam at `1e-4`. The AWS launcher used 1.3 million updates on eight A100s with 64 examples per process, making the total batch 512 at the same learning rate. It therefore made 26 times as many optimizer updates and presented about 208 times as many training examples as the paper. This protocol change is the leading explanation for the failed result.

The training host was a `p4d.24xlarge` Spot instance with eight A100 GPUs. Cost Explorer recorded **45.198333 Spot instance-hours** and **$824.41 gross p4d compute charges**. Credits exactly offset the recorded p4d charges. The original instance is stopped, but its 100 GB EBS root volume remains attached, so storage charges can continue after this report's billing cutoff.

## Run and hardware

The job followed the repository's AWS Sudoku launcher: 1.3 million total steps, batch size 64 per GPU, 10 diffusion steps, energy-landscape supervision, inner-loop optimization, four data workers, and validation every 10,000 steps. It resumed from the local step-2,000 checkpoint. The 18,000-puzzle RRN evaluation was explicitly skipped during training.

| Workload | AWS host | Hardware and role |
|---|---|---|
| Main training | `p4d.24xlarge` Spot, us-east-1c | 8 NVIDIA A100 40 GB GPUs, 96 vCPUs, 1,152 GiB RAM; encrypted 100 GB gp3 root volume (3,000 IOPS, 125 MB/s). [AWS p4d specifications](https://docs.aws.amazon.com/ec2/latest/instancetypes/ac.html) |
| Initial validation attempt | `m7i.xlarge` On-Demand | 4 vCPUs, 16 GiB RAM; CPU evaluation was too slow to finish in the available validation window. [AWS M7i specifications](https://aws.amazon.com/ec2/instance-types/general-purpose/) |
| Final validation | `g4dn.xlarge` On-Demand | 1 NVIDIA T4 GPU, 4 vCPUs, 16 GiB RAM; completed the 256-puzzle GPU evaluation. [AWS G4 specifications](https://aws.amazon.com/ec2/instance-types/g4/) |

The p4d launched at 08:36 UTC on 27 September. Its Spot usage ended after the target checkpoint was reached, before the configured 56-hour shutdown deadline. Cost Explorer recorded 45.198333 p4d hours, about 10.8 hours below that deadline.

## Performance evaluation

The final checkpoint was loaded on a temporary validation clone. The test ran four batches covering 256 puzzles from the held-out SATNet validation split and exited successfully.

| Metric | Result | Interpretation |
|---|---:|---|
| Blank-cell accuracy | **11.1164%** | Fraction of originally blank cells whose predicted digit matched the solution. A uniform random choice among nine digits is 11.111%; this result is effectively at that reference level. |
| Sudoku consistency | **0%** | No evaluated prediction satisfied the code's strict row, column, and 3×3-box digit uniqueness checks. |
| `board_accuracy` | **0%** | The code's SAT-Net sum-based board score was zero. This is a validity score, not an exact-grid-match rate. |

These are final-checkpoint results, not an estimate from the training loss. The implementation computes cell accuracy over **blank cells only**; givens are excluded. The consistency metric is the clearest evidence here that the model did not return legal complete Sudoku boards.

## Why the result did not match the paper

### The training protocol was materially different

The paper's Appendix A and the AWS run used the following settings:

| Setting | Paper | AWS run | Difference |
|---|---:|---:|---:|
| Optimizer updates | 50,000 | 1,300,000 | 26× more |
| GPUs | 1 RTX 2080 | 8 A100 40 GB | Distributed training |
| Batch per process | 64 | 64 | Same local batch |
| Total batch | 64 | 512 | 8× larger |
| Learning rate | `1e-4` | `1e-4` | No retuning for the larger batch |
| Approximate sample presentations | 3.2 million | 664.704 million* | 207.72× more |
| Fixed training-set equivalents | about 356 | about 73,856* | 207.72× more |

\*The first 2,000 updates ran locally with batch 64; the remaining 1,298,000 used a total batch of 512 on AWS.

The distributed batch change came from launching eight processes with `--batch_size 64 --split-batches False`. The released trainer defaults to `split_batches=True`, which would divide a total batch of 64 across the eight processes. Hardware count alone is not the issue; the launcher changed the optimizer's effective batch and then ran far beyond the paper's stopping point.

### The model degraded after the local checkpoint

A separate diagnostic loaded the EMA weights from the local step-2,000 checkpoint and sampled the first eight puzzles from the unchanged SATNet validation split with the corrected evaluator. With a fixed seed, it measured **72.7528% blank-cell accuracy**, 0% fully consistent boards, and a 3.0864% sum-based board score. Every sampled output was finite. This is a small stochastic diagnostic rather than a benchmark, but it establishes that the starting EMA contained useful predictive signal. The final EMA's 11.1164% result shows that signal was lost during the AWS continuation.

Only the final two checkpoints were retained. The step-50,000 checkpoint and the validation history are no longer available, and the stopped p4d journal and final checkpoint are only on its attached EBS volume. Consequently, the remaining artifacts cannot distinguish between these two mechanisms:

1. training failed soon after switching to the total batch of 512 and distributed execution; or
2. training improved initially and later collapsed during the schedule of 1.3 million updates.

The evidence supports a training collapse after step 2,000, with the changed batch and excessive schedule as the primary suspects. It does not establish which one triggered the collapse first.

### The paper and released code are internally inconsistent

Exact reproduction is also blocked by conflicts in the authors' public materials:

- The paper says 50,000 Sudoku updates, while the released `train.py` hardcodes 1.3 million.
- The paper's architecture table specifies a final 3×3 convolution with nine outputs, while the released `SudokuEBM` uses a 1×1 convolution. This run used the released model.
- The released full-validation path passes `samples[-1]` to the metric even though `sample()` returns a batch tensor. That evaluates one prediction against the entire label batch through broadcasting. This fork corrected it to evaluate `samples`; the final 11.1164% result used the corrected path.
- The paper does not clearly map its reported 99.4% to the three metrics emitted by the release. Its SAT-Net comparator's 98.3% is a puzzle solve rate, while the release's metric named `accuracy` is blank-cell accuracy. With givens clamped, strict `consistency` is the closest released measure of solved puzzles; this run scored 0%.
- The release provides no dependency lock, random seed, pretrained Sudoku checkpoint, tagged experiment configuration, or multi-run variance.

The SATNet data itself is not the discrepancy. The local tensors contain 10,000 valid one-hot puzzles split 9,000/1,000 by the released loader, with 31–42 givens per puzzle, and every given agrees with its solution. The core public-code settings also match: ten energy landscapes, clue masking, contrastive landscape supervision, and 20 refinement steps per landscape.

## AWS cost record

Cost Explorer was queried on 30 September 2026 at 03:52 UTC. Its daily data was present through 29 September and may lag for later activity. Costs below are USD.

| Cost item | Recorded usage | Gross usage charge | Matching credits | Net recorded |
|---|---:|---:|---:|---:|
| p4d.24xlarge Spot compute | 45.198333 instance-hours | $824.41 | −$824.41 | $0.00 |
| gp3 EBS usage in the account during the run window* | 6.666667 GB-month | $0.53 | −$0.53 | $0.00 |
| Public IPv4 usage in the account during the run window* | 46.2025 address-hours | $0.23 | −$0.23 | $0.00 |
| **Recorded subtotal** |  | **$825.18** | **−$825.18** | **$0.00** |

\* Cost Explorer grouped these EBS and IPv4 amounts by usage type, not by this run's resource IDs, so they are account-level totals for the queried window rather than perfect per-resource attribution. The p4d Spot line is tied to the unique p4d training workload in that window. Credits shown are the actual matching Cost Explorer `Credit` records; this is not a statement about the account's overall bill or remaining credit balance.

The temporary CPU and GPU validation hosts ran for about 36m 38s on `m7i.xlarge` and 10m 39s on `g4dn.xlarge`. Their compute lines had not appeared in Cost Explorer at report time. Using the us-east-1 Linux On-Demand rates effective 1 September 2026 ($0.2016/hour and $0.526/hour, respectively), their estimated compute is **about $0.22 gross** before any credits. This estimate excludes any small delayed EBS, snapshot, or network charges. The temporary clone and validation image/snapshot were cleaned up after the test.

The reported training compute cost is substantially below the earlier 56-hour Spot cap of $1,030.40. That cap was a planning ceiling, not a forecast of final total project charges. The p4d's encrypted 100 GB gp3 volume remains attached to the stopped instance, so storage can keep accruing beyond the usage shown above; later billing data may also add validation-host charges.

## Conclusion and pitfalls

- **Operational completion succeeded; the modeling objective did not.** The run reached its requested step count and produced a checkpoint, but the evaluation shows no usable Sudoku-solving performance.
- **The run did not follow the paper's optimization protocol.** The 26× longer schedule and 8× larger total batch changed the experiment enough that its result cannot validate or refute the paper's reported model.
- **The released repository is not sufficient for exact reproduction.** Its training length and architecture disagree with the paper, and its original validation path is incorrect for batched predictions.
- **Do not use training loss as the success criterion.** The solver should pass an inexpensive held-out puzzle gate on both blank-cell accuracy and valid-board rate before a long GPU schedule is funded.
- **The evaluation is limited.** It covered 256 of the 1,000 SATNet validation puzzles, not the full validation split, and did not run the separate 18,000-puzzle RRN test. No multi-seed result or confidence interval was produced.
- **Chance comparison is only a reference.** 11.111% assumes uniform random choice among nine digits. It is not a measured baseline for this exact subset and does not diagnose why the model failed.
- **The reported `board_accuracy` name can mislead.** In this implementation it is a SAT-Net sum-based validity score, not the proportion of boards exactly equal to the answer. Use it alongside the stricter consistency metric and a direct solved-board rate.
- **The cost record is time-limited and partly account-scoped.** AWS billing data can arrive later, EBS and IPv4 usage were not resource-tagged in this query, and the retained root volume may continue to bill.

For a future attempt, train from scratch on one GPU with total batch 64, Adam `1e-4`, a fixed seed, and exactly 50,000 updates. Save checkpoints and corrected validation metrics at least every 1,000 updates, retain the full history, and record both online and EMA model health. Evaluate all 1,000 SATNet test puzzles at step 50,000; run RRN only after the in-distribution model passes. An A/B run of the paper's 3×3 final convolution and the release's 1×1 convolution is needed to resolve that architecture conflict. Do not fund another multi-day p4d schedule until a cheap single-GPU run shows nonzero solved-board production and a stable learning curve.

## Evidence and method

- Repository configuration: `aws/run_sudoku.sh`, `AWS_TRAINING.md`, `sat_dataset.py`, and `diffusion_lib/denoising_diffusion_pytorch_1d.py`.
- AWS checks: EC2 instance/volume and Spot request state; CloudTrail launch/stop/clone events; Cost Explorer usage and `Credit` records; AWS Price List API for the two validation host rates.
- Evaluation results: final step-1,300,000 checkpoint, 256 SATNet validation puzzles, four batches; final metrics reported by the repository's Sudoku evaluator.
- Reproduction comparison: the IRED paper Appendix A and Table 10, the authors' released `train.py`, `models.py`, and validation implementation, and the SAT-Net paper's puzzle-level 98.3% result.
- Local checkpoint diagnostic: EMA at step 2,000, first eight SATNet validation puzzles, fixed seed, corrected full-batch metric.
