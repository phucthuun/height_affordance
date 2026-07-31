%% BeMoBIL XDF Import Script with Interactive Participant Selection (Multi-Run Auto-Detection)
% Imports all matching XDF files for a given (Participant, Session, Task) 
% and converts them into BIDS-compliant EEGLAB format.
%
% Input:  XDF file from sourcedata
% Output: BIDS-formatted data in derivatives/EEG_bemobil_pipeline/1_BIDS-data
%         and raw EEGLAB format in 2_raw-EEGLAB

clear; clc; close all;

%% 0. LOAD CONFIGURATION
run('s00_judo_bemobil_config.m');
fprintf('============ BEMOBIL XDF IMPORT TO BIDS ============\n');

%% 1. INTERACTIVE SELECTION (Participant, Session, Task Only)

prompt = {
    'Enter Participant ID (e.g., MH9HXJ):', ...
    'Enter Session ID (e.g., S001):', ...
    'Enter Task Name (e.g., heightaffordance):'
};
dlgtitle = 'XDF Import - Select Target Data';
dims = [1 60];
definput = {'MH9HXJ', 'S001', 'heightaffordance'};
userInput = inputdlg(prompt, dlgtitle, dims, definput);

if isempty(userInput)
    error('Import cancelled by user.');
end

% Store original IDs
participantID = userInput{1};
sessionID     = userInput{2};
taskName      = userInput{3};

% Build initial BIDS-compliant entity strings
subEntity  = sprintf('sub-%s', participantID);
sesEntity  = sprintf('ses-%s', sessionID);
taskEntity = sprintf('task-%s', taskName);

fprintf('\n--- Input Configuration ---\n');
fprintf('Participant: %s\n', participantID);
fprintf('Session:     %s\n', sessionID);
fprintf('Task:        %s\n', taskName);

%% 2. AUTOMATICALLY DETECT ALL RUNS

xdf_folder = fullfile(bemobil_config.raw_data_folder, subEntity, sesEntity, 'lslglobal');

if ~exist(xdf_folder, 'dir')
    error('LSL directory does not exist: %s', xdf_folder);
end

% Search for candidate files matching sub, ses, and task
search_pattern = fullfile(xdf_folder, sprintf('%s_%s_*%s*.xdf', subEntity, sesEntity, taskName));
xdf_files = dir(search_pattern);

% Fallback search if strict naming pattern returns nothing
if isempty(xdf_files)
    warning('No files matched strict pattern. Searching for any XDF files in target directory...');
    xdf_files = dir(fullfile(xdf_folder, '*.xdf'));
end

if isempty(xdf_files)
    error('No XDF files found in folder: %s', xdf_folder);
end

fprintf('\nFound %d matching XDF file(s) to process.\n', length(xdf_files));

%% 3. INITIALIZE EEGLAB
fprintf('\n--- Initializing EEGLAB ---\n');
[ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab;

%% 4. PROCESS ALL DISCOVERED RUNS

for r = 1:length(xdf_files)
    
    current_xdf_name = xdf_files(r).name;
    xdf_fullpath = fullfile(xdf_folder, current_xdf_name);
    
    fprintf('\n==================================================\n');
    fprintf(' Processing Run %d/%d: %s\n', r, length(xdf_files), current_xdf_name);
    fprintf('==================================================\n');

    % Extract Run ID automatically from filename (e.g., 'run-001' or '_001_')
    runTokens = regexp(current_xdf_name, 'run-([a-zA-Z0-9]+)', 'tokens');
    if ~isempty(runTokens)
        runID = runTokens{1}{1};
    else
        % Alternative regex to capture numeric sequence prior to suffix
        runTokensAlt = regexp(current_xdf_name, '_(\d{2,3})_', 'tokens');
        if ~isempty(runTokensAlt)
            runID = runTokensAlt{1}{1};
        else
            % Fallback index if no run string/number can be safely parsed
            runID = sprintf('%03d', r); 
        end
    end

    runEntity = sprintf('run-%s', runID);
    fprintf('Extracted Run Entity: %s\n', runEntity);

    % Setup Output Directories
    bids_out_folder = fullfile(bemobil_config.study_folder, bemobil_config.bids_target_folder, subEntity, sesEntity);
    raw_eeglab_folder = fullfile(bemobil_config.study_folder, bemobil_config.raw_EEGLAB_data_folder, subEntity, sesEntity);

    if ~exist(bids_out_folder, 'dir'), mkdir(bids_out_folder); end
    if ~exist(raw_eeglab_folder, 'dir'), mkdir(raw_eeglab_folder); end

    %% --- Load XDF Multi-Stream Data ---
    EEG = pop_loadxdf(xdf_fullpath, 'streamname', 'EEG');

    if isempty(EEG.data)
        warning('EEG stream not found automatically. Inspecting streams...');
        streams = load_xdf(xdf_fullpath);
        for s = 1:length(streams)
            fprintf('  %d: %s (Type: %s, Channels: %d)\n', ...
                s, streams{s}.info.name, streams{s}.info.type, ...
                str2double(streams{s}.info.channel_count));
        end
        
        stream_choice = inputdlg(sprintf('Select stream for %s:', current_xdf_name), ...
            'Select EEG Stream', [1 50], {'EEG'});
        if ~isempty(stream_choice)
            EEG = pop_loadxdf(xdf_fullpath, 'streamname', stream_choice{1}, 'handleJitter', 'on');
        else
            warning('Skipping file %s (No stream selected).', current_xdf_name);
            continue;
        end
    end

    % Set dataset metadata
    EEG.setname = sprintf('%s_%s_%s_%s_raw', subEntity, sesEntity, taskEntity, runEntity);
    EEG.filename = '';
    EEG.filepath = '';
    EEG.subject = participantID;
    EEG.session = str2double(regexprep(sessionID, '\D', ''));
    EEG.condition = taskName;
    EEG.data = double(EEG.data);

    fprintf('Loaded %d channels, %d samples at %.1f Hz\n', EEG.nbchan, EEG.pnts, EEG.srate);

    %% 4B. CONDITIONAL EVENT RELABELING (OLD SYSTEM: K2DJJ8 ONLY)
    if strcmpi(participantID, 'K2DJJ8')
        fprintf('\n--- Step: Relabeling trial events with trial numbers (Legacy System: K2DJJ8) ---\n');
        current_trial = '';
        relabel_targets = {'NPose', 'Neutral', 'Fight'};
        n_relabeled = 0;

        for e = 1:length(EEG.event)
            evt_type = EEG.event(e).type;
            if ~ischar(evt_type), continue; end

            onset_match = regexp(evt_type, '^TrialOnset(\d+)$', 'tokens', 'once');
            if ~isempty(onset_match)
                current_trial = onset_match{1};
                continue
            end

            if ~isempty(regexp(evt_type, '^TrialOffset\d+$', 'once'))
                current_trial = '';  % Reset once trial closes
                continue
            end

            if ismember(evt_type, relabel_targets)
                if isempty(current_trial)
                    warning('Event "%s" at latency %d found outside any TrialOnset/TrialOffset block — left unlabeled.', ...
                        evt_type, EEG.event(e).latency);
                    continue
                end
                EEG.event(e).type = [evt_type current_trial];
                n_relabeled = n_relabeled + 1;
            end
        end
        fprintf('Relabeled %d events with trial numbers.\n', n_relabeled);
    else
        % fprintf('\n--- Step: Skipping trial event relabeling (Newer Experiment System) ---\n');
    end

    %% --- Load Channel Locations ---
    if ~isempty(bemobil_config.channel_locations_filename)
        chanlocs_file = fullfile(bemobil_config.study_folder, bemobil_config.raw_data_folder, subEntity, ...
            bemobil_config.channel_locations_filename);
        if exist(chanlocs_file, 'file')
            EEG = pop_chanedit(EEG, 'load', chanlocs_file);
        else
            EEG = pop_chanedit(EEG, 'lookup', 'standard-10-5-cap385.elp');
        end
    else
        EEG = pop_chanedit(EEG, 'lookup', 'standard-10-5-cap385.elp');
    end

    %% --- Rename Channels ---
    if ~isempty(bemobil_config.rename_channels) && size(bemobil_config.rename_channels, 2) == 2
        for ren = 1:size(bemobil_config.rename_channels, 1)
            old_name = bemobil_config.rename_channels{ren, 1};
            new_name = bemobil_config.rename_channels{ren, 2};
            idx = find(strcmpi({EEG.chanlocs.labels}, old_name));
            if ~isempty(idx)
                EEG.chanlocs(idx).labels = new_name;
            end
        end
    end

    %% --- Mark EOG Channels ---
    if ~isempty(bemobil_config.eog_channels)
        for e = 1:length(bemobil_config.eog_channels)
            idx = find(strcmpi({EEG.chanlocs.labels}, bemobil_config.eog_channels{e}));
            if ~isempty(idx)
                EEG.chanlocs(idx).type = 'EOG';
            end
        end
    end

    %% --- Store Participant Metadata ---
    EEG.etc.bemobil = struct();
    EEG.etc.bemobil.participantID = participantID;
    EEG.etc.bemobil.sessionID = sessionID;
    EEG.etc.bemobil.runID = runID;
    EEG.etc.bemobil.taskName = taskName;
    EEG.etc.bemobil.original_xdf = xdf_fullpath;
    EEG.etc.bemobil.import_date = datestr(now, 'yyyy-mm-dd HH:MM:SS');

    %% --- Validate and Save Datasets ---
    EEG = eeg_checkset(EEG);

    % BIDS dataset save
    bids_filename = sprintf('%s_%s_%s_%s_eeg.set', subEntity, sesEntity, taskEntity, runEntity);
    fprintf('\nSaving BIDS: %s\n', fullfile(bids_out_folder, bids_filename));
    pop_saveset(EEG, 'filename', bids_filename, 'filepath', bids_out_folder);

    % Raw-EEGLAB dataset save
    raw_filename = sprintf('%s_%s_%s_%s_%s', subEntity, sesEntity, taskEntity, runEntity, bemobil_config.merged_filename);
    fprintf('Saving Raw EEGLAB: %s\n', fullfile(raw_eeglab_folder, raw_filename));
    pop_saveset(EEG, 'filename', raw_filename, 'filepath', raw_eeglab_folder);

    %% --- Create BIDS Sidecar Files ---
    % channels.tsv
    channels_tsv = fullfile(bids_out_folder, strrep(bids_filename, '_eeg.set', '_channels.tsv'));
    fid = fopen(channels_tsv, 'w');
    fprintf(fid, 'name\ttype\tunits\tsampling_frequency\treference\n');
    for ch = 1:EEG.nbchan
        ch_type = 'EEG';
        if isfield(EEG.chanlocs(ch), 'type') && ~isempty(EEG.chanlocs(ch).type)
            ch_type = EEG.chanlocs(ch).type;
        end
        fprintf(fid, '%s\t%s\tuV\t%.1f\tn/a\n', EEG.chanlocs(ch).labels, ch_type, EEG.srate);
    end
    fclose(fid);

    % eeg.json
    eeg_json = fullfile(bids_out_folder, strrep(bids_filename, '_eeg.set', '_eeg.json'));
    json_struct = struct(...
        'TaskName', taskName, ...
        'SamplingFrequency', EEG.srate, ...
        'EEGChannelCount', sum(strcmpi({EEG.chanlocs.type}, 'EEG') | cellfun(@isempty, {EEG.chanlocs.type})), ...
        'EOGChannelCount', sum(strcmpi({EEG.chanlocs.type}, 'EOG')), ...
        'RecordingType', 'continuous', ...
        'SoftwareFilters', 'n/a', ...
        'PowerLineFrequency', 50, ...
        'EEGReference', 'n/a' ...
    );
    json_text = jsonencode(json_struct);
    json_text = strrep(json_text, ',', sprintf(',\n  '));
    json_text = strrep(json_text, '{', sprintf('{\n  '));
    json_text = strrep(json_text, '}', sprintf('\n}'));
    fid = fopen(eeg_json, 'w');
    fprintf(fid, '%s', json_text);
    fclose(fid);

end

%% COMPLETE
fprintf('\n============ XDF IMPORT COMPLETE ============\n');
fprintf('Processed %d run(s) successfully for participant %s.\n', length(xdf_files), participantID);
fprintf('Next step: Run s02_bemobil_full_pipeline.m\n');