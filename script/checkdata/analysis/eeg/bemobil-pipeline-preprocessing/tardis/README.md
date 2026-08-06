## Overview

| Script | Step | Machine |
|---|---|---|
|1. s01_judo_bemobil_import.m  	|		(import XDF → BIDS)       | 	cluster, automatic, per participant|
|2. s02a_judo_bemobil_preprocess.m 	|	(preprocessing)            |	cluster, automatic, per participant|
|3. s02b_judo_bemobil_manual_reject.m	|	(manual segment rejection) 	| LOCAL PC, interactive, per run|
|4. s02c_judo_bemobil_amica_and_iclabel.m|	(AMICA + ICLabel)          |	cluster, automatic, per participant|
                                   

`run_pipeline.sh` already chains steps 1 → 2A → 2C in one SLURM job. Since manual rejection files won't exist yet on a first run, step 2C's "rejected" pass is simply skipped per-run (with a warning) and only the "preprocessed" pass runs. Once you've done step 3 and copied the results back, you resubmit step 2C alone (`run_step2c.sh`) to also get the "rejected" pass.

## Step 1-2A: on the cluster

SSH in and go to your script folder first:
```bash
ssh <username>@<cluster-address>
cd /mnt/beegfs/home/$USER/1223-xplo-judo   # or wherever your .m/.sh scripts live
```

**Single participant:**
```bash
sbatch run_step1_to_2a.sh 155T4T S001 heightaffordance
```

**Multiple participants:** edit the `PARTICIPANTS` array in `submit_step1_to_2a.sh`, then:
```bash
bash submit_step1_to_2a.sh
```

**Check progress:**
```bash
squeue -u $USER
tail -f logs/bemobil_<jobid>.out
```

At this point, for each run, you'll have on the cluster:
`.../3_EEG-preprocessing/sub-<bids_base_string>/..._preprocessed.set` and a `.../5_single-subject-EEG-analysis/sub-<bids>_raw/...` AMICA+ICLabel result.

## Step 2B: on your local PC (interactive — can't run on the cluster)

**a) Pull the preprocessed data down** for the run(s) you want to manually inspect:
```bash
rsync -avz <username>@<cluster-address>:/mnt/beegfs/home/<username>/1223-xplo-judo/10_Data/derivatives/EEG_bemobil_pipeline/3_EEG-preprocessing/sub-155T4T_ses-S001_task-heightaffordance_run-001/ \
  "C:\Data\Research\10_Data\derivatives\EEG_bemobil_pipeline\3_EEG-preprocessing\sub-155T4T_ses-S001_task-heightaffordance_run-001\"
```
(On Windows, `rsync` needs WSL/Git Bash/Cygwin, or use WinSCP/FileZilla instead — same source/destination paths.)

**b) In local MATLAB**, run `s02b_judo_bemobil_manual_reject`, and in the dialogs enter Participant ID / Session ID / Task / Run ID for that specific run. Repeat once per run (per participant/session/task/run combination) that needs manual rejection.

**c) Push the results back to the cluster** (same folder — it now also contains the `.mat` marks and the `preprocessed_and_rejected.set`):
```bash
rsync -avz "C:\Data\Research\10_Data\derivatives\EEG_bemobil_pipeline\3_EEG-preprocessing\sub-155T4T_ses-S001_task-heightaffordance_run-001\" \
  <username>@<cluster-address>:/mnt/beegfs/home/<username>/1223-xplo-judo/10_Data/derivatives/EEG_bemobil_pipeline/3_EEG-preprocessing/sub-155T4T_ses-S001_task-heightaffordance_run-001/
```

Do (a)–(c) for every run you want rejected-mode results for, across however many participants.

## Step 2C rerun: on the cluster (to add the "rejected" pass)

**Single participant:**
```bash
sbatch run_step2c.sh 155T4T S001 heightaffordance
```

**Multiple participants:** edit the `PARTICIPANTS` array in `submit_step2c.sh`, then:
```bash
bash submit_step2c.sh
```

Check the same way (`squeue -u $USER`, `tail -f logs/bemobil_amica_<jobid>.out`).

---

**One thing worth knowing:** because `force_recompute = 1` is hardcoded, this resubmission recomputes AMICA for the "preprocessed" pass too, even though you already have that result from the first run — it's not wasted correctness-wise, just wasted compute time. If that becomes annoying at scale, I can add a check that skips a mode's AMICA run when its output already exists on disk, so the resubmit only computes the "rejected" pass — just say the word.