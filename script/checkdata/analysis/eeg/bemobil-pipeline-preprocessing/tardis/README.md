# Judo EEG pipeline (BeMoBIL / AMICA / ICLabel), version 2

Preprocessing for the mobile height-affordance EEG data: XDF import, trimming to the trials, bemobil
preprocessing, optional manual segment rejection, AMICA + ICLabel cleaning in two modes, and a QC report per
run plus a group table and a methods-text draft.

| Step | Script | Where | Per |
|---|---|---|---|
| 1 | `s01_judo_bemobil_import.m` | tardis (SLURM) | participant |
| 2A | `s02a_judo_bemobil_preprocess.m` | tardis (SLURM, same job as step 1) | participant |
| 2B | `s02b_judo_bemobil_manual_reject.m` | your PC, interactive | run |
| 2C | `s02c_judo_bemobil_amica_and_iclabel.m` | tardis (SLURM) | participant |
| 3 | `s03_judo_qc_summary_and_methods.m` | tardis or your PC | whole dataset |

Settings for every step are in `s00_judo_bemobil_config.m`. Helper functions are in `utils/`.

## Changes from version 1

Results of version 1 should not be mixed with version 2:

- **The two modes were filtered differently in version 1.** bemobil overwrote `preprocessed_and_ICA.set` with
  a 1 Hz high-passed copy, so the old "preprocessed" outputs were high-passed at 1 Hz while the old
  "rejected" outputs (weights copied onto unfiltered data) were not high-passed at all. Now both modes get
  the same 0.1 Hz high-pass.
- **The AMICA filter cutoff depended on the sampling rate.** The fixed order 1650 gives a 1.5 Hz cutoff only
  at 250 Hz (1.25 Hz at 500 Hz, 0.75 Hz at 1000 Hz). The order is now computed so the cutoff is 1.5 Hz at
  any sampling rate.
- **Manual marks** are taken directly from the viewer and tied to the data they were made on; only the marks
  file has to go back to tardis.
- **Errors are no longer hidden.** The print-crash workarounds and the toolbox edit are gone; a failed run is
  reported and makes the job fail at the end.
- **New:** motion channels kept and used for QC, bad segments as events, per-run HTML QC reports, group table,
  methods-text draft, provenance (settings, versions, code hash, job ID) in every output, reuse of finished
  work only when settings and inputs are unchanged, one MATLAB version for all steps.

## What each step does

**Step 1 - import.** Loads the EEG stream of every XDF file named `sub-<id>_ses-<ses>_*<task>*.xdf`
(other files in the folder are ignored), adds 10-5 template channel locations, types the motion channels
(Acc*, Gyro*, Quat*), and saves `2_raw-EEGLAB/.../sub-<run>_merged_EEG.set`. A BIDS-style copy goes to
`1_BIDS-data` (with fixed channel types, reference and counts; still not a validated BIDS dataset).

**Step 2A - trimming and preprocessing.** Keeps 1 s before the first `TrialOnset` to 1 s after the last
`TrialOffset`. Saves the motion channels separately (`6_single-subject-motion-analysis`), then runs bemobil's
preprocessing on the EEG channels: ZapLine-Plus (50 Hz), FCz added back, bad-channel detection, spherical
interpolation, average reference. Output: `3_EEG-preprocessing/sub-<run>/sub-<run>_preprocessed.set`.

**Step 2B - manual segment rejection (optional, local).** You mark bad segments in the scrolling viewer
(condition labels hidden, 1 Hz high-pass for display only). Saves the marks with your initials, the protocol
version and a fingerprint of the data they belong to.

**Step 2C - AMICA and ICLabel, in two modes.**

| Mode | AMICA is trained on | Reported as |
|---|---|---|
| `auto` | the full preprocessed run, AMICA's own sample rejection only | AMICA sample rejection only |
| `manualauto` | the run without the step 2B segments, plus AMICA's sample rejection | manual + AMICA rejection |

Everything else is identical in both modes. A copy of the data is high-pass filtered for AMICA (edge
1.75 Hz, cutoff 1.5 Hz at any sampling rate), dipoles are fitted, the weights are applied to the **full,
unfiltered** run, ICLabel (`lite`, most probable class) labels the components, and two cleaned versions are
written: eye components removed (`rmEye`) and eye + muscle components removed (`rmEyeMuscle`). Both are
high-pass filtered at 0.1 Hz (cutoff 0.05 Hz), with no low-pass. The segments excluded from AMICA training
stay in the data as events `bad_manual` and `bad_amica`. `manualauto` is skipped (and the QC report says why)
until valid marks exist for a run.

About the 1 s trim margin: the 0.1 Hz high-pass is about 33 s long, so epochs right at the start or end of a
run pick up a little of the filter's edge response. In simulations this was about 0.6 uV RMS (after baseline
correction) for an epoch 1 s from the edge, 0.2 uV at 5 s and negligible beyond 10 s, so it only touches the
first and last trial. Mirroring the data at the edges made it worse, so EEGLAB's default edge handling is used.

**Step 3 - group summary.** Collects all QC files into `qc_summary.csv` and writes `methods_text.md`: a
methods paragraph with the settings, software versions and group statistics that were actually used, the
runs with QC flags, and references.

## One-time setup

Versions: MATLAB R2022b (set once in `judo_env.sh`), EEGLAB 2026.0.0 with the plugins bemobil-pipeline
2.0.1, AMICA, ICLabel, ZapLine-Plus, clean_rawdata, firfilt, dipfit and the XDF importer.

```bash
cd /mnt/beegfs/home/$USER/1223-xplo-judo/02_Task/height_affordance/script/checkdata/analysis/eeg/tardis
bash setup_once.sh        # makes the AMICA binary executable, creates logs/, checks the plugins
```

If EEGLAB is not in `/mnt/beegfs/home/nguyen/matlab/toolbox/EEGLAB/eeglab2026.0.0`, change
`JUDO_EEGLAB_ROOT` in `judo_env.sh` (cluster) or `eeglab_root` in `s00_judo_bemobil_config.m`.

The bemobil toolbox no longer needs to be edited: step 2C calls bemobil's AMICA, dipole-fit and weight-copy
functions directly and does the ICLabel cleaning and its figures itself, so nothing tries to print UI
controls on the cluster.

**For step 2B on your PC:** copy `s00_local_paths_TEMPLATE.m` to `s00_local_paths.m` and set your local
`project_root` (the folder that contains `10_Data`) and `eeglab_root`. This file is ignored inside SLURM jobs
and listed in `.gitignore`.

Folder layout on tardis:

```text
/mnt/beegfs/home/$USER/1223-xplo-judo/
├── 02_Task/height_affordance/script/checkdata/analysis/eeg/tardis/   <- these scripts; submit jobs from here
│   └── logs/                                                          <- SLURM output and error logs
└── 10_Data/
    ├── sourcedata/sub-<id>/ses-<ses>/lslglobal/*.xdf
    └── derivatives/EEG_bemobil_pipeline/
        ├── 1_BIDS-data/  2_raw-EEGLAB/  3_EEG-preprocessing/  4_spatial-filters/4-1_AMICA/
        ├── 5_single-subject-EEG-analysis/  6_single-subject-motion-analysis/
        └── 8_quality-control/          <- QC files, figures, HTML reports, group/
```

## Running it

All commands are run on tardis **from the scripts folder**.

**Steps 1 + 2A.** Edit `participants_step1_to_2a.txt` (one ID per line), then:

```bash
bash submit_step1_to_2a.sh                       # one job per participant
bash submit_step1_to_2a.sh --then-2c             # also queue step 2C (auto) to start when 2A succeeds
sbatch run_step1_to_2a.sh 155T4T S001 heightaffordance   # a single participant
```

**Step 2B (local, per run).** Copy `3_EEG-preprocessing/sub-<run>/` (at least `..._preprocessed.set` and
`.fdt`) to the same place under your local `project_root`. In MATLAB run `s02b_judo_bemobil_manual_reject`,
enter the IDs and your initials, mark segments, press REJECT. Copy the two files it names back to the same
folder on tardis:

```text
sub-<run>_rejected_segments.mat
sub-<run>_rejected_segments.json
```

`..._preprocessed_and_rejected.set` is only for your own inspection; step 2C rebuilds the rejected data from
the marks, and only uses them if the data fingerprint still matches.

**Step 2C.** Edit `participants_step2c.txt`, then:

```bash
bash submit_step2c.sh                    # both modes
bash submit_step2c.sh participants_step2c.txt manualauto   # only the manual mode, e.g. after step 2B
sbatch run_step2c.sh 155T4T S001 heightaffordance          # a single participant
```

A job that hits the 12 h limit can be resubmitted: finished AMICA decompositions are reused.

**Step 3.**

```bash
sbatch run_step3_summary.sh heightaffordance
```

## Outputs

```text
3_EEG-preprocessing/sub-<run>/
    sub-<run>_preprocessed.set/.fdt/.json         .json: settings, input, data fingerprint, trimming, versions
    sub-<run>_rejected_segments.mat/.json          step 2B marks (samples of preprocessed.set)
6_single-subject-motion-analysis/sub-<run>/sub-<run>_motion.set   motion channels, same samples as the EEG
4_spatial-filters/4-1_AMICA/sub-<run>_<mode>/
    sub-<run>_<mode>_AMICA.set, _dipfitted.set/.json, AMICA output files
5_single-subject-EEG-analysis/sub-<run>_<mode>/
    sub-<run>_<mode>_preprocessed_and_ICA.set      weights + ICLabel, nothing removed, unfiltered
    sub-<run>_<mode>_cleaned_rmEye.set/.json       eye ICs removed, 0.1 Hz high-pass
    sub-<run>_<mode>_cleaned_rmEyeMuscle.set/.json eye + muscle ICs removed, 0.1 Hz high-pass
8_quality-control/sub-<run>/
    sub-<run>_qc-2a.json, _qc-2c_auto.json, _qc-2c_manualauto.json, figures (.png)
    sub-<run>_qc-report.html                       open this; figures are embedded
8_quality-control/group/qc_summary.csv, methods_text.md
```

Every saved dataset also carries its settings and provenance in `EEG.etc.judo`.

### Using the cleaned data

Which mode and level to analyse is a decision for the analysis plan; the QC report compares them per run.
To epoch while leaving out epochs that overlap the excluded segments:

```matlab
addpath('<scripts folder>/utils');
EEG = pop_loadset('filename', 'sub-<run>_auto_cleaned_rmEyeMuscle.set', 'filepath', '<folder>');
[EEG_ep, info] = judo_epoch(EEG, '^(NPose|Neutral|Fight)\d*$', [-0.2 0.8]);               % excludes bad_manual + bad_amica
[EEG_ep, info] = judo_epoch(EEG, '^(NPose|Neutral|Fight)\d*$', [-0.2 0.8], {'bad_manual'}); % manual marks only
```

The stored data have no low-pass filter; apply the one your analysis needs (e.g. 30 Hz for ERP plots).

## Quality control

`8_quality-control/sub-<run>/sub-<run>_qc-report.html` shows, per run:

- flags for review (thresholds in `bemobil_config.qc` in s00; nothing is removed automatically);
- recording and trimming, condition events, interpolated channels, ZapLine-Plus results;
- the step 2B marks (rater, protocol, blind or not, seconds removed);
- head motion over time with the segments each mode excluded;
- both modes side by side: training data, AMICA filter and rejection, data amount per component, iterations,
  ICLabel classes, dipole residual variance, motion-correlated components, components and variance removed
  per level, usable epochs and SNR per condition;
- per mode: ICLabel summary, scalp maps of removed and motion-correlated components, average responses per
  condition at the first of Cz/FCz/Pz/Fz plus global field power, AMICA convergence, a per-component table;
- bemobil's own step 2A figures, and the software versions, code hash and SLURM job of every step.

"Motion-correlated" components follow the head accelerometer/gyroscope (1-20 Hz, correlation or envelope
correlation above the thresholds). It is a hint for review, because ICLabel was trained on stationary data.
SNR compares each average with its plus-minus average (residual noise); use it to compare levels and modes.

## Manual rejection protocol, version 1 (draft: adapt and keep the version number in s00 in sync)

Mark:
- large movement or cable artifacts across many channels;
- electrode pops, jumps or saturation affecting many channels;
- broad muscle bursts across many channels;
- periods where the participant is clearly not doing the task.

Do not mark:
- blinks and eye movements (ICA removes them);
- a single bad channel (interpolation handles it, or flag it to the step 2A settings);
- short, local muscle activity in a few channels.

Mark generously around an artifact (about 0.5 s on each side). You do not see the condition labels while
marking; keep it that way. Write anything unusual into the Notes field.

## When things are recomputed

- **Step 2A** reuses `preprocessed.set` only if its `.json` shows the same settings and the same input file;
  otherwise it recomputes. Outputs from the previous pipeline version have no `.json`, so they are replaced.
- **Step 2B marks** are tied to the data they were made on. If step 2A produces different data, step 2C
  skips `manualauto` for that run and asks for new marks.
- **Step 2C** reuses AMICA and dipole fitting only if `dipfitted.json` shows the same AMICA settings, the same
  preprocessed data and the same marks. Cleaning, filtering and QC are always redone.

Outputs of the previous version in `5_single-subject-EEG-analysis/sub-<run>_preprocessed` and
`..._preprocessed_and_rejected` are not touched; delete them once you no longer need them.

## Troubleshooting

- **No log file:** `logs/` must exist before `sbatch` (the submit scripts and `setup_once.sh` create it).
- **"s00_judo_bemobil_config.m not found":** submit the job from the scripts folder.
- **A run failed:** the job continues with the other runs and fails at the end; the error is in
  `logs/<job>_<id>.err` and in the run's QC file. The QC report lists failed and skipped modes.
- **`manualauto` skipped:** the report says why (no marks yet, marks from the old version, or marks made on
  different data).
- **More than 1/5 of the channels detected as bad:** bemobil opens a warning dialog, which can fail without a
  display; check that run's data.
- **AMICA crashes before the first iteration:** bemobil retries with fewer threads automatically.
