## Overview

| Script | Step | Machine |
|---|---|---|
|1. s01_judo_bemobil_import.m | (import XDF → BIDS) | tardis, per participant |
|2. s02a_judo_bemobil_preprocess.m | (preprocessing) | tardis, per participant |
|3. s02b_judo_bemobil_manual_reject.m |	(manual segment rejection) | LOCAL PC, interactive, per participant x session x run |
|4. s02c_judo_bemobil_amica_and_iclabel.m | (AMICA + ICLabel) | tardis, per participant |
                                   

`run_pipeline.sh` already chains steps 1 → 2A → 2C in one SLURM job. Since manual rejection files won't exist yet on a first run, step 2C's "rejected" pass is simply skipped per-run (with a warning) and only the "preprocessed" pass runs. Once you've done step 3 and copied the results back, you resubmit step 2C alone (`run_step2c.sh`) to also get the "rejected" pass.

## What you need

**Version**
- Matlab/2022b
- EEGLAB 2026.0.0
- bemobil-pipeline2.0.1

**Folder structures on tardis**
``` text
/mnt/beegfs/home/$USER/
├── 1223-xplo-judo/
│   ├── 02_Task/
│   │   └── height_affordance/
│   │       └── script/
│   │           └── checkdata/
│   │               └── analysis/
│   │                   └── eeg/
│   │                       └── tardis/            # MATLAB scripts and jobs
│   │                           └── logs/          # Output messages and errors
│   └── 10_Data/
│       ├── sourcedata/
│       └── derivatives/
│           └── EEG_mobile_pipeline/
└── matlab/
    └── toolbox/
        └── EEGLAB/
            └── eeglab2026.0.0/
                └── plugins/
                    └── bemobil-pipeline2.0.1/
	     
```
## Step 1-2a:

On tardis:

```bash
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

At this point, for each run, you'll have on the cluster:
`.../3_EEG-preprocessing/sub-<bids_base_string>/..._preprocessed.set` and a `.../5_single-subject-EEG-analysis/sub-<bids>_raw/...` AMICA+ICLabel result.

## Step 2b: 

**a) Pull the preprocessed data down** from tardis to your local PC for the run(s) you want to manually inspect

**b) In local MATLAB** on your local PC, run `s02b_judo_bemobil_manual_reject`, and in the dialogs enter Participant ID / Session ID / Task / Run ID for that specific run. Repeat once per run (per participant/session/task/run combination) that needs manual rejection.

**c) Push the results back to the cluster** (same folder — it now also contains the `.mat` marks and the `preprocessed_and_rejected.set`)

Do (a)–(c) for every run across participants.


## Step 2c:

**Single participant:**
```bash
sbatch run_step2c.sh 155T4T S001 heightaffordance
```

**Multiple participants:** edit the `PARTICIPANTS` array in `submit_step2c.sh`, then:
``` bash
bash submit_step2c.sh
```

At this point, for each run, you'll have on the cluster:
`.../4_spatial-filters/4-1_AMICA/sub-<bids>_raw/...` AMICA+ICLabel result and `.../5_single-subject-EEG-analysis/sub-<bids>_raw/...` 

---

**One thing worth knowing:** because `force_recompute = 1` is hardcoded, everything will be recomputed, even though you already have that result from the first run — it's not wasted correctness-wise, just wasted compute time. 

## DEBUG

1. Edit the code for bemobil

Cleaning step in 2c will try to print an UI that contains brain dipoles which will cause error because print() is depricated from matlab2023. The relevant part is in:

*/matlab/toolbox/EEGLAB/eeglab2026.0.0/plugins/bemobil-pipeline2.0.1/AMICA_processing/bemobil_clean_with_iclabel.m* 

``` bash
% save on disk
if save_file_on_disk
    
    print(gcf, fullfile(out_filepath,[erase(out_filename,'.set') '_brain_dipoles.png']), '-dpng');
    savefig(fullfile(out_filepath,[erase(out_filename,'.set') '_brain_dipoles.fig']))

    close
    print(fig1,fullfile(out_filepath,[erase(out_filename,'.set') '_ICs_kept.png']),'-dpng')
    close
    EEG = pop_saveset( EEG, 'filename',erase(out_filename,'.set'),'filepath', out_filepath);
    disp('...done');
end

```

Replace that part with this code:

``` bash
% save on disk
if save_file_on_disk
    
    % Prepare output filename for the dipole PNG
    dipole_png_path = fullfile(out_filepath, [erase(out_filename, '.set') '_brain_dipoles.png']);
    dipole_saved = false;
    
    % --- METHOD 1: Try exportapp ---
    try
        disp('Attempting Method 1: EXPORTAPP...');
        exportapp(gcf, dipole_png_path);
        dipole_saved = true;
    catch err1
        warning('Method 1 (exportapp) failed: %s', err1.message);
    end
    
    % --- METHOD 3: Fallback - Delete uicontrol handles explicitly + print ---
    if ~dipole_saved
        try
            disp('Attempting Method 3: Explicit UI delete + PRINT...');
            % Create a temporary copy handle to avoid breaking the original fig if needed
            hDipole = gcf;
            delete(findall(hDipole, 'Type', 'uicontrol'));
            set(hDipole, 'Color', 'w');
            print(hDipole, dipole_png_path, '-dpng', '-r300');
            dipole_saved = true;
        catch err3
            warning('Method 3 (explicit delete + print) failed: %s', err3.message);
        end
    end
    
    % --- METHOD 2: Try print with -noui ---
    if ~dipole_saved
        try
            disp('Attempting Method 2: PRINT with -noui...');
            print(gcf, dipole_png_path, '-dpng', '-noui', '-r300');
            dipole_saved = true;
        catch err2
            warning('Method 2 (print -noui) failed: %s', err2.message);
        end
    end
    
    % Check if any method succeeded
    if ~dipole_saved
        error('All 3 figure export methods failed to save brain dipoles PNG.');
    end

    % Save MATLAB figure file
    savefig(fullfile(out_filepath, [erase(out_filename, '.set') '_brain_dipoles.fig']));
    close(gcf);

    % Save kept ICs figure (if fig1 exists and is valid)
    if exist('fig1', 'var') && isvalid(fig1)
        delete(findall(fig1, 'Type', 'uicontrol'));
        set(fig1, 'Color', 'w');
        print(fig1, fullfile(out_filepath, [erase(out_filename, '.set') '_ICs_kept.png']), '-dpng', '-r300');
        close(fig1);
    end

    % Save EEGLAB dataset
    EEG = pop_saveset(EEG, 'filename', erase(out_filename, '.set'), 'filepath', out_filepath);
    disp('...done');
end
```
