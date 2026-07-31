%% Step 1: Filter Optimization and AMICA Training
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
output_filepath  = fullfile(bemobil_config.study_folder, bemobil_config.spatial_filters_folder, bemobil_config.spatial_filters_folder_AMICA, sprintf('sub-%s', bids_base_string));

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

%% 3.5 MANUAL SEGMENT REJECTION (visual inspection of bad data chunks before AMICA)
% The idea: visually mark obviously bad chunks of data (movement artifacts, disconnects, etc.) on the
% preprocessed-but-not-yet-decomposed dataset and remove them before AMICA is trained. The removed segments (in
% samples of EEG_preprocessed) are stored in a .mat file next to the AMICA output. On future runs for the same
% subject/session, that file is loaded and re-applied automatically, so the manual step only has to be done once.

rejected_segments_filepath = output_filepath; % lives next to the AMICA output for this subject/session
rejected_segments_fullfile = fullfile(rejected_segments_filepath, ...
    [bemobil_config.filename_prefix bids_base_string '_' bemobil_config.rejected_segments_filename]);

if exist(rejected_segments_fullfile, 'file') && ~bemobil_config.force_manual_segment_rejection

    fprintf('\n--- Found existing manual rejection marks, applying automatically ---\n');
    fprintf('Loading: %s\n', rejected_segments_fullfile);
    load(rejected_segments_fullfile, 'reject_segments_latency'); % Nx2 [start end] in samples of EEG_preprocessed

    if isempty(reject_segments_latency)
        EEG_preprocessed_and_rejected = EEG_preprocessed;
    else
        EEG_preprocessed_and_rejected = eeg_eegrej(EEG_preprocessed, reject_segments_latency);
    end

else

    fprintf('\n--- Manual data inspection: mark bad segments for rejection ---\n');
    fprintf('In the eegplot window: drag to highlight bad chunks, then press "REJECT" and close the window to continue.\n');

    % pop_eegplot with reject-mode enabled (4th arg = 1) removes the marked stretches and writes the result back
    % into a variable called EEG in this (script/base) workspace once you press "REJECT".
    % Note: pop_eegplot's return value is a command string, not a graphics handle, so we can't uiwait() on it
    % directly. Instead, grab whichever new figure appears after the call and wait on that.
    EEG = EEG_preprocessed;
    figs_before = findall(groot, 'Type', 'figure');
    pop_eegplot(EEG, 1, 1, 1, [], 'winlength', 20);
    figs_after = findall(groot, 'Type', 'figure');
    new_figs = setdiff(figs_after, figs_before);
    if ~isempty(new_figs)
        uiwait(new_figs(1));
    else
        warning('Could not detect the eegplot window automatically. Close it manually, then press any key here to continue.');
        pause;
    end

    EEG_preprocessed_and_rejected = eeg_checkset(EEG);

    % eeg_eegrej automatically inserts a 'boundary' event (with a 'duration' field, in samples of the SHORTENED
    % dataset) at every point where data was removed. Walk through those to reconstruct the rejected windows in
    % the latencies of the ORIGINAL (pre-rejection) dataset, so they can be re-applied to a fresh EEG_preprocessed
    % later without needing eegplot again.
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

    if ~exist(rejected_segments_filepath, 'dir'), mkdir(rejected_segments_filepath); end
    save(rejected_segments_fullfile, 'reject_segments_latency');
    fprintf('Saved manual rejection marks to: %s\n', rejected_segments_fullfile);

end

%% 4. RUN SPATIAL DECOMPOSITION (AMICA) on the manually rejected data — once only
amica_output_filepath = fullfile(bemobil_config.study_folder, bemobil_config.single_subject_analysis_folder, ...
    [bemobil_config.filename_prefix bids_base_string]);

files_before = dir(fullfile(amica_output_filepath, '*.set'));

[ALLEEG, EEG_preprocessed_and_rejected_ICA, CURRENTSET] = bemobil_process_all_AMICA(...
    ALLEEG, EEG_preprocessed_and_rejected, CURRENTSET, bids_base_string, bemobil_config, force_recompute);

% bemobil_process_all_AMICA saves its output to disk using its OWN internal filename convention
% (bemobil_config.preprocessed_and_ICA_filename) -- it has no idea we fed it the rejected data, so it does not
% know about our "_rejected_ICA" name. Locate whatever it actually wrote and duplicate it under our name, so
% step 5 below (and any future manual reload) can find it unambiguously and it doesn't get confused with a
% non-rejection-based ICA run.
standard_ica_set = fullfile(amica_output_filepath, [bemobil_config.filename_prefix bids_base_string '_' bemobil_config.preprocessed_and_ICA_filename]);

if ~exist(standard_ica_set, 'file')
    % fall back to a directory diff in case the internal naming differs from what we assumed
    files_after = dir(fullfile(amica_output_filepath, '*.set'));
    new_files = setdiff({files_after.name}, {files_before.name});
    if numel(new_files) == 1
        standard_ica_set = fullfile(amica_output_filepath, new_files{1});
    else
        error(['Could not locate the .set file written by bemobil_process_all_AMICA in %s. ' ...
            'Check the function''s actual save name and adjust standard_ica_set accordingly.'], amica_output_filepath);
    end
end

rejected_ica_set = fullfile(amica_output_filepath, [bemobil_config.filename_prefix bids_base_string '_' bemobil_config.preprocessed_and_rejected_ICA_filename]);
standard_ica_fdt = strrep(standard_ica_set, '.set', '.fdt');
rejected_ica_fdt = strrep(rejected_ica_set, '.set', '.fdt');

copyfile(standard_ica_set, rejected_ica_set);
if exist(standard_ica_fdt, 'file')
    copyfile(standard_ica_fdt, rejected_ica_fdt);
end

%% 5. Reload the UNCLEANED full-length ICA dataset and derive two cleaned versions
EEG_ica = pop_loadset('filename', [bemobil_config.filename_prefix bids_base_string '_' bemobil_config.preprocessed_and_rejected_ICA_filename], ...
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