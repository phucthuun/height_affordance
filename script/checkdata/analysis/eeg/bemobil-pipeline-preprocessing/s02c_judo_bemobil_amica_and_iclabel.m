%% Step 1C: AMICA Training & ICLabel Artifact Rejection (Automated Batch over All Runs)
clear; clc; close all;

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
dlgtitle = 'Step 1C - AMICA & ICLabel Batch Selection';
dims = [1 50];
definput = {'MH9HXJ', 'S001', 'heightaffordance'};
userInput = inputdlg(prompt, dlgtitle, dims, definput);

if isempty(userInput), error('Processing cancelled.'); end

participantID = userInput{1};
sessionID     = userInput{2};
taskName      = userInput{3};

subEntity = sprintf('sub-%s', participantID);
sesEntity = sprintf('ses-%s', sessionID);

%% 2. AUTOMATICALLY DISCOVER ALL PREPROCESSED RUN FILES
% Search inside the single subject analysis directory for matching preprocessed files
analysis_folder = fullfile(bemobil_config.study_folder, bemobil_config.single_subject_analysis_folder);
search_pattern = sprintf('%s%s_%s_task-%s_run-*_%s', ...
    bemobil_config.filename_prefix, participantID, sesEntity, taskName, bemobil_config.preprocessed_filename);

run_files = dir(fullfile(analysis_folder, [bemobil_config.filename_prefix participantID '*'], search_pattern));

% Fallback search across the general analysis directory if folder hierarchy differs
if isempty(run_files)
    run_files = dir(fullfile(analysis_folder, '**', search_pattern));
end

if isempty(run_files)
    error('No matching preprocessed run files found for subject %s in: %s', participantID, analysis_folder);
end

fprintf('\nFound %d preprocessed run file(s) to process for AMICA & ICLabel.\n', length(run_files));

%% 3. BATCH PROCESS ALL DISCOVERED RUNS

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
    
    fprintf('\n==================================================\n');
    fprintf(' Processing AMICA & ICLabel Run %d/%d: %s\n', r, length(run_files), bids_base_string);
    fprintf('==================================================\n');

    rejected_segments_filepath = fullfile(bemobil_config.study_folder, bemobil_config.spatial_filters_folder, ...
        bemobil_config.spatial_filters_folder_AMICA, sprintf('sub-%s', bids_base_string));

    %% --- Load Preprocessed Data ---
    EEG_preprocessed = pop_loadset('filename', current_preprocessed_file, 'filepath', preprocessed_filepath);

    %% --- Check & Apply Manual Rejection Marks (If Available) ---
    rejected_segments_fullfile = fullfile(rejected_segments_filepath, ...
        [bemobil_config.filename_prefix bids_base_string '_' bemobil_config.rejected_segments_filename]);

    if exist(rejected_segments_fullfile, 'file')
        fprintf('Loading manual rejection marks from: %s\n', rejected_segments_fullfile);
        load(rejected_segments_fullfile, 'reject_segments_latency');
        if isempty(reject_segments_latency)
            EEG_preprocessed_and_rejected = EEG_preprocessed;
        else
            EEG_preprocessed_and_rejected = eeg_eegrej(EEG_preprocessed, reject_segments_latency);
        end
    else
        warning('No manual rejection file found for run %s! Running AMICA without manual segment rejection.', runID);
        EEG_preprocessed_and_rejected = EEG_preprocessed;
    end

    %% --- Run AMICA Spatial Decomposition ---
    amica_output_filepath = preprocessed_filepath;
    files_before = dir(fullfile(amica_output_filepath, '*.set'));

    [ALLEEG, EEG_preprocessed_and_rejected_ICA, CURRENTSET] = bemobil_process_all_AMICA(...
        ALLEEG, EEG_preprocessed_and_rejected, CURRENTSET, bids_base_string, bemobil_config, force_recompute);

    standard_ica_set = fullfile(amica_output_filepath, [bemobil_config.filename_prefix bids_base_string '_' bemobil_config.preprocessed_and_ICA_filename]);

    if ~exist(standard_ica_set, 'file')
        files_after = dir(fullfile(amica_output_filepath, '*.set'));
        new_files = setdiff({files_after.name}, {files_before.name});
        if numel(new_files) == 1
            standard_ica_set = fullfile(amica_output_filepath, new_files{1});
        else
            error('Could not locate file written by bemobil_process_all_AMICA in %s.', amica_output_filepath);
        end
    end

    rejected_ica_set = fullfile(amica_output_filepath, [bemobil_config.filename_prefix bids_base_string '_' bemobil_config.preprocessed_and_rejected_ICA_filename]);
    standard_ica_fdt = strrep(standard_ica_set, '.set', '.fdt');
    rejected_ica_fdt = strrep(rejected_ica_set, '.set', '.fdt');

    copyfile(standard_ica_set, rejected_ica_set);
    if exist(standard_ica_fdt, 'file')
        copyfile(standard_ica_fdt, rejected_ica_fdt);
    end

    %% --- ICLabel Artifact Rejection & Export ---
    EEG_ica = pop_loadset('filename', [bemobil_config.filename_prefix bids_base_string '_' bemobil_config.preprocessed_and_rejected_ICA_filename], ...
        'filepath', amica_output_filepath);

    EEG_ica = iclabel(EEG_ica, bemobil_config.iclabel_classifier);

    % Clean eye components only
    [ALLEEG, EEG_eyeOnly, CURRENTSET] = bemobil_clean_with_iclabel(EEG_ica, ALLEEG, CURRENTSET, ...
        bemobil_config.iclabel_classifier, [1 2 4 5 6 7], bemobil_config.iclabel_threshold, ...
        [bemobil_config.filename_prefix bids_base_string '_cleaned_eyeOnly.set'], amica_output_filepath);

    % Clean eye and muscle components
    [ALLEEG, EEG_eyeMuscle, CURRENTSET] = bemobil_clean_with_iclabel(EEG_ica, ALLEEG, CURRENTSET, ...
        bemobil_config.iclabel_classifier, [1 4 5 6 7], bemobil_config.iclabel_threshold, ...
        [bemobil_config.filename_prefix bids_base_string '_cleaned_eyeMuscle.set'], amica_output_filepath);

end

%% COMPLETE
fprintf('\n============ AMICA & ICLABEL BATCH COMPLETE ============\n');
fprintf('Processed all %d runs for participant %s successfully.\n', length(run_files), participantID);