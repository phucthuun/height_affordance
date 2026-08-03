%% Step 2B: Manual Segment Rejection (Interactive Visual Inspection)
%
% Outputs: (1) the rejection marks (.mat) and 
% (2) the resulting "preprocessed_and_rejected.set" 
% Outputs are saved together in 3_EEG-preprocessing, 
% next to the source "preprocessed.set". 

clear; clc; close all;

if ~exist('ALLCOM','var')
    [ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab;
end

run('s00_judo_bemobil_config.m');


%% 1. USER METADATA INPUT
prompt = { ...
    'Enter Participant ID (e.g., MH9HXJ):', ...
    'Enter Session ID (e.g., S001):', ...
    'Enter Task Name (e.g., heightaffordance):', ...
    'Enter Run ID (e.g., 001):' ...
};
dlgtitle = 'Step 2B - Manual Rejection Selection';
dims = [1 50];
definput = {'155T4T', 'S001', 'heightaffordance', '001'};
userInput = inputdlg(prompt, dlgtitle, dims, definput);

if isempty(userInput), error('Processing cancelled.'); end

participantID = userInput{1};
sessionID     = userInput{2};
taskName      = userInput{3};
runID         = userInput{4};

bids_base_string = sprintf('%s_ses-%s_task-%s_run-%s', participantID, sessionID, taskName, runID);

% Preprocessed input location -- also where all outputs of this step are saved
preprocessed_filepath = fullfile(bemobil_config.study_folder, bemobil_config.EEG_preprocessing_data_folder, ...
    [bemobil_config.filename_prefix bids_base_string]);

if ~exist(preprocessed_filepath, 'dir'), mkdir(preprocessed_filepath); end

%% 2. LOAD PREPROCESSED DATA
preprocessed_filename = [bemobil_config.filename_prefix bids_base_string '_' bemobil_config.preprocessed_filename];
EEG_preprocessed = pop_loadset('filename', preprocessed_filename, 'filepath', preprocessed_filepath);

%% 3. INTERACTIVE VISUAL INSPECTION
fprintf('\n--- Manual data inspection: mark bad segments for rejection ---\n');
fprintf('In the eegplot window: drag to highlight bad chunks, then press "REJECT" and close window.\n');

EEG = EEG_preprocessed;
figs_before = findall(groot, 'Type', 'figure');
pop_eegplot(EEG, 1, 1, 1, [], 'winlength', 20);
figs_after = findall(groot, 'Type', 'figure');
new_figs = setdiff(figs_after, figs_before);

if ~isempty(new_figs)
    uiwait(new_figs(1));
else
    warning('Could not detect eegplot window automatically. Close manually and press any key.');
    pause;
end

EEG_preprocessed_and_rejected = eeg_checkset(EEG);

%% 4. EXTRACT & SAVE REJECTION MARKS (.mat)
boundary_idx = find(strcmp({EEG_preprocessed_and_rejected.event.type}, 'boundary'));
reject_segments_latency = [];
cum_removed = 0;

for b = boundary_idx
    dur = EEG_preprocessed_and_rejected.event(b).duration;
    if isempty(dur) || dur <= 0, continue; end
    start_orig = round(EEG_preprocessed_and_rejected.event(b).latency) + cum_removed;
    end_orig   = start_orig + dur;
    reject_segments_latency = [reject_segments_latency; start_orig end_orig]; %#ok<AGROW>
    cum_removed = cum_removed + dur;
end

rejected_segments_fullfile = fullfile(preprocessed_filepath, ...
    [bemobil_config.filename_prefix bids_base_string '_' bemobil_config.rejected_segments_filename]);

save(rejected_segments_fullfile, 'reject_segments_latency');
fprintf('\nSaved manual rejection marks to: %s\n', rejected_segments_fullfile);

%% 5. SAVE PREPROCESSED AND REJECTED DATASET (.set) -- into 3_EEG-preprocessing
rejected_set_filename = [bemobil_config.filename_prefix bids_base_string '_' bemobil_config.preprocessed_and_rejected_filename];

pop_saveset(EEG_preprocessed_and_rejected, ...
    'filename', rejected_set_filename, ...
    'filepath', preprocessed_filepath);

fprintf('Saved preprocessed & rejected dataset to: %s\n', fullfile(preprocessed_filepath, rejected_set_filename));