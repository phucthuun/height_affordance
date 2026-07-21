%% Step 1: Filter Optimization and AMICA Training
clear; clc; close all;

if ~exist('ALLCOM','var')
    [ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab;
end

% Load base configuration
run('tp_judo_bemobil_config.m');
force_recompute = 1;
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

bids_base_string = sprintf('%s_ses-%s_task-%s_run-%s', participantID, sessionID, taskName, runID);
input_filepath   = fullfile(bemobil_config.study_folder, bemobil_config.raw_EEGLAB_data_folder, sprintf('sub-%s', participantID), sprintf('ses-%s', sessionID));
output_filepath  = fullfile(bemobil_config.study_folder, bemobil_config.spatial_filters_folder_AMICA, sprintf('sub-%s', participantID), sprintf('ses-%s', sessionID));

if ~exist(output_filepath, 'dir'), mkdir(output_filepath); end

%% 2. LOAD & TRIM RAW MERGED DATA
target_merged_filename = sprintf('sub-%s_%s', bids_base_string, bemobil_config.merged_filename);
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

%% 3. BASIC PROCESSING
% opengl('save','software') %run if error in plotting
[ALLEEG, EEG_preprocessed, CURRENTSET] = bemobil_process_all_EEG_preprocessing(bids_base_string, bemobil_config, ALLEEG, EEG, CURRENTSET, force_recompute);

%%%% segment area %%%%
% manual segmentation --> give to AMICA
% look up eeglab: get output: which time period is removed(for replication)
% take an example 
% removeindices = [0, max(1, earliest_onset_latency - EEG.srate); 
% min(EEG.pnts, latest_offset_latency + EEG.srate), EEG.pnts]; 
% EEG = eeg_eegrej(EEG, removeindices); ---> has manually removed time
% segment
% load(EEG_preprocessed_and_rejected)
%%%%%%%%%%%%%%%%%%%%%%%

%% 4. RUN SPATIAL DECOMPOSITION (AMICA) — once only
bemobil_config.iclabel_classes = [1 2 4 5 6 7]; % placeholder, gets overridden below anyway
[ALLEEG, EEG_preprocessed_and_ICA, CURRENTSET] = bemobil_process_all_AMICA(...
    ALLEEG, EEG_preprocessed, CURRENTSET, bids_base_string, bemobil_config, force_recompute);

% [ALLEEG, EEG_preprocessed_and_rejected_ICA, CURRENTSET] = bemobil_process_all_AMICA(...
%     ALLEEG, EEG_preprocessed_and_rejected, CURRENTSET, bids_base_string, bemobil_config, force_recompute);
% [ALLEEG, EEG_preprocessed_and_ICA, CURRENTSET] = bemobil_copy_spatial_filter(EEG_preprocessed, ALLEEG, CURRENTSET, EEG_preprocessed_and_rejected_ICA, ....)
% |
% |---- preprocessed_and_ICA
%% 5. Reload the UNCLEANED full-length ICA dataset and derive two cleaned versions
amica_output_filepath = fullfile(bemobil_config.study_folder, bemobil_config.single_subject_analysis_folder, ...
    [bemobil_config.filename_prefix bids_base_string]);

EEG_ica = pop_loadset('filename', [bemobil_config.filename_prefix bids_base_string '_' bemobil_config.preprocessed_and_ICA_filename], ...
    'filepath', amica_output_filepath);

% ICLabel only needs to be computed once
EEG_ica = iclabel(EEG_ica, bemobil_config.iclabel_classifier);

% --- Version 1: eye components removed only ---
[ALLEEG, EEG_eyeOnly, CURRENTSET] = bemobil_clean_with_iclabel(EEG_ica, ALLEEG, CURRENTSET, ...
    bemobil_config.iclabel_classifier, [1 2 4 5 6 7], bemobil_config.iclabel_threshold, ...
    [bemobil_config.filename_prefix bids_base_string '_cleaned_eyeOnly.set'], amica_output_filepath);

% --- Version 2: eye AND muscle components removed ---
[ALLEEG, EEG_eyeMuscle, CURRENTSET] = bemobil_clean_with_iclabel(EEG_ica, ALLEEG, CURRENTSET, ...
    bemobil_config.iclabel_classifier, [1 4 5 6 7], bemobil_config.iclabel_threshold, ...
    [bemobil_config.filename_prefix bids_base_string '_cleaned_eyeMuscle.set'], amica_output_filepath);
