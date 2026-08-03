%% Step 2C: AMICA Training & ICLabel Artifact Rejection (HPC Tardis Version)
% Usage:
% matlab -batch "s02c_judo_bemobil_amica_and_iclabel('MH9HXJ','S001','heightaffordance')"
%
% Runs AMICA + ICLabel on BOTH preprocessed and preprocessed_and_rejected inputs, 
% Separate output folders:
%   'preprocessed' - trains AMICA on the plain preprocessed.set and cleans that same data.
%   'rejected'     - trains AMICA on the preprocessed_and_rejected.set produced by s02b
%                    The resulting weights are then transferred onto the FULL (un-rejected)
%                    preprocessed data before ICLabel cleaning, so the final cleaned dataset
%                    is the entire continuous recording, not just the rejected segments.
%                    If no rejected data/marks exist yet for a given run, that run's
%                    "rejected" mode is skipped with a warning while "preprocessed" still runs.
function s02c_judo_bemobil_amica_and_iclabel(participantID, sessionID, taskName)
run_modes = {'preprocessed', 'rejected'};

if isunix
    opengl('save', 'software');
    set(0, 'DefaultFigureVisible', 'off');
end

if ~exist('ALLCOM', 'var')
    [ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab;
end

run('s00_judo_bemobil_config.m');
force_recompute = 1;

fprintf('============ BEMOBIL AMICA & ICLABEL (HPC) ============\n');
fprintf('Participant: %s | Session: %s | Task: %s | Mode(s): %s\n', participantID, sessionID, taskName, strjoin(run_modes, ', '));

subEntity = sprintf('sub-%s', participantID);
sesEntity = sprintf('ses-%s', sessionID);

%% 1. AUTOMATICALLY DISCOVER ALL PREPROCESSED RUN FILES
analysis_folder = fullfile(bemobil_config.study_folder, bemobil_config.EEG_preprocessing_data_folder);
search_pattern = sprintf('%s%s_%s_task-%s_run-*_%s', ...
    bemobil_config.filename_prefix, participantID, sesEntity, taskName, bemobil_config.preprocessed_filename);

run_files = dir(fullfile(analysis_folder, [bemobil_config.filename_prefix participantID '*'], search_pattern));

% Fallback recursive search in case folder hierarchy differs
if isempty(run_files)
    run_files = dir(fullfile(analysis_folder, '**', search_pattern));
end

if isempty(run_files)
    existing = dir(fullfile(analysis_folder, [bemobil_config.filename_prefix participantID '*']));
    existing = existing([existing.isdir]);
    if isempty(existing)
        error(['No matching preprocessed run files found for subject %s in: %s\n' ...
            'No folders starting with "%s%s" exist there either -- check the Participant ID.'], ...
            participantID, analysis_folder, bemobil_config.filename_prefix, participantID);
    else
        existing_names = strjoin({existing.name}, sprintf('\n  '));
        error(['No matching preprocessed run files found for subject %s in: %s\n' ...
            'Searched for session/task: "%s" / "%s"\n' ...
            'Folders that DO exist for this participant:\n  %s\n' ...
            '-> Check that Session ID and Task Name match one of the folders above.'], ...
            participantID, analysis_folder, sesEntity, taskName, existing_names);
    end
end

fprintf('\nFound %d preprocessed run file(s). Will process mode(s): %s\n', ...
    length(run_files), strjoin(run_modes, ', '));

%% 2. BATCH PROCESS ALL DISCOVERED RUNS x SELECTED MODES

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
                mode_tag = 'preprocessed';
                cleaned_eyeOnly_suffix   = '_cleaned_eyeOnly.set';
                cleaned_eyeMuscle_suffix = '_cleaned_eyeMuscle.set';

            case 'rejected'
                rejected_set_filename = [bemobil_config.filename_prefix bids_base_string '_' bemobil_config.preprocessed_and_rejected_filename];
                rejected_set_fullfile = fullfile(preprocessed_filepath, rejected_set_filename);

                if exist(rejected_set_fullfile, 'file')
                    fprintf('Loading manually-rejected dataset saved by s02b: %s\n', rejected_set_fullfile);
                    EEG_input = pop_loadset('filename', rejected_set_filename, 'filepath', preprocessed_filepath);
                else
                    rejected_segments_fullfile = fullfile(preprocessed_filepath, ...
                        [bemobil_config.filename_prefix bids_base_string '_' bemobil_config.rejected_segments_filename]);

                    if ~exist(rejected_segments_fullfile, 'file')
                        warning(['No "preprocessed_and_rejected" dataset and no rejection-mark file found for %s. ' ...
                            'Run s02b (locally) first and copy its output onto the cluster. Skipping "rejected" mode for this run.'], bids_base_string);
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
                mode_tag = 'preprocessed_and_rejected';
                cleaned_eyeOnly_suffix   = '_rejected_cleaned_eyeOnly.set';
                cleaned_eyeMuscle_suffix = '_rejected_cleaned_eyeMuscle.set';
        end

        %% --- Run AMICA Spatial Decomposition ---
        bids_base_string_mode = sprintf('%s_%s', bids_base_string, mode_tag);

        amica_output_filepath = fullfile(bemobil_config.study_folder, bemobil_config.single_subject_analysis_folder, ...
            [bemobil_config.filename_prefix bids_base_string_mode]);

        [ALLEEG, ~, CURRENTSET] = safely_run_bemobil_process_all_AMICA(...
            ALLEEG, EEG_input, CURRENTSET, bids_base_string_mode, bemobil_config, force_recompute, amica_output_filepath);

        % Reload AMICA dataset from disk
        ica_set_filename = [bemobil_config.filename_prefix bids_base_string_mode '_' bemobil_config.preprocessed_and_ICA_filename];
        if ~exist(fullfile(amica_output_filepath, ica_set_filename), 'file')
            error('Expected AMICA output not found: %s', fullfile(amica_output_filepath, ica_set_filename));
        end
        EEG_ica = pop_loadset('filename', ica_set_filename, 'filepath', amica_output_filepath);

        %% --- Weight Transfer (rejected mode only) ---
        if strcmp(this_mode, 'rejected')
            fprintf('Transferring AMICA weights using bemobil_copy_spatial_filter...\n');

            EEG_ica_trained = EEG_ica;
            EEG_full = pop_loadset('filename', current_preprocessed_file, 'filepath', preprocessed_filepath);

            % Use official BeMoBIL utility to transfer spatial filters and metadata
            weights_on_full_filename = [bemobil_config.filename_prefix bids_base_string_mode '_weightsOnFullPreprocessed.set'];
            [ALLEEG, EEG_full, CURRENTSET] = bemobil_copy_spatial_filter(...
                EEG_full, ALLEEG, CURRENTSET, EEG_ica_trained, weights_on_full_filename, amica_output_filepath);

            EEG_ica = EEG_full;
        end

        %% --- ICLabel Artifact Rejection & Export ---
        EEG_ica = iclabel(EEG_ica, bemobil_config.iclabel_classifier);

        % Clean eye components only
        [ALLEEG, ~, CURRENTSET] = bemobil_clean_with_iclabel(EEG_ica, ALLEEG, CURRENTSET, ...
            bemobil_config.iclabel_classifier, [1 2 4 5 6 7], bemobil_config.iclabel_threshold, ...
            [bemobil_config.filename_prefix bids_base_string cleaned_eyeOnly_suffix], amica_output_filepath);

        % Clean eye and muscle components
        [ALLEEG, ~, CURRENTSET] = bemobil_clean_with_iclabel(EEG_ica, ALLEEG, CURRENTSET, ...
            bemobil_config.iclabel_classifier, [1 4 5 6 7], bemobil_config.iclabel_threshold, ...
            [bemobil_config.filename_prefix bids_base_string cleaned_eyeMuscle_suffix], amica_output_filepath);

    end
end

fprintf('\n============ AMICA & ICLABEL BATCH COMPLETE ============\n');
end


function [ALLEEG, EEG_out, CURRENTSET] = safely_run_bemobil_process_all_AMICA(...
    ALLEEG, EEG_input, CURRENTSET, bids_base_string_mode, bemobil_config, force_recompute, amica_output_filepath)

    expected_set = fullfile(amica_output_filepath, ...
        [bemobil_config.filename_prefix bids_base_string_mode '_' bemobil_config.preprocessed_and_ICA_filename]);

    try
        [ALLEEG, EEG_out, CURRENTSET] = bemobil_process_all_AMICA(...
            ALLEEG, EEG_input, CURRENTSET, bids_base_string_mode, bemobil_config, force_recompute);
    catch ME
        is_known_plot_crash = contains(ME.message, 'UI components are not supported') || ...
            (~isempty(ME.stack) && any(strcmp({ME.stack.name}, 'print')));

        if is_known_plot_crash && exist(expected_set, 'file')
            warning(['bemobil_process_all_AMICA crashed while exporting a diagnostic PNG, ' ...
                'but the AMICA-decomposed dataset was already saved before the crash. Continuing with: %s'], expected_set);
            EEG_out = [];
        else
            rethrow(ME);
        end
    end
end