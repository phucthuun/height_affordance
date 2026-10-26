%% s02b_judo_bemobil_manual_reject.m -- Step 2B: manual segment rejection (interactive, local PC)
%
% Run in MATLAB on your own PC (with a display), once per run you want to inspect.
%
% Before:  copy the run folder 3_EEG-preprocessing/sub-<run>/ from tardis (at least
%          sub-<run>_preprocessed.set and .fdt) into the same place under your local project_root,
%          and set your local paths in s00_local_paths.m (copy s00_local_paths_TEMPLATE.m).
% What it does:
%   1. asks for participant, session, task, run and your initials
%   2. shows the preprocessed data (high-passed at 1 Hz for display only; condition labels hidden)
%   3. you drag over bad segments and press REJECT (close the window without REJECT to cancel)
%   4. saves the marks (sample intervals of preprocessed.set) with your initials, the protocol version and a
%      fingerprint of the data they belong to:
%        sub-<run>_rejected_segments.mat and .json   <- copy these two back to tardis
%        sub-<run>_preprocessed_and_rejected.set     (optional, for your own inspection only)
% Step 2C rebuilds the rejected data from preprocessed.set + the marks, and only if the fingerprint matches.

clear; close all; clc;

script_dir = fileparts(mfilename('fullpath'));
if isempty(script_dir)
    script_dir = pwd;
end
addpath(fullfile(script_dir, 'utils'));
cfg = judo_setup('2B');

%% 1. Which run, who is rating
answer = inputdlg( ...
    {'Participant ID (e.g. MH9HXJ):', 'Session ID (e.g. S001):', 'Task (e.g. heightaffordance):', ...
     'Run ID (e.g. 001):', 'Your initials (rater):', 'Notes (optional):'}, ...
    'Step 2B - manual segment rejection', [1 60], ...
    {'155T4T', 'S001', 'heightaffordance', '001', '', ''});
if isempty(answer)
    disp('Cancelled.');
    return
end
[participantID, sessionID, taskName, runID, rater, notes] = answer{:};
rater = strtrim(rater);
if isempty(rater)
    errordlg('Please enter your initials so the marks can be traced to a rater.', 'Step 2B');
    return
end
P = judo_paths(cfg, strtrim(participantID), strtrim(sessionID), strtrim(taskName), strtrim(runID));

%% 2. Load the preprocessed run
pre_path = fullfile(P.pre_folder, P.preprocessed_file);
if ~exist(pre_path, 'file')
    errordlg(sprintf(['Not found:\n%s\n\nCopy %s and its .fdt from tardis into this folder ' ...
        '(check project_root in s00_local_paths.m).'], pre_path, P.preprocessed_file), 'Step 2B');
    return
end
EEG_pre = pop_loadset('filename', P.preprocessed_file, 'filepath', P.pre_folder);
fingerprint = judo_eeg_fingerprint(EEG_pre);

marks_path = fullfile(P.pre_folder, P.marks_file);
if exist(marks_path, 'file')
    old = load(marks_path);
    if isfield(old, 'preprocessed_fingerprint') && strcmp(old.preprocessed_fingerprint, fingerprint)
        old_info = 'unknown rater and date';
        if isfield(old, 'rater') && isfield(old, 'marks_date')
            old_info = sprintf('rater %s, %s', old.rater, old.marks_date);
        end
        choice = questdlg(sprintf('Marks for this run already exist (%s). Redo them?', old_info), ...
            'Step 2B', 'Redo', 'Cancel', 'Cancel');
        if ~strcmp(choice, 'Redo')
            disp('Kept the existing marks.');
            return
        end
    else
        uiwait(warndlg(['Existing marks for this run belong to a different version of preprocessed.set ' ...
            '(or to the old pipeline). They will be replaced.'], 'Step 2B'));
    end
end

%% 3. Inspect and mark
EEG_view = EEG_pre;
if ~isempty(cfg.manual_rejection_view_highpass)
    EEG_view = pop_eegfiltnew(EEG_view, 'locutoff', cfg.manual_rejection_view_highpass, 'usefftfilt', judo_use_fftfilt(), 'plotfreqz', 0);
end
if cfg.manual_rejection_blind && ~isempty(EEG_view.event)
    % hide which condition an event belongs to; boundaries stay visible
    types = judo_event_types(EEG_view.event);
    for e = find(~strcmp(types, 'boundary'))
        EEG_view.event(e).type = 'event';
    end
end

% eegplot's REJECT button puts the marked windows into TMPREJ in the base workspace and runs 'command' there
evalin('base', 'clear TMPREJ judo_2b_rejected');
eegplot(EEG_view.data, 'srate', EEG_view.srate, 'events', EEG_view.event, 'eloc_file', EEG_view.chanlocs, ...
    'winlength', cfg.manual_rejection_window_s, 'title', ...
    sprintf('Step 2B %s - drag over bad segments, then press REJECT', P.bids_base), ...
    'command', 'judo_2b_rejected = true;', 'butlabel', 'REJECT', 'tag', 'JUDO_2B_EEGPLOT');
clear EEG_view
plot_window = findobj('tag', 'JUDO_2B_EEGPLOT');
if ~isempty(plot_window)
    uiwait(plot_window(1));
end

if ~evalin('base', 'exist(''judo_2b_rejected'', ''var'') == 1')
    disp('Window closed without REJECT: nothing saved.');
    return
end
marked_windows = evalin('base', 'TMPREJ');
evalin('base', 'clear TMPREJ judo_2b_rejected');

regions = zeros(0, 2);
if ~isempty(marked_windows)
    regions = judo_intervals('merge', round(marked_windows(:, 1:2)), EEG_pre.pnts); % [start end] samples
end
if isempty(regions)
    choice = questdlg('No segments were marked. Save this run as "nothing to reject"?', 'Step 2B', ...
        'Save', 'Cancel', 'Cancel');
    if ~strcmp(choice, 'Save')
        disp('Nothing saved.');
        return
    end
end

%% 4. Save the marks (+ optional rejected dataset)
rejected_samples = judo_intervals('count', regions);
reject_segments_latency = regions; %#ok<NASGU> name kept from the previous pipeline version
preprocessed_fingerprint = fingerprint; %#ok<NASGU>
srate = EEG_pre.srate; %#ok<NASGU>
pnts = EEG_pre.pnts; %#ok<NASGU>
protocol = cfg.manual_rejection_protocol; %#ok<NASGU>
blind = cfg.manual_rejection_blind; %#ok<NASGU>
view_highpass_hz = cfg.manual_rejection_view_highpass; %#ok<NASGU>
rejected_seconds = rejected_samples / EEG_pre.srate;
rejected_percent = 100 * rejected_samples / EEG_pre.pnts;
provenance = judo_provenance(cfg);
marks_date = provenance.date; %#ok<NASGU>
save(marks_path, 'reject_segments_latency', 'preprocessed_fingerprint', 'srate', 'pnts', 'rater', 'notes', ...
    'protocol', 'blind', 'view_highpass_hz', 'rejected_seconds', 'rejected_percent', 'marks_date', 'provenance');

judo_json_write(fullfile(P.pre_folder, P.marks_json), struct( ...
    'step', '2B', 'run', P.bids_base, 'rater', rater, 'notes', notes, ...
    'protocol', cfg.manual_rejection_protocol, 'blind_to_condition', cfg.manual_rejection_blind, ...
    'display_highpass_hz', cfg.manual_rejection_view_highpass, 'srate', EEG_pre.srate, ...
    'n_samples', EEG_pre.pnts, 'n_segments', size(regions, 1), 'rejected_seconds', rejected_seconds, ...
    'rejected_percent', rejected_percent, 'segments_samples', regions, ...
    'segments_seconds', (regions - 1) / EEG_pre.srate, 'preprocessed_fingerprint', fingerprint, ...
    'provenance', provenance));

if cfg.manual_rejection_save_set
    EEG_rej = EEG_pre;
    if ~isempty(regions)
        EEG_rej = eeg_eegrej(EEG_pre, regions);
    end
    pop_saveset(EEG_rej, 'filename', P.rejected_file, 'filepath', P.pre_folder);
end

msg = sprintf(['Saved %d segment(s), %.1f s (%.1f%% of the run).\n\nCopy these two files back to tardis, ' ...
    'into 3_EEG-preprocessing/%s/:\n  %s\n  %s'], size(regions, 1), rejected_seconds, rejected_percent, ...
    P.sub_base, P.marks_file, P.marks_json);
disp(msg);
msgbox(msg, 'Step 2B done');
