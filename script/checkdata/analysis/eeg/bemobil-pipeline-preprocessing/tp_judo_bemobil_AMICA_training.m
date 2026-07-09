%% Step 1: Filter Optimization and AMICA Training
clear; clc; close all;

if ~exist('ALLCOM','var')
    eeglab;
end

% Load base configuration
run('tp_judo_bemobil_config.m');

%% 1. USER METADATA INPUT
prompt = { ...
    'Enter Participant ID (e.g., MH9HXJ):', ...
    'Enter Session ID (e.g., S001):', ...
    'Enter Task Name (e.g., heightaffordance):', ...
    'Enter Run ID (e.g., 001):' ...
};
dlgtitle = 'Step 1 - AMICA Training Selection';
dims = [1 50];
definput = {'MH9HXJ', 'S001', 'heightaffordance', '001'};
userInput = inputdlg(prompt, dlgtitle, dims, definput);

if isempty(userInput), error('Processing cancelled.'); end

participantID = userInput{1};
sessionID     = userInput{2};
taskName      = userInput{3};
runID         = userInput{4};

bids_base_string = sprintf('sub-%s_ses-%s_task-%s_run-%s', participantID, sessionID, taskName, runID);
input_filepath   = fullfile(bemobil_config.study_folder, bemobil_config.raw_EEGLAB_data_folder, sprintf('sub-%s', participantID), sprintf('ses-%s', sessionID), 'eeg');
output_filepath  = fullfile(bemobil_config.study_folder, bemobil_config.spatial_filters_folder_AMICA, sprintf('sub-%s', participantID), sprintf('ses-%s', sessionID), 'eeg');

if ~exist(output_filepath, 'dir'), mkdir(output_filepath); end

%% 2. LOAD & TRIM RAW MERGED DATA
target_merged_filename = sprintf('%s_%s', bids_base_string, bemobil_config.merged_filename);
EEG = pop_loadset('filename', target_merged_filename, 'filepath', input_filepath);

% Dynamic non-experiment trimming
allevents = {EEG.event.type}';
earliest_onset_latency = inf; latest_offset_latency = -inf;
for idx = 1:length(allevents)
    evt_type = allevents{idx};
    if startsWith(evt_type, 'TrialOnset') && ~isempty(regexp(evt_type, '\d+', 'match'))
        earliest_onset_latency = min(earliest_onset_latency, EEG.event(idx).latency);
    end
    if startsWith(evt_type, 'TrialOffset') && ~isempty(regexp(evt_type, '\d+', 'match'))
        latest_offset_latency = max(latest_offset_latency, EEG.event(idx).latency);
    end
end
if isinf(earliest_onset_latency) || latest_offset_latency == -inf
    earliest_onset_latency = EEG.event(1).latency; latest_offset_latency = EEG.event(end).latency;
end
removeindices = [0, max(1, earliest_onset_latency - EEG.srate); min(EEG.pnts, latest_offset_latency + EEG.srate), EEG.pnts];
EEG = eeg_eegrej(EEG, removeindices);

%% 3. CUSTOM STEP 1 FILTERING & ZAPLINE
% Pre-ICA Aggressive Filter (1.75 Hz Highpass, No Lowpass)
fprintf('\n--- Applying Step 1 Highpass Optimization Filter (1.75 Hz) ---\n');
EEG = pop_eegfiltnew(EEG, 'locutoff', 1.75, 'hicutoff', [], 'plotfreqz', 0); 

% Explicit Open ZapLine Line Noise Removal (Low Cutoff 49 Hz, No High Cutoff)
if isfield(bemobil_config, 'zaplineConfig') && ~isempty(bemobil_config.zaplineConfig)
    fprintf('\n--- Running Open ZapLine (Low Cutoff: 49 Hz) ---\n');
    % Line noise cleaner targeting ~50Hz band cleanly from 49Hz up
    EEG = clean_data_with_zapline_plus(EEG, 50, 'noisefreqs', [50], 'min_freq', 49);
end

%% 4. RUN SPATIAL DECOMPOSITION (AMICA)
[ALLEEG, EEG, CURRENTSET] = eeg_store(cat(1, [], [], []), EEG, 1);
fprintf('\n--- Launching AMICA Training Loop ---\n');
bemobil_process_all_AMICA(ALLEEG, EEG, CURRENTSET, bids_base_string, bemobil_config, 1);

fprintf('\n=== STEP 1 COMPLETE: Spatial Weights Generated ===\n');