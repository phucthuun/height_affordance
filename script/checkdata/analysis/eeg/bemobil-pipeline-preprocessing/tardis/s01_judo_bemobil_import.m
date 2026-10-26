function s01_judo_bemobil_import(participantID, sessionID, taskName)
%S01_JUDO_BEMOBIL_IMPORT  Step 1: import the EEG stream of every XDF run of one participant/session/task.
%
%   matlab -batch "s01_judo_bemobil_import('155T4T', 'S001', 'heightaffordance')"
%
%   Input   10_Data/sourcedata/sub-<id>/ses-<ses>/lslglobal/sub-<id>_ses-<ses>_*<task>*.xdf
%   Output  2_raw-EEGLAB/sub-<id>/ses-<ses>/sub-<run>_merged_EEG.set (+ .json provenance sidecar)
%           1_BIDS-data/sub-<id>/ses-<ses>/sub-<run>_eeg.set + _channels.tsv + _eeg.json
%           (BIDS-style copy, not a validated BIDS dataset; switch off with cfg.save_bids_copy)
%
%   Motion sensor channels in the EEG stream are typed (ACCEL / GYRO / MISC) here and split off in step 2A.

cfg = judo_setup('1');
subEntity = sprintf('sub-%s', participantID);
sesEntity = sprintf('ses-%s', sessionID);

xdf_folder = fullfile(cfg.raw_data_folder, subEntity, sesEntity, 'lslglobal');
if ~exist(xdf_folder, 'dir')
    error('judo:s01', 'LSL folder does not exist: %s', xdf_folder);
end

xdf_files = dir(fullfile(xdf_folder, sprintf('%s_%s_*%s*.xdf', subEntity, sesEntity, taskName)));
if isempty(xdf_files)
    present = dir(fullfile(xdf_folder, '*.xdf'));
    error('judo:s01', ['No XDF file matches %s_%s_*%s*.xdf in %s.\nFiles present: %s\n' ...
        'Rename the file(s) or check the task name; other files are not imported automatically.'], ...
        subEntity, sesEntity, taskName, xdf_folder, strjoin({present.name}, ', '));
end
fprintf('[judo] %d XDF file(s) to import.\n', numel(xdf_files));

chanloc_template = fullfile(fileparts(which('dipfitdefs')), 'standard_BESA', 'standard-10-5-cap385.elp');

for r = 1:numel(xdf_files)
    xdf_name = xdf_files(r).name;
    xdf_path = fullfile(xdf_folder, xdf_name);
    runID = run_id_from_name(xdf_name, numel(xdf_files));
    P = judo_paths(cfg, participantID, sessionID, taskName, runID);

    fprintf('\n==== Importing run %d/%d: %s -> run %s ====\n', r, numel(xdf_files), xdf_name, runID);

    EEG = pop_loadxdf(xdf_path, 'streamname', cfg.xdf_eeg_stream_name);
    if isempty(EEG.data)
        error('judo:s01', 'No "%s" stream in %s', cfg.xdf_eeg_stream_name, xdf_name);
    end

    EEG.setname   = sprintf('%s_raw', P.sub_base);
    EEG.filename  = '';
    EEG.filepath  = '';
    EEG.subject   = participantID;
    EEG.session   = str2double(regexprep(sessionID, '\D', ''));
    EEG.condition = taskName;
    EEG.data      = double(EEG.data);

    % Legacy recording system: append the trial number to the condition markers (e.g. 'NPose' -> 'NPose12')
    if strcmpi(participantID, 'K2DJJ8')
        EEG = relabel_legacy_events(EEG);
    end

    % Channel locations (template), then channel types
    if ~isempty(cfg.channel_locations_filename)
        chanlocs_file = fullfile(cfg.raw_data_folder, subEntity, cfg.channel_locations_filename);
        if exist(chanlocs_file, 'file')
            EEG = pop_chanedit(EEG, 'load', chanlocs_file);
        else
            warning('judo:s01', 'Channel location file not found (%s); using the 10-5 template.', chanlocs_file);
            EEG = pop_chanedit(EEG, 'lookup', chanloc_template);
        end
    else
        EEG = pop_chanedit(EEG, 'lookup', chanloc_template);
    end
    for ch = 1:EEG.nbchan
        EEG.chanlocs(ch).type = channel_type(EEG.chanlocs(ch).labels, cfg);
    end

    prov = judo_provenance(cfg);
    EEG.etc.bemobil = struct('participantID', participantID, 'sessionID', sessionID, 'runID', runID, ...
        'taskName', taskName, 'original_xdf', xdf_path, 'import_date', prov.date);
    EEG.etc.judo.import = prov;
    EEG = eeg_checkset(EEG);

    % EEGLAB copy that step 2A reads
    if ~exist(P.raw_folder, 'dir')
        mkdir(P.raw_folder);
    end
    pop_saveset(EEG, 'filename', P.merged_file, 'filepath', P.raw_folder);
    judo_json_write(fullfile(P.raw_folder, strrep(P.merged_file, '.set', '.json')), struct( ...
        'step', '1', 'source_xdf', xdf_path, 'stream', cfg.xdf_eeg_stream_name, 'srate', EEG.srate, ...
        'n_channels', EEG.nbchan, 'duration_s', EEG.pnts / EEG.srate, 'n_events', numel(EEG.event), ...
        'provenance', prov));

    if cfg.save_bids_copy
        write_bids_copy(EEG, P, cfg, taskName);
    end
end

fprintf('\n[judo] Step 1 done for %s.\n', participantID);
end

%% ------------------------------------------------------------------------------------------------------------
function runID = run_id_from_name(name, n_files)
tok = regexp(name, 'run-([a-zA-Z0-9]+)', 'tokens', 'once');
if isempty(tok)
    tok = regexp(name, '_(\d{2,3})_', 'tokens', 'once');
end
if ~isempty(tok)
    runID = tok{1};
elseif n_files == 1
    runID = '001';
    warning('judo:s01', 'No run number in %s; using run 001 because it is the only file.', name);
else
    error('judo:s01', ['No run number ("run-001") in %s and there are %d files, so runs cannot be told apart.\n' ...
        'Rename the files to contain run-<ID>.'], name, n_files);
end
end

function EEG = relabel_legacy_events(EEG)
current_trial = '';
targets = {'NPose', 'Neutral', 'Fight'};
n = 0;
for e = 1:numel(EEG.event)
    t = EEG.event(e).type;
    if ~ischar(t)
        continue
    end
    onset = regexp(t, '^TrialOnset(\d+)$', 'tokens', 'once');
    if ~isempty(onset)
        current_trial = onset{1};
    elseif ~isempty(regexp(t, '^TrialOffset\d+$', 'once'))
        current_trial = '';
    elseif ismember(t, targets) && ~isempty(current_trial)
        EEG.event(e).type = [t current_trial];
        n = n + 1;
    end
end
fprintf('[judo] Relabeled %d legacy condition events.\n', n);
end

function t = channel_type(label, cfg)
if ~ismember(label, cfg.motion_channel_labels)
    t = 'EEG';
elseif startsWith(label, 'Acc')
    t = 'ACCEL';
elseif startsWith(label, 'Gyro')
    t = 'GYRO';
else
    t = 'MISC';
end
end

function write_bids_copy(EEG, P, cfg, taskName)
if ~exist(P.bids_folder, 'dir')
    mkdir(P.bids_folder);
end
pop_saveset(EEG, 'filename', P.bids_file, 'filepath', P.bids_folder);

types = {EEG.chanlocs.type};
tsv = fullfile(P.bids_folder, strrep(P.bids_file, '_eeg.set', '_channels.tsv'));
fid = fopen(tsv, 'w');
fprintf(fid, 'name\ttype\tunits\tsampling_frequency\treference\n');
for ch = 1:EEG.nbchan
    if strcmp(types{ch}, 'EEG')
        bids_type = 'EEG'; units = 'uV'; ref = cfg.ref_channel;
    else
        bids_type = 'MISC'; units = 'n/a'; ref = 'n/a'; % accelerometer / gyroscope / orientation
    end
    fprintf(fid, '%s\t%s\t%s\t%.4f\t%s\n', EEG.chanlocs(ch).labels, bids_type, units, EEG.srate, ref);
end
fclose(fid);

meta = struct( ...
    'TaskName', taskName, ...
    'SamplingFrequency', EEG.srate, ...
    'EEGChannelCount', sum(strcmp(types, 'EEG')), ...
    'EOGChannelCount', 0, ...
    'MiscChannelCount', sum(~strcmp(types, 'EEG')), ...
    'RecordingType', 'continuous', ...
    'RecordingDuration', EEG.pnts / EEG.srate, ...
    'SoftwareFilters', 'n/a', ...
    'PowerLineFrequency', cfg.power_line_hz, ...
    'EEGReference', cfg.ref_channel);
judo_json_write(fullfile(P.bids_folder, strrep(P.bids_file, '_eeg.set', '_eeg.json')), meta);
end
