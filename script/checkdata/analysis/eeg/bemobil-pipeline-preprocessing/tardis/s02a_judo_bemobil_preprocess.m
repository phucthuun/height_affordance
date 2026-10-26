function s02a_judo_bemobil_preprocess(participantID, sessionID, taskName)
%S02A_JUDO_BEMOBIL_PREPROCESS  Step 2A: trim to the trials, split off motion channels, bemobil preprocessing.
%
%   matlab -batch "s02a_judo_bemobil_preprocess('155T4T', 'S001', 'heightaffordance')"
%
%   Per run:
%     1. trim to cfg.trim_padding_s (1 s) before the first TrialOnset and after the last TrialOffset
%     2. save the motion sensor channels to 6_single-subject-motion-analysis/sub-<run>/sub-<run>_motion.set
%     3. bemobil preprocessing on the EEG channels: ZapLine-Plus, FCz added back, repeated bad-channel
%        detection (fixed random seed), spherical interpolation, average reference
%     4. QC numbers to 8_quality-control/sub-<run>/sub-<run>_qc-2a.json
%
%   A run is skipped (reused) when preprocessed.set exists and its .json sidecar shows the same settings and
%   the same input file. Otherwise it is recomputed from scratch, which also replaces outputs of the old
%   pipeline version. A failed run does not stop the others; the job fails at the end if any run failed.

cfg = judo_setup('2A');
runIDs = judo_find_runs(cfg, participantID, sessionID, taskName, 'merged');

failures = {};
for r = 1:numel(runIDs)
    P = judo_paths(cfg, participantID, sessionID, taskName, runIDs{r});
    fprintf('\n==== Step 2A, run %d/%d: %s ====\n', r, numel(runIDs), P.bids_base);
    try
        preprocess_run(cfg, P);
    catch err
        failures{end + 1} = sprintf('%s: %s', P.bids_base, err.message); %#ok<AGROW>
        fprintf(2, '[judo] Run %s FAILED: %s\n', P.bids_base, getReport(err, 'extended', 'hyperlinks', 'off'));
        judo_json_write(P.qc_2a_json, struct('step', '2A', 'status', 'failed', 'error', err.message, ...
            'run', run_info(P), 'provenance', judo_provenance(cfg)));
    end
    close all hidden
end

if ~isempty(failures)
    error('judo:s02a', 'Step 2A failed for %d run(s):\n  %s', numel(failures), strjoin(failures, '\n  '));
end
fprintf('\n[judo] Step 2A done for %s.\n', participantID);
end

%% ------------------------------------------------------------------------------------------------------------
function preprocess_run(cfg, P)
ALLEEG = [];
CURRENTSET = 0;

merged_path = fullfile(P.raw_folder, P.merged_file);
EEG = pop_loadset('filename', P.merged_file, 'filepath', P.raw_folder);

motion_present = intersect(cfg.motion_channel_labels, {EEG.chanlocs.labels}, 'stable');
cfg_run = cfg;
cfg_run.channels_to_remove = motion_present;

settings = settings_2a(cfg_run);
settings_hash = judo_hash(jsonencode(settings));
input_fp = judo_file_fingerprint(merged_path);

sidecar_path = fullfile(P.pre_folder, P.preprocessed_json);
sidecar = judo_json_read(sidecar_path);
up_to_date = exist(fullfile(P.pre_folder, P.preprocessed_file), 'file') && ~isempty(sidecar) && ...
    isfield(sidecar, 'settings_hash') && strcmp(sidecar.settings_hash, settings_hash) && ...
    isfield(sidecar, 'input_fingerprint') && strcmp(sidecar.input_fingerprint, input_fp);

if up_to_date
    fprintf('[judo] preprocessed.set is up to date (same settings and input) -> reusing it.\n');
    EEG_pre = pop_loadset('filename', P.preprocessed_file, 'filepath', P.pre_folder);
    trim = sidecar.trim;
    reused = true;
else
    if exist(fullfile(P.pre_folder, P.preprocessed_file), 'file')
        fprintf('[judo] Existing preprocessed.set has other settings/input or no sidecar -> recomputing.\n');
    end
    reused = false;

    [EEG, trim] = judo_trim_to_trials(EEG, cfg);
    fprintf('[judo] Trimmed %.1f s -> %.1f s (%.1f s removed at the start, %.1f s at the end).\n', ...
        trim.duration_before_s, trim.duration_after_s, trim.removed_start_s, trim.removed_end_s);

    % Motion channels: keep them (same samples as the EEG) before bemobil removes them
    if ~isempty(motion_present)
        EEG_motion = pop_select(EEG, 'channel', motion_present);
        EEG_motion.setname = [P.sub_base '_motion'];
        EEG_motion.etc.judo.trim = trim;
        if ~exist(P.motion_folder, 'dir')
            mkdir(P.motion_folder);
        end
        pop_saveset(EEG_motion, 'filename', P.motion_file, 'filepath', P.motion_folder);
        clear EEG_motion
        fprintf('[judo] Saved %d motion channels to %s\n', numel(motion_present), fullfile(P.motion_folder, P.motion_file));
    else
        warning('judo:s02a', 'No motion channels found in %s.', P.merged_file);
    end

    EEG.etc.judo.trim = trim;
    EEG.datfile = '';
    rng(cfg.random_seed, 'twister'); % reproducible bad-channel detection
    [~, EEG_pre] = bemobil_process_all_EEG_preprocessing(P.bids_base, cfg_run, ALLEEG, EEG, CURRENTSET, 1);
    clear EEG

    judo_json_write(sidecar_path, struct( ...
        'step', '2A', ...
        'settings_hash', settings_hash, ...
        'settings', settings, ...
        'input_file', merged_path, ...
        'input_fingerprint', input_fp, ...
        'output_fingerprint', judo_eeg_fingerprint(EEG_pre), ...
        'trim', trim, ...
        'motion_channels', {motion_present}, ...
        'provenance', judo_provenance(cfg)));
end

qc = qc_2a(cfg, P, EEG_pre, trim, motion_present, reused, settings_hash);
judo_json_write(P.qc_2a_json, qc);
fprintf('[judo] QC written to %s\n', P.qc_2a_json);
end

%% ------------------------------------------------------------------------------------------------------------
function s = settings_2a(cfg)
% Everything that changes preprocessed.set. A change here makes step 2A recompute the run.
fields = {'pipeline_version', 'trim_padding_s', 'trial_onset_regex', 'trial_offset_regex', ...
    'channels_to_remove', 'random_seed', 'eog_channels', 'ref_channel', 'rename_channels', 'resample_freq', ...
    'chancorr_crit', 'chan_max_broken_time', 'chan_detect_num_iter', 'chan_detected_fraction_threshold', ...
    'flatline_crit', 'line_noise_crit', 'num_chan_rej_max_target', 'channel_locations_filename', 'zaplineConfig'};
s = struct();
for i = 1:numel(fields)
    s.(fields{i}) = cfg.(fields{i});
end
end

function info = run_info(P)
info = struct('participant', P.participant, 'session', P.session, 'task', P.task, 'run', P.run, ...
    'bids_base', P.bids_base);
end

function qc = qc_2a(cfg, P, EEG, trim, motion_present, reused, settings_hash)
qc = struct();
qc.step = '2A';
qc.status = 'ok';
qc.run = run_info(P);
qc.provenance = judo_provenance(cfg);
qc.reused_existing_output = reused;
qc.settings_hash = settings_hash;
qc.output_fingerprint = judo_eeg_fingerprint(EEG);

qc.recording = struct( ...
    'srate', EEG.srate, ...
    'duration_before_trim_s', trim.duration_before_s, ...
    'duration_s', EEG.pnts / EEG.srate, ...
    'first_trial_onset_s', trim.first_trial_onset_s, ...
    'last_trial_offset_s', trim.last_trial_offset_s, ...
    'n_trial_onsets', trim.n_trial_onsets, ...
    'n_trial_offsets', trim.n_trial_offsets, ...
    'trim_padding_s', trim.padding_s, ...
    'padding_before_actual_s', trim.padding_before_actual_s, ...
    'padding_after_actual_s', trim.padding_after_actual_s, ...
    'removed_start_s', trim.removed_start_s, ...
    'removed_end_s', trim.removed_end_s, ...
    'used_fallback_events', trim.used_fallback);
qc.events = judo_count_conditions(EEG, cfg);

qc.motion = struct('channels', {motion_present}, 'file', fullfile(P.motion_folder, P.motion_file), ...
    'saved', ~isempty(motion_present));

labels = {EEG.chanlocs.labels};
interp = [];
if isfield(EEG.etc, 'interpolated_channels')
    interp = EEG.etc.interpolated_channels(:)';
end
badness = [];
threshold = NaN;
n_iterations = NaN;
iterations_identical = [];
if isfield(EEG.etc, 'channel_rejection')
    if isfield(EEG.etc.channel_rejection, 'bad_channel_detection')
        detections = EEG.etc.channel_rejection.bad_channel_detection;
        badness = mean(detections, 2)';
        n_iterations = size(detections, 2);
        % clean_rawdata >= 2.7 resets the random generator, which makes all iterations identical
        iterations_identical = all(all(detections == detections(:, 1)));
    end
    if isfield(EEG.etc.channel_rejection, 'detection_threshold')
        threshold = EEG.etc.channel_rejection.detection_threshold;
    end
end
rank = NaN;
if isfield(EEG.etc, 'rank')
    rank = EEG.etc.rank;
end
qc.channels = struct( ...
    'n_channels', EEG.nbchan, ...
    'labels', {labels}, ...
    'reference', cfg.ref_channel, ...
    'interpolated', {labels(interp)}, ...
    'n_interpolated', numel(interp), ...
    'fraction_interpolated', numel(interp) / EEG.nbchan, ...
    'detection_fraction_threshold', threshold, ...
    'detection_fraction_per_channel', badness, ...
    'detection_iterations', n_iterations, ...
    'detection_iterations_identical', iterations_identical, ...
    'rank', rank);

qc.zapline = struct('noisefreqs', [], 'found_noise', [], 'n_components_removed', [], ...
    'proportion_removed', [], 'ratio_noise_raw', [], 'ratio_noise_clean', []);
if isfield(EEG.etc, 'zapline')
    z = EEG.etc.zapline;
    if isfield(z, 'config') && isfield(z.config, 'noisefreqs')
        qc.zapline.noisefreqs = z.config.noisefreqs;
    end
    if isfield(z, 'analyticsResults')
        a = z.analyticsResults;
        qc.zapline.found_noise          = get_field(a, 'foundNoise');
        qc.zapline.n_components_removed = get_field(a, 'NremoveFinal');
        qc.zapline.proportion_removed   = get_field(a, 'proportionRemoved');
        qc.zapline.ratio_noise_raw      = get_field(a, 'ratioNoiseRaw');
        qc.zapline.ratio_noise_clean    = get_field(a, 'ratioNoiseClean');
    end
end

% Figures bemobil already writes next to the data (embedded in the HTML report)
fig = @(suffix) fullfile(P.pre_folder, [P.sub_base suffix]);
qc.figures = struct( ...
    'raw', fig('_raw.png'), ...
    'bad_channels', fig('_bad_channels.png'), ...
    'bad_channels_detection', fig('_bad_channels_detection.png'), ...
    'interpolated_channels', fig('_interpolated_channels.png'), ...
    'zapline', {zapline_figures(P)});

qc.warnings = {};
if qc.channels.fraction_interpolated > cfg.qc.max_interpolated_fraction
    qc.warnings{end + 1} = sprintf('%d of %d channels (%.0f%%) interpolated (limit %.0f%%).', ...
        numel(interp), EEG.nbchan, 100 * qc.channels.fraction_interpolated, 100 * cfg.qc.max_interpolated_fraction);
end
if trim.used_fallback
    qc.warnings{end + 1} = 'No TrialOnset/TrialOffset markers: trimmed around the first and last event.';
end
if trim.padding_before_actual_s < trim.padding_s || trim.padding_after_actual_s < trim.padding_s
    qc.warnings{end + 1} = 'The recording starts or ends less than the trim margin away from a trial.';
end
if trim.n_trial_onsets ~= trim.n_trial_offsets
    qc.warnings{end + 1} = sprintf('%d trial onsets but %d trial offsets.', trim.n_trial_onsets, trim.n_trial_offsets);
end
if isempty(motion_present)
    qc.warnings{end + 1} = 'No motion channels: movement checks are not available for this run.';
end
end

function v = get_field(s, name)
v = [];
if isfield(s, name)
    v = s.(name);
end
end

function files = zapline_figures(P)
d = dir(fullfile(P.pre_folder, [P.sub_base '_basic_prepared_zapline*.png']));
files = cellfun(@(n) fullfile(P.pre_folder, n), {d.name}, 'UniformOutput', false);
end
