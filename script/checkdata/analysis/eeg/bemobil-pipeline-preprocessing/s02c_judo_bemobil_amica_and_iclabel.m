%% Step 2C: AMICA Training & ICLabel Artifact Rejection (Automated Batch over All Runs)
%
% Supports running AMICA + ICLabel on EITHER the plain "preprocessed" dataset,
% the "preprocessed_and_rejected" dataset (manual segments removed in s02b), or BOTH.
% Each mode writes to a fully separate output folder/filename set, so running both
% never overwrites the other, and filenames always reflect what was actually used.

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
dlgtitle = 'Step 2C - AMICA & ICLabel Batch Selection';
dims = [1 50];
definput = {'MH9HXJ', 'S001', 'heightaffordance'};
userInput = inputdlg(prompt, dlgtitle, dims, definput);

if isempty(userInput), error('Processing cancelled.'); end

participantID = userInput{1};
sessionID     = userInput{2};
taskName      = userInput{3};

subEntity = sprintf('sub-%s', participantID);
sesEntity = sprintf('ses-%s', sessionID);

%% 1b. SELECT WHICH INPUT VERSION(S) TO RUN AMICA + ICLABEL ON
mode_options = {'preprocessed  (no manual rejection)', ...
                 'preprocessed_and_rejected  (manual segments removed in s02b)'};
[mode_selection, ok] = listdlg('ListString', mode_options, 'SelectionMode', 'multiple', ...
    'InitialValue', [1 2], 'Name', 'Input selection', 'ListSize', [420 80], ...
    'PromptString', 'Run AMICA + ICLabel on which dataset(s)?');

if ~ok || isempty(mode_selection), error('Processing cancelled.'); end

run_modes = {};
if any(mode_selection == 1), run_modes{end+1} = 'preprocessed'; end %#ok<AGROW>
if any(mode_selection == 2), run_modes{end+1} = 'rejected';     end %#ok<AGROW>

%% 2. AUTOMATICALLY DISCOVER ALL PREPROCESSED RUN FILES
analysis_folder = fullfile(bemobil_config.study_folder, bemobil_config.EEG_preprocessing_data_folder);
search_pattern = sprintf('%s%s_%s_task-%s_run-*_%s', ...
    bemobil_config.filename_prefix, participantID, sesEntity, taskName, bemobil_config.preprocessed_filename);

run_files = dir(fullfile(analysis_folder, [bemobil_config.filename_prefix participantID '*'], search_pattern));

% Fallback recursive search in case folder hierarchy differs (needs MATLAB R2016b+ for '**')
if isempty(run_files)
    run_files = dir(fullfile(analysis_folder, '**', search_pattern));
end

if isempty(run_files)
    error('No matching preprocessed run files found for subject %s in: %s', participantID, analysis_folder);
end

fprintf('\nFound %d preprocessed run file(s). Will process mode(s): %s\n', ...
    length(run_files), strjoin(run_modes, ', '));

%% 3. BATCH PROCESS ALL DISCOVERED RUNS x SELECTED MODES

for r = 1:length(run_files)

    current_preprocessed_file = run_files(r).name;
    preprocessed_filepath    = run_files(r).folder;

    % Extract Run ID automatically using regex from filename
    runTokens = regexp(current_preprocessed_file, 'run-([a-zA-Z0-9]+)', 'tokens');
    if ~isempty(runTokens)
        runID = runTokens{1}{1};
    else
        runID = sprintf('%03d', r);
    end

    bids_base_string = sprintf('%s_ses-%s_task-%s_run-%s', participantID, sessionID, taskName, runID);

    for m = 1:length(run_modes)
        this_mode = run_modes{m};

        fprintf('\n==================================================\n');
        fprintf(' Run %d/%d: %s  |  Mode: %s\n', r, length(run_files), bids_base_string, this_mode);
        fprintf('==================================================\n');

        %% --- Build the input EEG dataset for this mode ---
        switch this_mode

            case 'preprocessed'
                EEG_input = pop_loadset('filename', current_preprocessed_file, 'filepath', preprocessed_filepath);
                mode_tag = 'raw';
                cleaned_eyeOnly_suffix   = '_cleaned_eyeOnly.set';
                cleaned_eyeMuscle_suffix = '_cleaned_eyeMuscle.set';

            case 'rejected'
                rejected_set_filename = [bemobil_config.filename_prefix bids_base_string '_' bemobil_config.preprocessed_and_rejected_filename];
                rejected_set_fullfile = fullfile(preprocessed_filepath, rejected_set_filename);

                if exist(rejected_set_fullfile, 'file')
                    % Preferred path: load the dataset s02b already computed and saved.
                    fprintf('Loading manually-rejected dataset saved by s02b: %s\n', rejected_set_fullfile);
                    EEG_input = pop_loadset('filename', rejected_set_filename, 'filepath', preprocessed_filepath);
                else
                    % Fallback: reconstruct by re-applying saved sample marks to a freshly
                    % loaded preprocessed.set. Only reliable if s02a has NOT been re-run/
                    % changed since s02b made the marks (sample indices must still match).
                    rejected_segments_fullfile = fullfile(preprocessed_filepath, ...
                        [bemobil_config.filename_prefix bids_base_string '_' bemobil_config.rejected_segments_filename]);

                    if ~exist(rejected_segments_fullfile, 'file')
                        warning(['No "preprocessed_and_rejected" dataset and no rejection-mark file found for %s. ' ...
                            'Run s02b first. Skipping "rejected" mode for this run.'], bids_base_string);
                        continue
                    end

                    warning(['%s: no saved preprocessed_and_rejected.set found -- reconstructing from stored ' ...
                        'sample marks instead. This assumes preprocessing has not changed since s02b was run.'], bids_base_string);
                    EEG_input = pop_loadset('filename', current_preprocessed_file, 'filepath', preprocessed_filepath);
                    load(rejected_segments_fullfile, 'reject_segments_latency');
                    if ~isempty(reject_segments_latency)
                        EEG_input = eeg_eegrej(EEG_input, reject_segments_latency);
                    end
                end
                mode_tag = 'rej';
                cleaned_eyeOnly_suffix   = '_rejected_cleaned_eyeOnly.set';
                cleaned_eyeMuscle_suffix = '_rejected_cleaned_eyeMuscle.set';
        end

        %% --- Run AMICA Spatial Decomposition ---
        % Give each mode its own bids string so bemobil_process_all_AMICA writes to a
        % fully separate folder (sub-..._raw vs sub-..._rej) -- no filename collisions,
        % no copy/rename workaround needed.
        bids_base_string_mode = sprintf('%s_%s', bids_base_string, mode_tag);

        amica_output_filepath = fullfile(bemobil_config.study_folder, bemobil_config.single_subject_analysis_folder, ...
            [bemobil_config.filename_prefix bids_base_string_mode]);

        [ALLEEG, ~, CURRENTSET] = bemobil_process_all_AMICA(...
            ALLEEG, EEG_input, CURRENTSET, bids_base_string_mode, bemobil_config, force_recompute);

        % Reload from disk (matches the pattern used elsewhere in this pipeline) rather
        % than trusting the in-memory struct returned above.
        ica_set_filename = [bemobil_config.filename_prefix bids_base_string_mode '_' bemobil_config.preprocessed_and_ICA_filename];
        if ~exist(fullfile(amica_output_filepath, ica_set_filename), 'file')
            error(['Expected AMICA output not found: %s\nCheck that bemobil_process_all_AMICA saves to ' ...
                '<single_subject_analysis_folder>/sub-<bids_base_string_mode>/ using preprocessed_and_ICA_filename, ' ...
                'and adjust this path if your installed function differs.'], fullfile(amica_output_filepath, ica_set_filename));
        end
        EEG_ica = pop_loadset('filename', ica_set_filename, 'filepath', amica_output_filepath);

        %% --- ICLabel Artifact Rejection & Export ---
        EEG_ica = iclabel(EEG_ica, bemobil_config.iclabel_classifier);

        % Clean eye components only
        [ALLEEG, EEG_eyeOnly, CURRENTSET] = bemobil_clean_with_iclabel(EEG_ica, ALLEEG, CURRENTSET, ...
            bemobil_config.iclabel_classifier, [1 2 4 5 6 7], bemobil_config.iclabel_threshold, ...
            [bemobil_config.filename_prefix bids_base_string cleaned_eyeOnly_suffix], amica_output_filepath);

        % Clean eye and muscle components
        [ALLEEG, EEG_eyeMuscle, CURRENTSET] = bemobil_clean_with_iclabel(EEG_ica, ALLEEG, CURRENTSET, ...
            bemobil_config.iclabel_classifier, [1 4 5 6 7], bemobil_config.iclabel_threshold, ...
            [bemobil_config.filename_prefix bids_base_string cleaned_eyeMuscle_suffix], amica_output_filepath);

    end
end

%% COMPLETE
fprintf('\n============ AMICA & ICLABEL BATCH COMPLETE ============\n');
fprintf('Processed all %d run(s) x mode(s) [%s] for participant %s successfully.\n', ...
    length(run_files), strjoin(run_modes, ', '), participantID);