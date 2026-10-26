function s02c_judo_bemobil_amica_and_iclabel(participantID, sessionID, taskName, modes)
%S02C_JUDO_BEMOBIL_AMICA_AND_ICLABEL  Step 2C: AMICA, dipole fitting and ICLabel cleaning, in two modes.
%
%   matlab -batch "s02c_judo_bemobil_amica_and_iclabel('155T4T', 'S001', 'heightaffordance')"
%   matlab -batch "s02c_judo_bemobil_amica_and_iclabel('155T4T', 'S001', 'heightaffordance', 'auto')"
%
%   Modes (cfg.amica_modes):
%     auto        AMICA trained on the full preprocessed run; AMICA's own sample rejection only
%     manualauto  AMICA trained after removing the segments marked in step 2B (skipped, with a note in the
%                 QC report, until valid marks exist), plus AMICA's sample rejection
%   Both modes differ only in the training data. In both, the weights are applied to the full, unfiltered
%   preprocessed run; ICLabel ('lite', popularity) classifies the components; each cleaning level in
%   cfg.ic_cleaning_levels removes its classes; the result is high-pass filtered at 0.1 Hz. Segments
%   rejected manually or by AMICA stay in the data, marked as 'bad_manual' / 'bad_amica' events.
%
%   Outputs per run and mode
%     4_spatial-filters/4-1_AMICA/sub-<run>_<mode>/       AMICA.set, dipfitted.set (+ .json), AMICA outfiles
%     5_single-subject-EEG-analysis/sub-<run>_<mode>/     preprocessed_and_ICA.set   weights + ICLabel, unfiltered
%                                                        cleaned_rmEye.set          eye ICs removed, 0.1 Hz HP
%                                                        cleaned_rmEyeMuscle.set    eye + muscle ICs removed, 0.1 Hz HP
%     8_quality-control/sub-<run>/                        qc-2c_<mode>.json, figures, qc-report.html
%
%   AMICA and dipole fitting are reused when dipfitted.json shows the same settings, the same preprocessed
%   data and the same manual marks; ICLabel cleaning, filtering and QC are always redone (they are fast).

cfg = judo_setup('2C');
if nargin < 4 || isempty(modes)
    modes = cfg.amica_modes;
elseif ischar(modes)
    modes = {modes};
end
runIDs = judo_find_runs(cfg, participantID, sessionID, taskName, 'preprocessed');

failures = {};
for r = 1:numel(runIDs)
    P = judo_paths(cfg, participantID, sessionID, taskName, runIDs{r});
    fprintf('\n==== Step 2C, run %d/%d: %s ====\n', r, numel(runIDs), P.bids_base);
    try
        failures = [failures, process_run(cfg, P, modes)]; %#ok<AGROW>
    catch err
        failures{end + 1} = sprintf('%s: %s', P.bids_base, err.message); %#ok<AGROW>
        fprintf(2, '[judo] Run %s FAILED: %s\n', P.bids_base, getReport(err, 'extended', 'hyperlinks', 'off'));
    end
    close all hidden
end

if ~isempty(failures)
    error('judo:s02c', 'Step 2C failed for:\n  %s', strjoin(failures, '\n  '));
end
fprintf('\n[judo] Step 2C done for %s.\n', participantID);
end

%% ------------------------------------------------------------------------------------------------------------
function failures = process_run(cfg, P, modes)
failures = {};
EEG_pre = pop_loadset('filename', P.preprocessed_file, 'filepath', P.pre_folder);
EEG_pre.datfile = ''; % data are in memory; make sure nothing reads the file on disk instead
fp = judo_eeg_fingerprint(EEG_pre);

EEG_motion = [];
if exist(fullfile(P.motion_folder, P.motion_file), 'file')
    EEG_motion = pop_loadset('filename', P.motion_file, 'filepath', P.motion_folder);
end

for m = 1:numel(modes)
    Pm = judo_paths(cfg, P.participant, P.session, P.task, P.run, modes{m});
    fprintf('\n---- Mode %s ----\n', modes{m});
    try
        run_mode(cfg, Pm, modes{m}, EEG_pre, fp, EEG_motion);
    catch err
        failures{end + 1} = sprintf('%s (%s): %s', P.bids_base, modes{m}, err.message); %#ok<AGROW>
        fprintf(2, '[judo] Mode %s FAILED: %s\n', modes{m}, getReport(err, 'extended', 'hyperlinks', 'off'));
        qc = qc_header(cfg, Pm, modes{m});
        qc.status = 'failed';
        qc.reason = err.message;
        judo_json_write(Pm.qc_2c_json, qc);
    end
    close all hidden
end

movement_figure(cfg, P, EEG_pre, EEG_motion);
judo_qc_report(cfg, P);
end

%% ------------------------------------------------------------------------------------------------------------
function qc = run_mode(cfg, P, mode, EEG_pre, fp, EEG_motion)
ALLEEG = [];
CURRENTSET = 0;
n = EEG_pre.pnts;
srate = EEG_pre.srate;
prov = judo_provenance(cfg);
qc = qc_header(cfg, P, mode);
qc.input = struct('preprocessed_file', fullfile(P.pre_folder, P.preprocessed_file), ...
    'preprocessed_fingerprint', fp, 'duration_s', n / srate, 'n_channels', EEG_pre.nbchan, 'srate', srate);

%% Training data for this mode
manual_iv = zeros(0, 2);
qc.manual = struct('available', false);
switch mode
    case 'auto'
        EEG_train = EEG_pre;
    case 'manualauto'
        [manual_iv, qc.manual, reason] = load_manual_marks(P, fp, n, srate);
        if ~isempty(reason)
            qc.status = 'skipped';
            qc.reason = reason;
            judo_json_write(P.qc_2c_json, qc);
            fprintf('[judo] manualauto skipped: %s\n', reason);
            return
        end
        EEG_train = EEG_pre;
        if ~isempty(manual_iv)
            EEG_train = eeg_eegrej(EEG_pre, manual_iv);
        end
    otherwise
        error('judo:s02c', 'Unknown mode "%s".', mode);
end
manual_mask = judo_intervals('to_mask', manual_iv, n);
kept_idx = find(~manual_mask);
if EEG_train.pnts ~= numel(kept_idx)
    error('judo:s02c', 'Training data (%d samples) do not match the kept samples (%d).', EEG_train.pnts, numel(kept_idx));
end

%% AMICA + dipole fitting (reused if up to date)
amica_settings = settings_amica(cfg);
amica_key = judo_hash({jsonencode(amica_settings), fp, double(manual_iv)});
sidecar_path = fullfile(P.amica_folder, P.dipfitted_json);
sidecar = judo_json_read(sidecar_path);
reuse = exist(fullfile(P.amica_folder, P.dipfitted_file), 'file') && ~isempty(sidecar) && ...
    isfield(sidecar, 'amica_key') && strcmp(sidecar.amica_key, amica_key);

if reuse
    fprintf('[judo] AMICA + dipfit are up to date for this mode -> reusing %s\n', P.dipfitted_file);
    EEG_dip = pop_loadset('filename', P.dipfitted_file, 'filepath', P.amica_folder);
    amica_filter = sidecar.amica_filter;
    clear EEG_train
else
    order = cfg.filter_AMICA_highPassOrder;
    if isempty(order)
        order = fir_order(cfg.filter_AMICA_transition_bandwidth, srate);
    end
    EEG_train.datfile = '';
    rng(cfg.random_seed, 'twister');
    [ALLEEG, EEG_filt, CURRENTSET] = bemobil_filter(ALLEEG, EEG_train, CURRENTSET, ...
        cfg.filter_lowCutoffFreqAMICA, cfg.filter_highCutoffFreqAMICA, [], [], order, cfg.filter_AMICA_lowPassOrder);
    clear EEG_train
    amica_filter = EEG_filt.etc.filter.highpass;
    EEG_filt.event = [];   % events are not needed for the decomposition (as in bemobil)
    EEG_filt.urevent = [];

    [ALLEEG, EEG_amica, CURRENTSET] = bemobil_signal_decomposition(ALLEEG, EEG_filt, CURRENTSET, true, ...
        cfg.num_models, cfg.max_threads, EEG_filt.etc.rank, [], P.amica_file, P.amica_folder, ...
        cfg.AMICA_autoreject, cfg.AMICA_n_rej, cfg.AMICA_reject_sigma_threshold, cfg.AMICA_max_iter);
    clear EEG_filt

    [ALLEEG, EEG_dip] = bemobil_dipfit(EEG_amica, ALLEEG, CURRENTSET, cfg.warping_channel_names, ...
        cfg.residualVariance_threshold, cfg.do_remove_outside_head, cfg.number_of_dipoles, ...
        P.dipfitted_file, P.amica_folder);
    clear EEG_amica
    judo_remove_fieldtrip_externals();

    judo_json_write(sidecar_path, struct('step', '2C', 'mode', mode, 'amica_key', amica_key, ...
        'settings', amica_settings, 'preprocessed_fingerprint', fp, 'manual_intervals', manual_iv, ...
        'amica_filter', amica_filter, 'provenance', prov));
end
ALLEEG = []; %#ok<NASGU> free memory
CURRENTSET = 0;

%% AMICA's rejected samples, mapped onto the full run
train_bad = false(1, numel(kept_idx));
if isfield(EEG_dip.etc, 'bad_samples')
    train_bad = logical(EEG_dip.etc.bad_samples(:)');
end
if numel(train_bad) ~= numel(kept_idx)
    error('judo:s02c', 'AMICA sample mask (%d) does not match the training data (%d).', numel(train_bad), numel(kept_idx));
end
amica_mask = false(1, n);
amica_mask(kept_idx(train_bad)) = true;
amica_iv = judo_intervals('from_mask', amica_mask);
excluded_mask = amica_mask | manual_mask;

LL = [];
if isfield(EEG_dip.etc, 'spatial_filter') && isfield(EEG_dip.etc.spatial_filter, 'AMICAmods') && ...
        isfield(EEG_dip.etc.spatial_filter.AMICAmods, 'LL')
    LL = EEG_dip.etc.spatial_filter.AMICAmods.LL(:)';
end
n_iter = find(LL ~= 0, 1, 'last');
if isempty(n_iter)
    n_iter = NaN;
    final_ll = NaN;
else
    final_ll = LL(n_iter);
end
n_ic = size(EEG_dip.icaweights, 1);
n_train = numel(train_bad);
n_used = n_train - sum(train_bad);
qc.amica = struct( ...
    'reused', reuse, ...
    'highpass_passband_hz', amica_filter.passband, ...
    'highpass_cutoff_hz', amica_filter.cutoff, ...
    'highpass_transition_bandwidth_hz', amica_filter.transition_bandwidth, ...
    'highpass_order', amica_filter.order, ...
    'n_models', cfg.num_models, ...
    'max_iter', cfg.AMICA_max_iter, ...
    'n_iterations', n_iter, ...
    'final_log_likelihood', final_ll, ...
    'autoreject', cfg.AMICA_autoreject, ...
    'n_rej', cfg.AMICA_n_rej, ...
    'rej_sigma', cfg.AMICA_reject_sigma_threshold, ...
    'training_samples', n_train, ...
    'training_s', n_train / srate, ...
    'rejected_percent_of_training', 100 * sum(train_bad) / n_train, ...
    'samples_used', n_used, ...
    'n_components', n_ic, ...
    'samples_per_channel_sq', n_used / n_ic ^ 2);
qc.excluded = struct( ...
    'manual_s', sum(manual_mask) / srate, ...
    'manual_percent_of_run', 100 * sum(manual_mask) / n, ...
    'amica_s', sum(amica_mask) / srate, ...
    'amica_percent_of_run', 100 * sum(amica_mask) / n, ...
    'total_percent_of_run', 100 * sum(excluded_mask) / n);
qc.rejection_intervals_s = struct('manual', to_seconds(manual_iv, srate), 'amica', to_seconds(amica_iv, srate));

%% Weights onto the full, unfiltered run; bad segments as events; ICLabel
[~, EEG_ica] = bemobil_copy_spatial_filter(EEG_pre, ALLEEG, CURRENTSET, EEG_dip);
clear EEG_dip
EEG_ica.etc.bad_samples = amica_mask;
EEG_ica.etc.bad_samples_percent = 100 * sum(amica_mask) / n;
EEG_ica.etc.remove_data_intervals = amica_iv;
EEG_ica = judo_add_interval_events(EEG_ica, manual_iv, 'bad_manual');
EEG_ica = judo_add_interval_events(EEG_ica, amica_iv, 'bad_amica');
EEG_ica = iclabel(EEG_ica, cfg.iclabel_classifier);
EEG_ica.setname = [P.mode_base '_preprocessed_and_ICA'];
EEG_ica.etc.judo.step_2c = struct('mode', mode, 'manual_intervals', manual_iv, 'amica_filter', amica_filter, ...
    'provenance', prov);
if ~exist(P.analysis_folder, 'dir')
    mkdir(P.analysis_folder);
end
pop_saveset(EEG_ica, 'filename', P.ica_file, 'filepath', P.analysis_folder);

C = EEG_ica.etc.ic_classification.ICLabel.classifications;
class_names = EEG_ica.etc.ic_classification.ICLabel.classes;
[p_max, popular] = max(C, [], 2);
counts = struct();
for k = 1:numel(class_names)
    counts.(matlab.lang.makeValidName(class_names{k})) = sum(popular == k);
end
qc.iclabel = struct('classifier', cfg.iclabel_classifier, 'threshold', cfg.iclabel_threshold, ...
    'classes', {class_names}, 'popular_class', popular(:)', 'popular_probability', p_max(:)', ...
    'probabilities', C, 'counts', counts);

rv = nan(1, n_ic);
if isfield(EEG_ica, 'dipfit') && isfield(EEG_ica.dipfit, 'model')
    for k = 1:min(n_ic, numel(EEG_ica.dipfit.model))
        if ~isempty(EEG_ica.dipfit.model(k).rv)
            rv(k) = EEG_ica.dipfit.model(k).rv;
        end
    end
end
qc.dipfit = struct('rv', rv, 'rv_median_percent', 100 * median(rv, 'omitnan'), 'n_rv_below_15', sum(rv < 0.15));

qc.motion = judo_motion_ic_correlation(EEG_ica, EEG_motion, cfg);

%% Final high-pass (once), then each cleaning level
[EEG_f, final_filter] = judo_highpass(EEG_ica, cfg.final_filter_lower_edge);
clear EEG_ica
if ~isempty(cfg.final_filter_higher_edge)
    EEG_f = pop_eegfiltnew(EEG_f, 'hicutoff', cfg.final_filter_higher_edge, 'usefftfilt', judo_use_fftfilt(), 'plotfreqz', 0);
    final_filter.lowpass_passband_hz = cfg.final_filter_higher_edge;
end
qc.final_filter = final_filter;

[erp_none, curves_none] = judo_erp_check(EEG_f, cfg, excluded_mask);
curves_all = {curves_none};
curve_labels = {'no ICs removed'};
erp_by_level = struct('none', erp_none);

levels = cfg.ic_cleaning_levels;
level_info = [];
for L = 1:numel(levels)
    [EEG_c, info] = judo_clean_iclabel(EEG_f, levels(L).classes_to_keep, cfg.iclabel_threshold);
    out_file = [P.mode_base '_cleaned_' levels(L).name '.set'];
    EEG_c.setname = [P.mode_base '_cleaned_' levels(L).name];
    EEG_c.etc.judo.cleaning = struct('mode', mode, 'level', levels(L).name, 'label', levels(L).label, ...
        'classes_to_keep', levels(L).classes_to_keep, 'removed_ICs', info.removed, ...
        'final_filter', final_filter, 'provenance', prov);
    pop_saveset(EEG_c, 'filename', out_file, 'filepath', P.analysis_folder);
    judo_json_write(fullfile(P.analysis_folder, strrep(out_file, '.set', '.json')), struct( ...
        'step', '2C', 'mode', mode, 'level', levels(L).name, 'description', levels(L).label, ...
        'classes_to_keep', levels(L).classes_to_keep, 'removed_ICs', info.removed, ...
        'final_filter', final_filter, 'bad_segment_events', {{'bad_manual', 'bad_amica'}}, ...
        'source', fullfile(P.pre_folder, P.preprocessed_file), 'provenance', prov));

    [erp_level, curves_level] = judo_erp_check(EEG_c, cfg, excluded_mask);
    clear EEG_c
    erp_by_level.(levels(L).name) = erp_level;
    curves_all{end + 1} = curves_level; %#ok<AGROW>
    curve_labels{end + 1} = levels(L).label; %#ok<AGROW>

    info.name = levels(L).name;
    info.label = levels(L).label;
    info.output = fullfile(P.analysis_folder, out_file);
    info.motion_flagged_kept = setdiff(qc.motion.flagged, info.removed);
    if isempty(level_info)
        level_info = info;
    else
        level_info(L) = info;
    end
end
qc.levels = level_info;
qc.erp = struct('window_s', cfg.erp_window_s, 'baseline_s', cfg.erp_baseline_s, 'channel', curves_none.channel, ...
    'excludes', 'epochs overlapping bad_manual or bad_amica segments, crossing a boundary, or outside the data', ...
    'by_level', erp_by_level);

%% Figures (EEG_f still has all ICs)
fig = @(name) fullfile(P.qc_folder, [P.mode_base '_' name '.png']);
qc.figures = struct();
if judo_qc_plots('iclabel', fig('iclabel'), cfg, EEG_f, level_info, qc.motion)
    qc.figures.iclabel = fig('iclabel');
end
removed_all = unique([level_info.removed]);
if judo_qc_plots('topos', fig('removed_ics'), cfg, EEG_f, removed_all, ic_titles(removed_all, popular, p_max, class_names))
    qc.figures.removed_ics = fig('removed_ics');
end
flagged_kept = setdiff(qc.motion.flagged, removed_all);
if judo_qc_plots('topos', fig('motion_ics'), cfg, EEG_f, flagged_kept, ic_titles(flagged_kept, popular, p_max, class_names))
    qc.figures.motion_ics = fig('motion_ics');
end
if judo_qc_plots('erp', fig('erp'), cfg, curves_all, curve_labels)
    qc.figures.erp = fig('erp');
end
if judo_qc_plots('amica_ll', fig('amica_ll'), cfg, LL)
    qc.figures.amica_ll = fig('amica_ll');
end
clear EEG_f

qc.warnings = warnings_2c(cfg, qc, level_info, erp_none);
qc.outputs = struct('preprocessed_and_ICA', fullfile(P.analysis_folder, P.ica_file), ...
    'cleaned', {{level_info.output}}, 'amica_folder', P.amica_folder);
judo_json_write(P.qc_2c_json, qc);
fprintf('[judo] QC written to %s\n', P.qc_2c_json);
end

%% ------------------------------------------------------------------------------------------------------------
function [iv, manual, reason] = load_manual_marks(P, fp, n, srate)
iv = zeros(0, 2);
manual = struct('available', false);
reason = '';
marks_path = fullfile(P.pre_folder, P.marks_file);
if ~exist(marks_path, 'file')
    reason = sprintf(['No manual marks yet. Do step 2B for this run and copy %s and %s into %s.'], ...
        P.marks_file, P.marks_json, P.pre_folder);
    return
end
M = load(marks_path);
if ~isfield(M, 'preprocessed_fingerprint')
    reason = 'The marks file comes from the previous pipeline version (no data fingerprint). Redo step 2B for this run.';
    return
end
if ~strcmp(M.preprocessed_fingerprint, fp)
    reason = ['The marks were made on a different version of preprocessed.set (step 2A was rerun with other ' ...
        'settings or input). Redo step 2B for this run.'];
    return
end
iv = judo_intervals('merge', M.reject_segments_latency, n);
count = judo_intervals('count', iv);
manual = struct('available', true, 'rater', M.rater, 'protocol', M.protocol, 'date', M.marks_date, ...
    'blind_to_condition', M.blind, 'display_highpass_hz', M.view_highpass_hz, 'notes', M.notes, ...
    'n_segments', size(iv, 1), 'rejected_s', count / srate, 'rejected_percent', 100 * count / n);
end

function qc = qc_header(cfg, P, mode)
qc = struct();
qc.step = '2C';
qc.mode = mode;
qc.mode_label = mode_label(mode);
qc.status = 'ok';
qc.reason = '';
qc.run = struct('participant', P.participant, 'session', P.session, 'task', P.task, 'run', P.run, ...
    'bids_base', P.bids_base);
qc.provenance = judo_provenance(cfg);
qc.settings = struct('amica', settings_amica(cfg), 'iclabel_classifier', cfg.iclabel_classifier, ...
    'iclabel_threshold', cfg.iclabel_threshold, 'ic_cleaning_levels', cfg.ic_cleaning_levels, ...
    'final_filter_lower_edge', cfg.final_filter_lower_edge, 'final_filter_higher_edge', cfg.final_filter_higher_edge, ...
    'conditions', {cfg.condition_names}, ...
    'erp_window_s', cfg.erp_window_s, 'erp_baseline_s', cfg.erp_baseline_s);
end

function label = mode_label(mode)
switch mode
    case 'auto'
        label = 'AMICA sample rejection only';
    case 'manualauto'
        label = 'manual rejection + AMICA sample rejection';
    otherwise
        label = mode;
end
end

function s = settings_amica(cfg)
% Everything that changes the decomposition. A change here makes step 2C recompute AMICA and dipfit.
fields = {'filter_lowCutoffFreqAMICA', 'filter_AMICA_transition_bandwidth', 'filter_AMICA_highPassOrder', ...
    'filter_highCutoffFreqAMICA', 'filter_AMICA_lowPassOrder', 'num_models', 'AMICA_autoreject', 'AMICA_n_rej', ...
    'AMICA_reject_sigma_threshold', 'AMICA_max_iter', 'warping_channel_names', 'residualVariance_threshold', ...
    'do_remove_outside_head', 'number_of_dipoles', 'random_seed'};
s = struct();
for i = 1:numel(fields)
    s.(fields{i}) = cfg.(fields{i});
end
end

function order = fir_order(transition_bandwidth, srate)
% Hamming-window FIR order for a given transition bandwidth (as pop_eegfiltnew computes it)
order = ceil(3.3 / transition_bandwidth * srate / 2) * 2;
end

function s = to_seconds(iv, srate)
% [first last] sample -> [start end] in seconds of the trimmed run
if isempty(iv)
    s = zeros(0, 2);
else
    s = [(iv(:, 1) - 1) / srate, iv(:, 2) / srate];
end
end

function titles = ic_titles(ics, popular, p_max, class_names)
titles = arrayfun(@(k) sprintf('IC%d %s %.2f', k, class_names{popular(k)}, p_max(k)), ics, 'UniformOutput', false);
end

function w = warnings_2c(cfg, qc, level_info, erp_none)
w = {};
if qc.manual.available && qc.manual.rejected_percent > cfg.qc.max_manual_rejected_percent
    w{end + 1} = sprintf('Manual rejection removed %.0f%% of the run (limit %.0f%%).', ...
        qc.manual.rejected_percent, cfg.qc.max_manual_rejected_percent);
end
if qc.amica.rejected_percent_of_training > cfg.qc.max_amica_rejected_percent
    w{end + 1} = sprintf('AMICA rejected %.0f%% of its training data (limit %.0f%%).', ...
        qc.amica.rejected_percent_of_training, cfg.qc.max_amica_rejected_percent);
end
if qc.amica.samples_per_channel_sq < cfg.qc.min_samples_per_channel_sq
    w{end + 1} = sprintf(['Little data for AMICA: %.0f samples per component squared (rule of thumb >= %d); ' ...
        'consider training on all runs of the session together.'], qc.amica.samples_per_channel_sq, ...
        cfg.qc.min_samples_per_channel_sq);
end
if ~isnan(qc.amica.n_iterations) && qc.amica.n_iterations >= cfg.AMICA_max_iter
    w{end + 1} = sprintf('AMICA stopped at the iteration limit (%d) instead of converging.', cfg.AMICA_max_iter);
end
if qc.iclabel.counts.Brain < cfg.qc.min_brain_ics
    w{end + 1} = sprintf('Only %d ICs labelled Brain (limit %d).', qc.iclabel.counts.Brain, cfg.qc.min_brain_ics);
end
for c = 1:numel(cfg.condition_names)
    name = cfg.condition_names{c};
    r = erp_none.(name);
    if r.n_used < cfg.qc.min_trials_per_condition
        w{end + 1} = sprintf('%s: %d of %d epochs usable after excluding bad segments (limit %d).', ...
            name, r.n_used, r.n_events, cfg.qc.min_trials_per_condition); %#ok<AGROW>
    end
end
if qc.motion.available && ~isempty(level_info)
    kept = level_info(end).motion_flagged_kept;
    if ~isempty(kept)
        w{end + 1} = sprintf('IC(s) %s follow the head-motion sensors but are kept in "%s"; check them in the report.', ...
            strjoin(arrayfun(@num2str, kept, 'UniformOutput', false), ', '), level_info(end).name);
    end
elseif ~qc.motion.available
    w{end + 1} = ['Motion check not available: ' qc.motion.reason];
end
end

%% ------------------------------------------------------------------------------------------------------------
function movement_figure(cfg, P, EEG_pre, EEG_motion)
% One figure per run: head motion over time and the segments each mode excluded.
srate = EEG_pre.srate;
mv = struct();
mv.duration_s = EEG_pre.pnts / srate;
types = judo_event_types(EEG_pre.event);
onsets = [];
if ~isempty(types)
    lat = [EEG_pre.event.latency];
    onsets = (lat(~cellfun(@isempty, regexp(types, cfg.trial_onset_regex, 'once'))) - 1) / srate;
end
mv.trial_onsets_s = onsets;

if ~isempty(EEG_motion) && EEG_motion.srate == srate && abs(EEG_motion.pnts - EEG_pre.pnts) <= 2
    labels = {EEG_motion.chanlocs.labels};
    acc = startsWith(labels, 'Acc');
    if any(acc)
        x = double(EEG_motion.data(acc, :));
        x = x - movmean(x, round(srate), 2); % remove gravity / slow drift
        env = sqrt(movmean(sum(x .^ 2, 1), round(srate)));
        step = max(1, round(srate / 10));
        mv.motion_t_s = (0:step:numel(env) - 1) / srate;
        mv.motion_env = env(1:step:end);
        mv.motion_unit_label = 'acc. (sensor units)';
    end
end

mv.modes = struct('label', {}, 'manual_s', {}, 'amica_s', {}, 'summary', {});
for m = 1:numel(cfg.amica_modes)
    Pm = judo_paths(cfg, P.participant, P.session, P.task, P.run, cfg.amica_modes{m});
    q = judo_json_read(Pm.qc_2c_json);
    entry = struct('label', cfg.amica_modes{m}, 'manual_s', zeros(0, 2), 'amica_s', zeros(0, 2), 'summary', 'not run yet');
    if ~isempty(q)
        if strcmp(q.status, 'ok')
            % JSON stores a single [start end] pair as a flat list, which comes back as a column
            entry.manual_s = reshape(q.rejection_intervals_s.manual, [], 2);
            entry.amica_s = reshape(q.rejection_intervals_s.amica, [], 2);
            entry.summary = sprintf('manual %.1f%%, AMICA %.1f%% of the run', ...
                q.excluded.manual_percent_of_run, q.excluded.amica_percent_of_run);
        else
            entry.summary = [q.status ': ' q.reason];
        end
    end
    mv.modes(end + 1) = entry;
end
judo_qc_plots('movement', fullfile(P.qc_folder, [P.sub_base '_movement.png']), cfg, mv);
end
