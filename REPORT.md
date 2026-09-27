# Local training report

Date: 26 September 2026. Machine: Apple Silicon, PyTorch 2.14 on the MPS GPU. Both runs used 10 diffusion steps, energy-landscape supervision, and inner-loop optimization.

Training is stopped. Nothing is running.

## Addition

Continuous elementwise addition of two rank-20 matrices (400 outputs per example). Data is sampled on the fly, so there is no downloaded set. Batch size 256. The run resumed from the step-1,000 checkpoint and finished 100,000 steps.

Validation mean squared error:

| Step | Validation MSE |
|---:|---:|
| 1,000 | 1.055 |
| 2,000 | 0.372 |
| 3,000 | 0.098 |
| 6,000 | 0.012 |
| 100,000 | 0.00388 |

Predicting zero on this data scores about 0.67, so the model was worse than that baseline at step 1,000 and clearly past it by step 3,000. The error flattened over the last several thousand steps.

Inference on 2,048 fresh problems, using the EMA weights in `results/ds_addition/model_mlp_diffsteps_10/model-100.pt`:

| Metric | Value |
|---|---:|
| MSE | 0.00388 |
| RMSE | 0.062 |
| MAE | 0.050 |
| Median problem MSE | 0.00387 |
| Worst problem MSE | 0.0054 |
| Entries within 0.05 | 56% |
| Entries within 0.10 | 89% |
| Zero-predictor MSE | 0.666 |

Targets lie in [−2, 2]. The model gets the sign and the rough magnitude. Individual entries are often off by about 0.05, and sometimes by about 0.15. This is approximate addition, not exact arithmetic.

## Sudoku

SATNet Sudoku: 9,000 training puzzles and 1,000 validation puzzles, each a 9×9 board stored as 729 one-hot values. The Sudoku convolution energy model, batch size 64, with given cells held fixed. The hard RRN test set (18,000 puzzles) was downloaded for the extra check the trainer runs every 10,000 steps. Training never reached that check.

Started 26 September 2026 at 10:20 local time. Stopped on request at step 2,011, after 3 hours 47 minutes. The last saved checkpoint is step 2,000: `results/ds_sudoku/model_sudoku_diffsteps_10/model-2.pt` (701 MB). `model-1.pt` is the step-1,000 checkpoint.

Denoising loss:

| Step | Denoising loss |
|---:|---:|
| 1 | 0.53 |
| 1,000 | 0.14 |
| 2,000 | 0.075 |
| 2,011 | 0.067 |

Empty-cell accuracy on the training batch used for the checkpoint sample:

| Step | Empty-cell accuracy | Fully consistent boards | Cells in a valid row, column, and box |
|---:|---:|---:|---:|
| 1,000 | 57.1% | 0% | 0.7% |
| 2,000 | 69.0% | 0% | 2.2% |

Empty-cell accuracy is the fraction of cells that were blank in the puzzle and match the solution digit. “Fully consistent” means every row, column, and 3×3 box contains each digit once. The third column is the fraction of cells whose row, column, and box each sum to 36, which is the SATNet validity check. The network is learning the right digits on many empty cells. It is not yet producing legal boards.

The logged validation accuracy (about 12% at both checkpoints) should not be compared with the training-batch numbers. In `diffusion_lib/denoising_diffusion_pytorch_1d.py`, the Sudoku validation path scores only the last puzzle in each batch against the whole batch. The training-batch numbers above use the full batch and are the ones to trust.

A training step takes about 4 seconds. Each 1,000-step checkpoint then spends about 45 minutes sampling the 1,000 validation puzzles (16 batches, roughly 2.5 minutes each), because every puzzle runs 10 diffusion steps with 20 energy-descent steps inside each one. At that pace the remaining schedule, 1.3 million steps, would take on the order of months on this machine.

## Setup changes

These were required to run on this Mac.

- `diffusion_lib/denoising_diffusion_pytorch_1d.py`: batches are cast to float32 before they move to the GPU. MPS has no float64 kernels, and the datasets were yielding float64.
- `train.py`: `--train-steps` sets the length of a run. The default is still 1,300,000.
- `sat_dataset.py`: RRN boards are read as text. They are 81-digit strings, and pandas was parsing them as integers, which dropped leading zeros.
- `.venv` and `requirements.txt`: Python 3.11, PyTorch 2.14, and the libraries the scripts import.
