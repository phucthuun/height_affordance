%% BeMoBIL XDF Import Script with Interactive Participant Selection
% Imports XDF files and converts to BIDS-compliant EEGLAB format
% Preserves original participant IDs while maintaining BIDS structure
%
% Input:  XDF file from sourcedata
% Output: BIDS-formatted data in derivatives/EEG_bemobil_pipeline/1_BIDS-data
%         and raw EEGLAB format in 2_raw-EEGLAB

clear; clc; close all;

%% 0. LOAD CONFIGURATION
% Make sure judo_bemobil_config.m is in your path or current directory
run('tp_judo_bemobil_config.m');MH9HXJ

fprintf('============ BEMOBIL XDF IMPORT TO BIDS ============\n');

%% 1. INTERACTIVE PARTICIPANT SELECTION

% --- Dialog box for participant metadata ---
prompt = {
    'Enter Participant ID (e.g., MH9HXJ):', ...
    'Enter Session ID (e.g., S001):', ...
    'Enter Run ID (e.g., 001):', ...
    'Enter Task Name (e.g., heightaffordance):'
};
dlgtitle = 'XDF Import - Select Target Data';
dims = [1 60];
definput = {'MH9HXJ', 'S001', '001', 'heightaffordance'};
userInput = inputdlg(prompt, dlgtitle, dims, definput);

if isempty(userInput)
    error('Import cancelled by user.');
end

% Store original IDs (preserving case and format)
participantID = userInput{1};
sessionID     = userInput{2};
runID         = userInput{3};
taskName      = userInput{4};

% Build BIDS-compliant entity strings
subEntity  = sprintf('sub-%s', participantID);
sesEntity  = sprintf('ses-%s', sessionID);
runEntity  = sprintf('run-%s', runID);
taskEntity = sprintf('task-%s', taskName);

fprintf('\n--- Import Configuration ---\n');
fprintf('Participant: %s\n', participantID);
fprintf('Session:     %s\n', sessionID);
fprintf('Run:         %s\n', runID);
fprintf('Task:        %s\n', taskName);

%% 2. CONSTRUCT FILE PATHS

% Source XDF path (your specific naming convention)
xdf_folder = fullfile(bemobil_config.raw_data_folder, subEntity, sesEntity, 'lslglobal');
xdf_filename = sprintf('%s_%s_%s_%s_lslglobal.xdf', subEntity, sesEntity, taskEntity, runEntity);
xdf_fullpath = fullfile(xdf_folder, xdf_filename);

% Verify XDF exists
if ~exist(xdf_fullpath, 'file')
    % Try alternative naming patterns
    alt_patterns = {
        sprintf('%s_%s_%s_%s_lslglobal.xdf', subEntity, sesEntity, taskEntity, runEntity),
        sprintf('%s_%s_%s_run-%s_lslglobal.xdf', subEntity, sesEntity, taskEntity, runID),
        sprintf('%s_%s_task-%s_run-%s_lslglobal.xdf', subEntity, sesEntity, taskName, runID)
    };

    found = false;
    for p = 1:length(alt_patterns)
        test_path = fullfile(xdf_folder, alt_patterns{p});
        if exist(test_path, 'file')
            xdf_fullpath = test_path;
            xdf_filename = alt_patterns{p};
            found = true;
            fprintf('Found XDF with alternative pattern: %s\n', xdf_filename);
            break;
        end
    end

    if ~found
        % List available files in folder
        fprintf('\nXDF file not found. Searching in: %s\n', xdf_folder);
        if exist(xdf_folder, 'dir')
            files = dir(fullfile(xdf_folder, '*.xdf'));
            if ~isempty(files)
                fprintf('Available XDF files:\n');
                for f = 1:length(files)
                    fprintf('  %d: %s\n', f, files(f).name);
                end
                choice = inputdlg('Enter file number to use:', 'Select XDF', [1 40], {'1'});
                if ~isempty(choice)
                    xdf_filename = files(str2double(choice{1})).name;
                    xdf_fullpath = fullfile(xdf_folder, xdf_filename);
                else
                    error('No file selected.');
                end
            else
                error('No XDF files found in: %s', xdf_folder);
            end
        else
            error('LSL folder does not exist: %s', xdf_folder);
        end
    end
end

fprintf('\nSource XDF: %s\n', xdf_fullpath);

% Output directories
bids_out_folder = fullfile(bemobil_config.study_folder, bemobil_config.bids_target_folder, subEntity, sesEntity);
raw_eeglab_folder = fullfile(bemobil_config.study_folder, bemobil_config.raw_EEGLAB_data_folder, subEntity, sesEntity);

% Create output directories
if ~exist(bids_out_folder, 'dir'), mkdir(bids_out_folder); end
if ~exist(raw_eeglab_folder, 'dir'), mkdir(raw_eeglab_folder); end

%% 3. INITIALIZE EEGLAB

fprintf('\n--- Initializing EEGLAB ---\n');
[ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab;

%% 4. LOAD XDF FILE

fprintf('\n--- Step 1: Loading XDF Multi-Stream Data ---\n');

% Load XDF with clock synchronization
EEG = pop_loadxdf(xdf_fullpath, 'streamname', 'EEG');

% If EEG stream not found, list available streams
if isempty(EEG.data)
    warning('EEG stream not found. Loading XDF to inspect available streams...');
    streams = load_xdf(xdf_fullpath);
    fprintf('\nAvailable streams in XDF:\n');
    for s = 1:length(streams)
        fprintf('  %d: %s (Type: %s, Channels: %d)\n', ...
            s, streams{s}.info.name, streams{s}.info.type, ...
            str2double(streams{s}.info.channel_count));
    end
    
    stream_choice = inputdlg('Enter stream name to use:', 'Select EEG Stream', [1 50], {'EEG'});
    if ~isempty(stream_choice)
        EEG = pop_loadxdf(xdf_fullpath, 'streamname', stream_choice{1}, 'handleJitter', 'on');
    else
        error('No stream selected.');
    end
end

% Set dataset identifiers
EEG.setname = sprintf('%s_%s_%s_%s_raw', subEntity, sesEntity, taskEntity, runEntity);
EEG.filename = '';
EEG.filepath = '';
EEG.subject = participantID;
EEG.session = str2double(regexprep(sessionID, '\D', ''));
EEG.condition = taskName;

% Ensure double precision
EEG.data = double(EEG.data);

fprintf('Loaded %d channels, %d samples at %.1f Hz\n', EEG.nbchan, EEG.pnts, EEG.srate);

%% 5. LOAD CHANNEL LOCATIONS

fprintf('\n--- Step 2: Loading Channel Locations ---\n');

if ~isempty(bemobil_config.channel_locations_filename)
    % Custom channel locations file
    chanlocs_file = fullfile(bemobil_config.study_folder, bemobil_config.raw_data_folder, subEntity, ...
        bemobil_config.channel_locations_filename);
    if exist(chanlocs_file, 'file')
        EEG = pop_chanedit(EEG, 'load', chanlocs_file);
        fprintf('Loaded custom channel locations from: %s\n', chanlocs_file);
    else
        warning('Custom chanlocs file not found: %s\nUsing standard 10-5 locations.', chanlocs_file);
        EEG = pop_chanedit(EEG, 'lookup', 'standard-10-5-cap385.elp');
    end
else
    % Use standard 10-5 locations
    EEG = pop_chanedit(EEG, 'lookup', 'standard-10-5-cap385.elp');
    fprintf('Applied standard 10-5 channel locations.\n');
end

%% 6. REMOVE UNUSED CHANNELS

% if ~isempty(bemobil_config.channels_to_remove)
%     fprintf('\n--- Removing unused channels: %s ---\n', strjoin(bemobil_config.channels_to_remove, ', '));
%     EEG = pop_select(EEG, 'nochannel', bemobil_config.channels_to_remove);
% end

%% 7. RENAME CHANNELS (if configured)

if ~isempty(bemobil_config.rename_channels)
    fprintf('\n--- Renaming channels ---\n');
    if size(bemobil_config.rename_channels, 2) == 2
        for r = 1:size(bemobil_config.rename_channels, 1)
            old_name = bemobil_config.rename_channels{r, 1};
            new_name = bemobil_config.rename_channels{r, 2};
            idx = find(strcmpi({EEG.chanlocs.labels}, old_name));
            if ~isempty(idx)
                EEG.chanlocs(idx).labels = new_name;
                fprintf('  %s -> %s\n', old_name, new_name);
            end
        end
    end
end

%% 8. MARK EOG CHANNELS

if ~isempty(bemobil_config.eog_channels)
    fprintf('\n--- Marking EOG channels ---\n');
    for e = 1:length(bemobil_config.eog_channels)
        idx = find(strcmpi({EEG.chanlocs.labels}, bemobil_config.eog_channels{e}));
        if ~isempty(idx)
            EEG.chanlocs(idx).type = 'EOG';
            fprintf('  %s marked as EOG\n', bemobil_config.eog_channels{e});
        else
            warning('EOG channel not found: %s', bemobil_config.eog_channels{e});
        end
    end
end

%% 9. STORE PARTICIPANT METADATA

% Create a metadata structure for BIDS compliance
EEG.etc.bemobil = struct();
EEG.etc.bemobil.participantID = participantID;
EEG.etc.bemobil.sessionID = sessionID;
EEG.etc.bemobil.runID = runID;
EEG.etc.bemobil.taskName = taskName;
EEG.etc.bemobil.original_xdf = xdf_fullpath;
EEG.etc.bemobil.import_date = datestr(now, 'yyyy-mm-dd HH:MM:SS');

%% 10. VALIDATE AND SAVE

EEG = eeg_checkset(EEG);

% BIDS-compliant filename
bids_filename = sprintf('%s_%s_%s_%s_eeg.set', subEntity, sesEntity, taskEntity, runEntity);

% Save to BIDS folder
fprintf('\n--- Saving BIDS-formatted data ---\n');
fprintf('Output: %s\n', fullfile(bids_out_folder, bids_filename));
pop_saveset(EEG, 'filename', bids_filename, 'filepath', bids_out_folder);

% Also save to raw-EEGLAB folder (merged format for pipeline)
raw_filename = sprintf('%s_%s_%s_%s_%s', subEntity, sesEntity, taskEntity, runEntity, bemobil_config.merged_filename);
fprintf('Output: %s\n', fullfile(raw_eeglab_folder, raw_filename));
pop_saveset(EEG, 'filename', raw_filename, 'filepath', raw_eeglab_folder);

%% 11. CREATE BIDS SIDECAR FILES

fprintf('\n--- Creating BIDS sidecar files ---\n');

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
fprintf('Created: %s\n', channels_tsv);

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
% Pretty print JSON
json_text = strrep(json_text, ',', sprintf(',\n  '));
json_text = strrep(json_text, '{', sprintf('{\n  '));
json_text = strrep(json_text, '}', sprintf('\n}'));
fid = fopen(eeg_json, 'w');
fprintf(fid, '%s', json_text);
fclose(fid);
fprintf('Created: %s\n', eeg_json);

%% COMPLETE

fprintf('\n============ XDF IMPORT COMPLETE ============\n');
fprintf('Participant %s imported successfully.\n', participantID);
fprintf('Data saved to:\n');
fprintf('  BIDS:      %s\n', bids_out_folder);
fprintf('  Raw-EEGLAB: %s\n', raw_eeglab_folder);
fprintf('\nNext step: Run s02_bemobil_full_pipeline.m\n');
