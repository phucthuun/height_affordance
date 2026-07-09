%% tp_judo_bemobil_transfer_preprocessing.m
% Step 2: Spatial Weight Transfer, Custom Cleanup, and Target Epoching
% Merges AMICA weights from Step 1 onto the baseline data stream.
clear; clc; close all;

if ~exist('ALLCOM','var')
    eeglab;
end

% Load project-specific configuration
run('tp_judo_bemobil_config_conservative.m');

%% 1. USER METADATA INPUT
prompt = { ...
    'Enter Participant ID (e.g., MH9HXJ):', ...
    'Enter Session ID (e.g., S001):', ...
    'Enter Task Name (e.g., heightaffordance):', ...
    'Enter Run ID (e.g., 001):' ...
};
dlgtitle = 'Step 2 - Weight Transfer & Epoch Selection';
dims = [1 50];
definput = {'MH9HXJ', 'S001', 'heightaffordance', '001'};
userInput = inputdlg(prompt, dlgtitle, dims, definput);

if isempty(userInput), error('Processing cancelled by user.'); end

participantID = userInput{1}; 
sessionID     = userInput{2}; 
taskName      = userInput{3}; 
runID         = userInput{4};

bids_base_string = sprintf('sub-%s_ses-%s_task-%s_run-%s', participantID, sessionID, taskName, runID);

% Setup precise file paths matching configuration 
raw_filepath   = fullfile(bemobil_config.study_folder, bemobil_config.raw_EEGLAB_data_folder, sprintf('sub-%s', participantID), sprintf('ses-%s', sessionID), 'eeg');
ica_filepath   = fullfile(bemobil_config.study_folder, bemobil_config.spatial_filters_folder, bemobil_config.spatial_filters_folder_AMICA, bids_base_string);
epoch_out_path = fullfile(bemobil_config.study_folder, bemobil_config.single_subject_analysis_folder, sprintf('sub-%s', participantID), sprintf('ses-%s', sessionID), 'eeg');

if ~exist(epoch_out_path, 'dir'), mkdir(epoch_out_path); end

%% 2. LOAD RAW BASELINE DATA & LOAD STEP 1 ICA MATRIX
fprintf('\n--- Loading Untouched Raw Baseline Set ---\n');
target_merged_filename = sprintf('%s_%s', bids_base_string, bemobil_config.merged_filename);
EEG_raw = pop_loadset('filename', target_merged_filename, 'filepath', raw_filepath);

% Dynamic non-experiment trimming matching baseline experiment boundaries
allevents = {EEG_raw.event.type}';
earliest_onset_latency = inf; latest_offset_latency = -inf;
for idx = 1:length(allevents)
    evt_type = allevents{idx};
    if startsWith(evt_type, 'TrialOnset') && ~isempty(regexp(evt_type, '\d+', 'match'))
        earliest_onset_latency = min(earliest_onset_latency, EEG_raw.event(idx).latency);
    end
    if startsWith(evt_type, 'TrialOffset') && ~isempty(regexp(evt_type, '\d+', 'match'))
        latest_offset_latency = max(latest_offset_latency, EEG_raw.event(idx).latency);
    end
end
removeindices = [0, max(1, earliest_onset_latency - EEG_raw.srate); min(EEG_raw.pnts, latest_offset_latency + EEG_raw.srate), EEG_raw.pnts];
EEG_raw = eeg_eegrej(EEG_raw, removeindices);

% Load calculated spatial filters generated from Step 1
fprintf('\n--- Loading Spatial Matrix Components From Step 1 ---\n');
amica_set_name = sprintf('%s_%s', bids_base_string, bemobil_config.amica_filename_output);
EEG_ica_source = pop_loadset('filename', amica_set_name, 'filepath', ica_filepath);

%% 3. INTERPOLATE CHANNELS & MATRIX TRANSFER
fprintf('\n--- Validating Channel Counts and Aligning Track Configurations ---\n');

% Check if there's a mismatch between continuous raw data and AMICA weights
if EEG_raw.nbchan ~= EEG_ica_source.nbchan
    fprintf('Channel mismatch detected (Raw: %d vs. AMICA: %d). Aligning layouts...\n', EEG_raw.nbchan, EEG_ica_source.nbchan);
    
    raw_labels = {EEG_raw.chanlocs.labels};
    ica_labels = {EEG_ica_source.chanlocs.labels};
    
    % Find channels that are in AMICA but completely missing from Raw (like the reference FCz)
    missing_from_raw = setdiff(ica_labels, raw_labels);
    
    if ~isempty(missing_from_raw)
        for m = 1:length(missing_from_raw)
            fprintf('Adding missing channel back to raw stream: %s\n', missing_from_raw{m});
            % Append an empty zeroed row for the missing channel
            EEG_raw.data(end+1, :) = 0;
            EEG_raw.nbchan = size(EEG_raw.data, 1);
            % Assign it the correct label temporarily
            EEG_raw.chanlocs(end+1).labels = missing_from_raw{m};
        end
        % Standardize locations lookup to make sure the added channel has coordinates
        EEG_raw = pop_chanedit(EEG_raw, 'lookup', 'standard-10-5-cap385.elp');
    end
    
    % Now safely interpolate any channels to match the AMICA configuration exactly
    fprintf('Interpolating and re-ordering channels to match the AMICA template...\n');
    EEG_raw = pop_interp(EEG_raw, EEG_ica_source.chanlocs, 'spherical');
else
    fprintf('Channel configurations match perfectly (%d channels). Ready for transfer.\n', EEG_raw.nbchan);
end

% Clear any pre-existing/mismatched ICA activations to force clean recomputation
EEG_raw.icaact = [];

% Matrix Transfer: Inject spatial decomposition fields into the raw timeline
EEG_raw.icaweights  = EEG_ica_source.icaweights;
EEG_raw.icasphere   = EEG_ica_source.icasphere;
EEG_raw.icawinv     = EEG_ica_source.icawinv;
EEG_raw.icachansind = EEG_ica_source.icachansind;

fprintf('Running final dataset validation check...\n');
EEG_raw = eeg_checkset(EEG_raw);

%% 4. RUN AUTOMATED IC LABELLING
fprintf('\n--- Evaluating Component Signatures via ICLabel ---\n');
EEG_raw = pop_iclabel(EEG_raw, 'default'); 

% Compute activations if missing to extract top variance components
if isempty(EEG_raw.icaact)
    EEG_raw.icaact = eeg_geticaact(EEG_raw);
end

% Locate Top 30 components by absolute maximum activation variance
[~, sorted_idx] = sort(max(abs(EEG_raw.icaact), [], 2), 'descend');
top_30_comps = sorted_idx(1:min(30, length(sorted_idx)));

%% 5. GENERATE VARIANT 1: EYE ARTIFACT SUBTRACTION ONLY
fprintf('\n--- Generating Version 1: Eye Component Removal (Top 30 Components) ---\n');
% Extract the classification probability matrix from the correct ICLabel field
ic_probas = EEG_raw.etc.ic_classification.ICLabel.classifications;

% Class 3 = Eye in ICLabel classifier arrays
eye_components = [];
for ic = 1:size(ic_probas, 1)
    [~, max_cls] = max(ic_probas(ic, :));
    if max_cls == 3 && ismember(ic, top_30_comps)
        eye_components = [eye_components, ic];
    end
end

EEG_v1 = pop_subcomp(EEG_raw, eye_components, 0);

%% 6. GENERATE VARIANT 2: EYE + MUSCLE ARTIFACT SUBTRACTION
fprintf('\n--- Generating Version 2: Eye + Muscle Component Removal (Top 30 Components) ---\n');
% Class 2 = Muscle in ICLabel classifier arrays
eye_muscle_components = eye_components;
for ic = 1:size(ic_probas, 1)
    [~, max_cls] = max(ic_probas(ic, :));
    if max_cls == 2 && ismember(ic, top_30_comps)
        eye_muscle_components = [eye_muscle_components, ic];
    end
end

EEG_v2 = pop_subcomp(EEG_raw, eye_muscle_components, 0);

%% 7. APPLY ANALYTICAL FILTERS AND EXTRACT EPOCHS
variants = {EEG_v1, EEG_v2};
v_names  = {'v1_eye-removed', 'v2_eyemuscle-removed'};

for v = 1:2
    EEG_curr = variants{v};
    
    % Plan Filter Settings: Highpass 1 Hz, Lowpass 40 Hz
    fprintf('\n--- Filtering Version %s (1-40 Hz) ---\n', v_names{v});
    EEG_curr = pop_eegfiltnew(EEG_curr, 'locutoff', 1.0, 'hicutoff', 40.0, 'plotfreqz', 0);
    
    % Dynamically discover dynamic Neutral%d trigger markers
    curr_events = {EEG_curr.event.type};
    neutral_triggers = {};
    for ev = 1:length(curr_events)
        if startsWith(curr_events{ev}, 'Neutral') && ~isempty(regexp(curr_events{ev}, '\d+', 'match'))
            neutral_triggers = [neutral_triggers, curr_events{ev}];
        end
    end
    neutral_triggers = unique(neutral_triggers);
    
    if isempty(neutral_triggers)
        warning('No Neutral triggers detected in data stream for version %s!', v_names{v});
        continue;
    end
    
    % Extract Target Epoch: Window = [-200 ms to +1500 ms]
    fprintf('--- Extracting Epochs for Version %s ---\n', v_names{v});
    EEG_epoched = pop_epoch(EEG_curr, neutral_triggers, [-0.2, 1.5], 'newname', sprintf('%s_epochs', v_names{v}), 'epochinfo', 'yes');
    
    % Baseline Correction (-200ms to 0ms)
    EEG_epoched = pop_rmbase(EEG_epoched, [-200, 0]);
    
    % Save final epoched output structure
    final_output_name = sprintf('%s_%s_final_epoched.set', bids_base_string, v_names{v});
    pop_saveset(EEG_epoched, 'filename', final_output_name, 'filepath', epoch_out_path);
    fprintf('Successfully Saved: %s\n', fullfile(epoch_out_path, final_output_name));
end

fprintf('\n============= PROCESS COMPLETE =============\n');