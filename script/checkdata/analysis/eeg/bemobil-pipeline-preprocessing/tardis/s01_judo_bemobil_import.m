function s01_judo_bemobil_import(participantID, sessionID, taskName)
%% BeMoBIL XDF Import Script (HPC Tardis Version)
% Usage:
% matlab -batch "s01_hpc_import_xdf('MH9HXJ', 'S001', 'heightaffordance')"

if isunix
    opengl('save', 'software');
    set(0, 'DefaultFigureVisible', 'off');
end

run('s00_judo_bemobil_config.m');
fprintf('============ BEMOBIL XDF IMPORT TO BIDS (HPC) ============\n');

subEntity  = sprintf('sub-%s', participantID);
sesEntity  = sprintf('ses-%s', sessionID);
taskEntity = sprintf('task-%s', taskName);

fprintf('\n--- Processing Target ---\n');
fprintf('Participant: %s | Session: %s | Task: %s\n', participantID, sessionID, taskName);

%% AUTOMATICALLY DETECT ALL RUNS
xdf_folder = fullfile(bemobil_config.raw_data_folder, subEntity, sesEntity, 'lslglobal');

if ~exist(xdf_folder, 'dir')
    error('LSL directory does not exist: %s', xdf_folder);
end

search_pattern = fullfile(xdf_folder, sprintf('%s_%s_*%s*.xdf', subEntity, sesEntity, taskName));
xdf_files = dir(search_pattern);

if isempty(xdf_files)
    warning('No files matched strict pattern. Searching for any XDF files...');
    xdf_files = dir(fullfile(xdf_folder, '*.xdf'));
end

if isempty(xdf_files)
    error('No XDF files found in folder: %s', xdf_folder);
end

fprintf('\nFound %d matching XDF file(s) to process.\n', length(xdf_files));

%% INITIALIZE EEGLAB
[ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab;

%% PROCESS RUNS
for r = 1:length(xdf_files)
    current_xdf_name = xdf_files(r).name;
    xdf_fullpath = fullfile(xdf_folder, current_xdf_name);
    
    fprintf('\n==================================================\n');
    fprintf(' Processing Run %d/%d: %s\n', r, length(xdf_files), current_xdf_name);
    fprintf('==================================================\n');

    runTokens = regexp(current_xdf_name, 'run-([a-zA-Z0-9]+)', 'tokens');
    if ~isempty(runTokens)
        runID = runTokens{1}{1};
    else
        runTokensAlt = regexp(current_xdf_name, '_(\d{2,3})_', 'tokens');
        if ~isempty(runTokensAlt)
            runID = runTokensAlt{1}{1};
        else
            runID = sprintf('%03d', r); 
        end
    end

    runEntity = sprintf('run-%s', runID);

    bids_out_folder = fullfile(bemobil_config.study_folder, bemobil_config.bids_target_folder, subEntity, sesEntity);
    raw_eeglab_folder = fullfile(bemobil_config.study_folder, bemobil_config.raw_EEGLAB_data_folder, subEntity, sesEntity);

    if ~exist(bids_out_folder, 'dir'), mkdir(bids_out_folder); end
    if ~exist(raw_eeglab_folder, 'dir'), mkdir(raw_eeglab_folder); end

    % Load XDF Stream non-interactively
    EEG = pop_loadxdf(xdf_fullpath, 'streamname', 'EEG');

    if isempty(EEG.data)
        error('EEG stream not found automatically in %s', current_xdf_name);
    end

    EEG.setname = sprintf('%s_%s_%s_%s_raw', subEntity, sesEntity, taskEntity, runEntity);
    EEG.filename = '';
    EEG.filepath = '';
    EEG.subject = participantID;
    EEG.session = str2double(regexprep(sessionID, '\D', ''));
    EEG.condition = taskName;
    EEG.data = double(EEG.data);

    % Legacy System Event Relabeling
    if strcmpi(participantID, 'K2DJJ8')
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
                current_trial = '';
                continue
            end

            if ismember(evt_type, relabel_targets) && ~isempty(current_trial)
                EEG.event(e).type = [evt_type current_trial];
                n_relabeled = n_relabeled + 1;
            end
        end
        fprintf('Relabeled %d events.\n', n_relabeled);
    end

    % Channel Locations & Edits
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

    EEG.etc.bemobil = struct();
    EEG.etc.bemobil.participantID = participantID;
    EEG.etc.bemobil.sessionID = sessionID;
    EEG.etc.bemobil.runID = runID;
    EEG.etc.bemobil.taskName = taskName;
    EEG.etc.bemobil.original_xdf = xdf_fullpath;
    EEG.etc.bemobil.import_date = datestr(now, 'yyyy-mm-dd HH:MM:SS');

    EEG = eeg_checkset(EEG);

    % Output Files
    bids_filename = sprintf('%s_%s_%s_%s_eeg.set', subEntity, sesEntity, taskEntity, runEntity);
    pop_saveset(EEG, 'filename', bids_filename, 'filepath', bids_out_folder);

    raw_filename = sprintf('%s_%s_%s_%s_%s', subEntity, sesEntity, taskEntity, runEntity, bemobil_config.merged_filename);
    pop_saveset(EEG, 'filename', raw_filename, 'filepath', raw_eeglab_folder);

    % Sidecar JSON/TSV Generation
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
    fid = fopen(eeg_json, 'w');
    fprintf(fid, '%s', json_text);
    fclose(fid);
end

fprintf('\n============ XDF IMPORT COMPLETE ============\n');
end