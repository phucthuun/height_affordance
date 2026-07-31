%% Step 2A: Preprocessing & Trimming (Automated Batch over All Runs)
clear; clc; close all; 
% Force software OpenGL rendering (prevents copyobj GPU crashes)
opengl('save', 'software'); 
% Force figures to generate off-screen without popping up windows
set(0, 'DefaultFigureVisible', 'off');

if ~exist('ALLCOM','var')
    [ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab;
end

% Load base configuration
run('s00_judo_bemobil_config.m');
force_recompute = 1;

%% 1. USER METADATA INPUT (Participant, Session, Task)
prompt = { ...
    'Enter Participant ID (e.g., MH9HXJ):', ...
    'Enter Session ID (e.g., S001):', ...
    'Enter Task Name (e.g., heightaffordance):' ...
};
dlgtitle = 'Step 1A - Preprocess All Runs';
dims = [1 50];
definput = {'MH9HXJ', 'S001', 'heightaffordance'};
userInput = inputdlg(prompt, dlgtitle, dims, definput);

if isempty(userInput), error('Processing cancelled.'); end

participantID = userInput{1};
sessionID     = userInput{2};
taskName      = userInput{3};

% Input directory where merged EEGLAB files reside
input_filepath = fullfile(bemobil_config.study_folder, bemobil_config.raw_EEGLAB_data_folder, ...
    sprintf('sub-%s', participantID), sprintf('ses-%s', sessionID));

%% 2. AUTOMATICALLY DISCOVER ALL RUN FILES
search_pattern = sprintf('sub-%s_ses-%s_task-%s_run-*_%s', ...
    participantID, sessionID, taskName, bemobil_config.merged_filename);
run_files = dir(fullfile(input_filepath, search_pattern));

if isempty(run_files)
    error('No matching merged files found in: %s', input_filepath);
end

fprintf('\nFound %d run file(s) to process for participant %s.\n', length(run_files), participantID);

%% 3. BATCH PROCESS ALL DISCOVERED RUNS

for r = 1:length(run_files)
    target_merged_filename = run_files(r).name;
    
    % Extract Run ID automatically using regex
    runTokens = regexp(target_merged_filename, 'run-([a-zA-Z0-9]+)', 'tokens');
    if ~isempty(runTokens)
        runID = runTokens{1}{1};
    else
        runID = sprintf('%03d', r);
    end
    
    bids_base_string = sprintf('%s_ses-%s_task-%s_run-%s', participantID, sessionID, taskName, runID);
    
    fprintf('\n==================================================\n');
    fprintf(' Preprocessing Run %d/%d: %s\n', r, length(run_files), bids_base_string);
    fprintf('==================================================\n');

    % Load Dataset
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
        earliest_onset_latency = EEG.event(1).latency; 
        latest_offset_latency = EEG.event(end).latency;
    end

    removeindices = [0, max(1, earliest_onset_latency - EEG.srate); min(EEG.pnts, latest_offset_latency + EEG.srate), EEG.pnts];
    EEG = eeg_eegrej(EEG, removeindices);

    % Basic Preprocessing
    [ALLEEG, EEG_preprocessed, CURRENTSET] = bemobil_process_all_EEG_preprocessing(...
        bids_base_string, bemobil_config, ALLEEG, EEG, CURRENTSET, force_recompute);
end

fprintf('\n============ STEP 1A BATCH COMPLETE ============\n');
fprintf('Processed all %d runs for participant %s successfully.\n', length(run_files), participantID);