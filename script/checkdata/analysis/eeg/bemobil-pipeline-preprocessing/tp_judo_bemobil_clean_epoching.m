%% Step 2: Epoch cleaned datasets around "Neutral<N>" events, with baseline correction
clear; clc;

if ~exist('ALLCOM','var')
    [ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab;
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
dlgtitle = 'Step 2 - Epoching Selection';
dims = [1 50];
definput = {'MH9HXJ', 'S001', 'heightaffordance', '001'};
userInput = inputdlg(prompt, dlgtitle, dims, definput);

if isempty(userInput), error('Processing cancelled.'); end

participantID = userInput{1};
sessionID     = userInput{2};
taskName      = userInput{3};
runID         = userInput{4};

bids_base_string = sprintf('%s_ses-%s_task-%s_run-%s', participantID, sessionID, taskName, runID);

%% 2. EPOCHING SETTINGS
epoch_window     = [-0.2 2.1];   % seconds: -200 ms to 2100 ms relative to event onset
baseline_window  = [-200 0];     % ms, pre-stimulus baseline for pop_rmbase

analysis_filepath = fullfile(bemobil_config.study_folder, bemobil_config.single_subject_analysis_folder, ...
    [bemobil_config.filename_prefix bids_base_string]);

epoched_filepath = fullfile(analysis_filepath, 'epoched');
if ~exist(epoched_filepath, 'dir'), mkdir(epoched_filepath); end

cleaned_versions = {'cleaned_eyeOnly.set', 'cleaned_eyeMuscle.set'};

%% 3. EPOCH EACH CLEANED VERSION
for v = 1:numel(cleaned_versions)

    infile = [bemobil_config.filename_prefix bids_base_string '_' cleaned_versions{v}];
    EEG = pop_loadset('filename', infile, 'filepath', analysis_filepath);

    % Match Neutral1, Neutral2, Neutral3, Neutral4, ... dynamically
    allevents = {EEG.event.type};
    neutral_mask = ~cellfun(@isempty, regexp(allevents, '^Neutral\d+$', 'once'));
    neutral_types = unique(allevents(neutral_mask));

    if isempty(neutral_types)
        warning('No "Neutral<N>" events found in %s — skipping.', infile);
        continue
    end
    fprintf('%s: found %d Neutral-type events (%s)\n', infile, sum(neutral_mask), strjoin(neutral_types, ', '));

    EEG = pop_epoch(EEG, neutral_types, epoch_window, 'epochinfo', 'yes');
    EEG = eeg_checkset(EEG, 'eventconsistency');

    n_trials = EEG.trials;
    if n_trials ~= numel(neutral_types)
        warning('Expected %d epochs, got %d — some Neutral events may be missing or fell outside the trimmed data.', ...
            numel(neutral_types), n_trials);
    end

    % Flag epochs that contain a boundary event (discontinuity from earlier
    % trimming/rejection steps) so they can be reviewed before analysis
    boundary_epochs = [];
    for e = 1:numel(EEG.epoch)
        if any(strcmp(EEG.epoch(e).eventtype, 'boundary'))
            boundary_epochs(end+1) = e; %#ok<AGROW>
        end
    end
    if ~isempty(boundary_epochs)
        warning('%s: epoch(s) %s contain a boundary event — inspect before use.', ...
            infile, mat2str(boundary_epochs));
    end

    EEG = pop_rmbase(EEG, baseline_window);

    outfile = strrep(cleaned_versions{v}, '.set', '_epoched.set');
    outfile = [bemobil_config.filename_prefix bids_base_string '_' outfile];
    pop_saveset(EEG, 'filename', outfile, 'filepath', epoched_filepath);
    fprintf('Saved %d epochs (baseline-corrected) to %s\\%s\n', n_trials, epoched_filepath, outfile);
end
