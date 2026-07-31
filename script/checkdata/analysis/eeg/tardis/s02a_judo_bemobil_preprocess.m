function s02a_judo_bemobil_preprocess(participantID, sessionID, taskName)
%% Step 2A: Preprocessing & Trimming (HPC Tardis Version)
% Usage:
% matlab -batch "s02a_judo_bemobil_preprocess('MH9HXJ', 'S001', 'heightaffordance')"

if isunix
    opengl('save', 'software');
    set(0, 'DefaultFigureVisible', 'off');
end

if ~exist('ALLCOM','var')
    [ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab;
end

run('s00_judo_bemobil_config.m');
force_recompute = 1;

input_filepath = fullfile(bemobil_config.study_folder, bemobil_config.raw_EEGLAB_data_folder, ...
    sprintf('sub-%s', participantID), sprintf('ses-%s', sessionID));

search_pattern = sprintf('sub-%s_ses-%s_task-%s_run-*_%s', ...
    participantID, sessionID, taskName, bemobil_config.merged_filename);
run_files = dir(fullfile(input_filepath, search_pattern));

if isempty(run_files)
    error('No matching merged files found in: %s', input_filepath);
end

fprintf('\nFound %d run file(s) to process for subject %s.\n', length(run_files), participantID);

for r = 1:length(run_files)
    target_merged_filename = run_files(r).name;
    
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

    EEG = pop_loadset('filename', target_merged_filename, 'filepath', input_filepath);

    % Dynamic trimming
    allevents = {EEG.event.type}';
    earliest_onset_latency = inf; 
    latest_offset_latency = -inf;

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

    % Execute Preprocessing
    [ALLEEG, EEG_preprocessed, CURRENTSET] = bemobil_process_all_EEG_preprocessing(...
        bids_base_string, bemobil_config, ALLEEG, EEG, CURRENTSET, force_recompute);
end

fprintf('\n============ PREPROCESSING COMPLETE ============\n');
end