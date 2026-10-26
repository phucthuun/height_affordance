function s03_judo_qc_summary_and_methods(taskName)
%S03_JUDO_QC_SUMMARY_AND_METHODS  Group QC table and a methods-section draft from all per-run QC files.
%
%   matlab -batch "s03_judo_qc_summary_and_methods('heightaffordance')"
%   matlab -batch "s03_judo_qc_summary_and_methods"           % all tasks
%
%   Reads 8_quality-control/sub-*/sub-*_qc-2a.json and _qc-2c_<mode>.json and writes to
%   8_quality-control/group/:
%     qc_summary.csv     one row per run and mode (numbers behind the methods text)
%     methods_text.md    methods paragraph with the actual settings, versions and group statistics,
%                        plus the list of runs with QC flags and the references
%   Settings and versions are taken from the QC files (what was actually run), not from the current config.
%   Doesn't need EEGLAB; can be run on tardis or locally.

if nargin < 1
    taskName = '';
end
cfg = judo_setup('3', false);
qc_root = fullfile(cfg.study_folder, cfg.qc_folder);
files = dir(fullfile(qc_root, 'sub-*', '*_qc-2a.json'));
if isempty(files)
    error('judo:s03', 'No step 2A QC files found under %s', qc_root);
end

rows = [];
q2a_all = {};
q2c_all = {};
for f = 1:numel(files)
    q2a = judo_json_read(fullfile(files(f).folder, files(f).name));
    if isempty(q2a) || (~isempty(taskName) && ~strcmp(q2a.run.task, taskName))
        continue
    end
    q2a_all{end + 1} = q2a; %#ok<AGROW>
    for m = 1:numel(cfg.amica_modes)
        mode = cfg.amica_modes{m};
        q = judo_json_read(fullfile(files(f).folder, strrep(files(f).name, '_qc-2a.json', ['_qc-2c_' mode '.json'])));
        if ~isempty(q) && strcmp(q.status, 'ok')
            q2c_all{end + 1} = q; %#ok<AGROW>
        end
        row = make_row(cfg, q2a, q, mode);
        if isempty(rows)
            rows = row;
        else
            rows(end + 1) = row; %#ok<AGROW>
        end
    end
end
if isempty(rows)
    error('judo:s03', 'No QC files for task "%s".', taskName);
end

out_folder = fullfile(qc_root, 'group');
if ~exist(out_folder, 'dir')
    mkdir(out_folder);
end
csv_file = fullfile(out_folder, 'qc_summary.csv');
writetable(struct2table(rows(:)), csv_file);
fprintf('[judo] Group QC table: %s (%d rows)\n', csv_file, numel(rows));

md_file = fullfile(out_folder, 'methods_text.md');
txt = methods_text(cfg, rows, q2a_all, q2c_all, taskName);
fid = fopen(md_file, 'w', 'n', 'UTF-8');
fprintf(fid, '%s', txt);
fclose(fid);
fprintf('[judo] Methods text: %s\n', md_file);
end

%% ------------------------------------------------------------------------------------------------------------
function row = make_row(cfg, q2a, q, mode)
row = struct();
row.participant = q2a.run.participant;
row.session = q2a.run.session;
row.task = q2a.run.task;
row.run = q2a.run.run;
row.mode = mode;
row.status = 'not run';
row.srate = NaN;
row.duration_min = NaN;
row.n_trials = NaN;
row.n_interpolated = NaN;
row.pct_interpolated = NaN;
row.zapline_removed = NaN;
if strcmp(q2a.status, 'ok')
    row.srate = q2a.recording.srate;
    row.duration_min = q2a.recording.duration_s / 60;
    row.n_trials = q2a.recording.n_trial_onsets;
    row.n_interpolated = q2a.channels.n_interpolated;
    row.pct_interpolated = 100 * q2a.channels.fraction_interpolated;
    if ~isempty(q2a.zapline.proportion_removed)
        row.zapline_removed = sum(q2a.zapline.proportion_removed);
    end
end
fields_nan = {'manual_pct', 'amica_rejected_pct_training', 'excluded_pct_total', 'amica_cutoff_hz', 'amica_order', ...
    'n_ics', 'samples_per_ic_sq', 'amica_iterations', 'n_Brain', 'n_Muscle', 'n_Eye', 'n_Heart', 'n_LineNoise', ...
    'n_ChannelNoise', 'n_Other', 'rv_median_pct', 'n_motion_flagged', 'final_cutoff_hz', 'final_order'};
for k = 1:numel(fields_nan)
    row.(fields_nan{k}) = NaN;
end
for L = 1:numel(cfg.ic_cleaning_levels)
    row.(['removed_' cfg.ic_cleaning_levels(L).name]) = NaN;
    row.(['varpct_' cfg.ic_cleaning_levels(L).name]) = NaN;
end
level_names = [{'none'}, {cfg.ic_cleaning_levels.name}];
for c = 1:numel(cfg.condition_names)
    cond = cfg.condition_names{c};
    row.(['epochs_used_' cond]) = NaN;
    row.(['epochs_total_' cond]) = NaN;
    for L = 1:numel(level_names)
        row.(['snr_' level_names{L} '_' cond]) = NaN;
    end
end
row.n_warnings = NaN;
row.warnings = '';

if isempty(q)
    return
end
row.status = q.status;
if ~strcmp(q.status, 'ok')
    row.warnings = q.reason;
    return
end
if q.manual.available
    row.manual_pct = q.manual.rejected_percent;
else
    row.manual_pct = 0;
end
row.amica_rejected_pct_training = q.amica.rejected_percent_of_training;
row.excluded_pct_total = q.excluded.total_percent_of_run;
row.amica_cutoff_hz = q.amica.highpass_cutoff_hz;
row.amica_order = q.amica.highpass_order;
row.n_ics = q.amica.n_components;
row.samples_per_ic_sq = q.amica.samples_per_channel_sq;
row.amica_iterations = q.amica.n_iterations;
counts = q.iclabel.counts;
for name = fieldnames(counts)'
    if isfield(row, ['n_' name{1}])
        row.(['n_' name{1}]) = counts.(name{1});
    end
end
row.rv_median_pct = q.dipfit.rv_median_percent;
if q.motion.available
    row.n_motion_flagged = numel(q.motion.flagged);
end
row.final_cutoff_hz = q.final_filter.cutoff_hz;
row.final_order = q.final_filter.order;
levels = q.levels;
for L = 1:numel(levels)
    if isfield(row, ['removed_' levels(L).name])
        row.(['removed_' levels(L).name]) = numel(levels(L).removed);
        row.(['varpct_' levels(L).name]) = levels(L).variance_removed_percent;
    end
end
for c = 1:numel(cfg.condition_names)
    cond = cfg.condition_names{c};
    if isfield(q.erp.by_level.none, cond)
        row.(['epochs_used_' cond]) = q.erp.by_level.none.(cond).n_used;
        row.(['epochs_total_' cond]) = q.erp.by_level.none.(cond).n_events;
    end
    for L = 1:numel(level_names)
        if isfield(q.erp.by_level, level_names{L}) && isfield(q.erp.by_level.(level_names{L}), cond)
            snr = q.erp.by_level.(level_names{L}).(cond).snr_db;
            if ~isempty(snr)
                row.(['snr_' level_names{L} '_' cond]) = snr;
            end
        end
    end
end
w = q.warnings;
if isempty(w)
    w = {};
elseif ischar(w)
    w = {w};
end
row.n_warnings = numel(w);
row.warnings = strjoin(w(:)', ' | ');
end

%% ------------------------------------------------------------------------------------------------------------
function txt = methods_text(cfg, rows, q2a_all, q2c_all, taskName)
ok_2a = q2a_all(cellfun(@(q) strcmp(q.status, 'ok'), q2a_all));
n_runs = numel(ok_2a);
participants = unique(cellfun(@(q) q.run.participant, ok_2a, 'UniformOutput', false));
auto = rows(strcmp({rows.mode}, 'auto') & strcmp({rows.status}, 'ok'));
manual = rows(strcmp({rows.mode}, 'manualauto') & strcmp({rows.status}, 'ok'));

% Versions as recorded in the QC files (what was actually run)
prov = [cellfun(@(q) q.provenance, ok_2a, 'UniformOutput', false), cellfun(@(q) q.provenance, q2c_all, 'UniformOutput', false)];
v = @(f) versions(prov, f);
first = [];
if ~isempty(q2c_all)
    first = q2c_all{1};
end

L = {};
L{end + 1} = '# Methods draft: EEG preprocessing';
L{end + 1} = '';
L{end + 1} = sprintf(['_Generated %s by s03_judo_qc_summary_and_methods from %d run(s) of %d participant(s)%s. ' ...
    'Numbers are mean ± SD (range) across runs. Check them against the QC reports and adapt the wording ' ...
    'before use._'], char(datetime('now', 'Format', 'yyyy-MM-dd')), n_runs, numel(participants), task_note(taskName));
L{end + 1} = '';

% Paragraph 1: software and preprocessing
p = sprintf('EEG data were processed in MATLAB %s with EEGLAB %s (Delorme & Makeig, 2004) and the BeMoBIL pipeline (%s; Klug et al., 2022). ', ...
    v('matlab'), v('eeglab'), v('toolboxes.bemobil'));
p = [p sprintf(['For each run, the EEG stream of the XDF recording was imported; the head-mounted motion sensor channels ' ...
    '(%s) were stored separately and excluded from EEG processing. '], strjoin(motion_channels(ok_2a), ', '))];
p = [p sprintf(['Recordings were trimmed to %g s before the first trial onset and %g s after the last trial offset ' ...
    '(duration after trimming %s min). '], cfg.trim_padding_s, cfg.trim_padding_s, ...
    stat(cellfun(@(q) q.recording.duration_s / 60, ok_2a)))];
p = [p sprintf('Line noise at %s Hz was removed with ZapLine-Plus (%s; Klug & Kloosterman, 2022). ', ...
    num_list_text(cfg.zaplineConfig.noisefreqs), v('toolboxes.zapline_plus'))];
p = [p sprintf(['Bad channels were detected with the clean_rawdata channel criterion (%s; correlation with the ' ...
    'RANSAC reconstruction below %.2f for more than %.0f%% of the recording) as implemented in the BeMoBIL pipeline ' ...
    '(%d detection runs; a channel was rejected if flagged in at least %.0f%% of them, at most %s of the channels)%s, ' ...
    'interpolated with spherical splines (bad channels per run: %s), and the data were re-referenced to the common ' ...
    'average with the recording reference (%s) restored as a channel. '], v('toolboxes.clean_rawdata'), ...
    cfg.chancorr_crit, 100 * cfg.chan_max_broken_time, cfg.chan_detect_num_iter, ...
    100 * cfg.chan_detected_fraction_threshold, rat_text(cfg.num_chan_rej_max_target), iterations_note(ok_2a), ...
    stat(cellfun(@(q) q.channels.n_interpolated, ok_2a)), cfg.ref_channel)];
L{end + 1} = p;
L{end + 1} = '';

% Paragraph 2: ICA
if ~isempty(first)
    a = first.settings.amica;
    p = sprintf(['For independent component analysis, a copy of each run was high-pass filtered (zero-phase ' ...
        'Hamming-windowed sinc FIR; Widmann et al., 2015; passband edge %g Hz, -6 dB cutoff %s Hz, order %s; ' ...
        'Klug & Gramann, 2021; Winkler et al., 2015) and decomposed with AMICA (%s; Palmer et al., 2011; %d model, ' ...
        'at most %d iterations, reduced to the data rank) with %d iterations of AMICA''s sample rejection at %g SD ' ...
        '(Klug et al., 2024). '], a.filter_lowCutoffFreqAMICA, uniq_text([rows_ok(rows).amica_cutoff_hz], '%.2f'), ...
        uniq_text([rows_ok(rows).amica_order], '%d'), v('toolboxes.amica'), a.num_models, a.AMICA_max_iter, ...
        a.AMICA_n_rej, a.AMICA_reject_sigma_threshold);
    p = [p sprintf(['Two decompositions were computed per run. In the first, AMICA was trained on the complete ' ...
        'trimmed run and its sample rejection removed %s%% of the samples. '], stat([auto.amica_rejected_pct_training]))];
    if ~isempty(manual)
        p = [p sprintf(['In the second, segments with artifacts were first marked by visual inspection%s (%s%% of ' ...
            'the data) and removed before training; AMICA''s sample rejection then removed a further %s%% of the ' ...
            'remaining samples. '], blind_note(q2c_all), stat([manual.manual_pct]), ...
            stat([manual.amica_rejected_pct_training]))];
    else
        p = [p '[The decomposition after manual segment rejection has not been run for any run yet.] '];
    end
    p = [p sprintf(['Equivalent dipoles were fitted to each component with DIPFIT (%s; standard BEM head model, ' ...
        'template electrode positions; median residual variance %s%%). The unmixing weights were then applied to ' ...
        'the complete, unfiltered run, and components were classified with ICLabel (%s, "%s" classifier; ' ...
        'Pion-Tonachini et al., 2019), assigning each component its most probable class (%s components per run, ' ...
        'of which %s labelled Brain). '], v('toolboxes.dipfit'), stat([rows_ok(rows).rv_median_pct]), ...
        v('toolboxes.iclabel'), first.settings.iclabel_classifier, stat([rows_ok(rows).n_ics]), ...
        stat([rows_ok(rows).n_Brain]))];
    lev = first.settings.ic_cleaning_levels;
    lev_text = cell(1, numel(lev));
    for k = 1:numel(lev)
        lev_text{k} = sprintf('%s (%s components per run)', lower(lev(k).label), ...
            stat([rows_ok(rows).(['removed_' lev(k).name])]));
    end
    p = [p sprintf('Two cleaned versions of each run were derived: %s. ', strjoin(lev_text, '; and '))];
    p = [p sprintf(['Finally, the data were high-pass filtered (zero-phase Hamming-windowed sinc FIR, passband edge ' ...
        '%g Hz, -6 dB cutoff %s Hz, order %s). ' ...
        'No low-pass filter was applied to the stored data. Segments excluded from ICA training remain in the ' ...
        'continuous data and are marked as events, so that epochs overlapping them can be excluded.'], ...
        first.final_filter.passband_edge_hz, uniq_text([rows_ok(rows).final_cutoff_hz], '%.3f'), ...
        uniq_text([rows_ok(rows).final_order], '%d'))];
    L{end + 1} = p;
else
    L{end + 1} = '[Step 2C (ICA) has not produced results yet.]';
end
L{end + 1} = '';

% Usable epochs
L{end + 1} = '## Usable epochs per condition (after excluding marked segments)';
L{end + 1} = '';
L{end + 1} = '| Condition | auto | manual + auto |';
L{end + 1} = '|---|---|---|';
for c = 1:numel(cfg.condition_names)
    cond = cfg.condition_names{c};
    L{end + 1} = sprintf('| %s | %s | %s |', cond, stat_field(auto, ['epochs_used_' cond]), ...
        stat_field(manual, ['epochs_used_' cond])); %#ok<AGROW>
end
L{end + 1} = '';

% Versions that differ between runs
L{end + 1} = '## Software versions found in the QC files';
L{end + 1} = '';
for f = {'matlab', 'eeglab', 'toolboxes.bemobil', 'toolboxes.amica', 'toolboxes.iclabel', 'toolboxes.zapline_plus', ...
        'toolboxes.clean_rawdata', 'toolboxes.firfilt', 'toolboxes.dipfit', 'pipeline_version', 'code_hash'}
    L{end + 1} = sprintf('- %s: %s', f{1}, v(f{1})); %#ok<AGROW>
end
L{end + 1} = '';

% Runs with flags
L{end + 1} = '## Runs with QC flags';
L{end + 1} = '';
flagged = rows(~cellfun(@isempty, {rows.warnings}));
if isempty(flagged)
    L{end + 1} = 'None.';
else
    for k = 1:numel(flagged)
        L{end + 1} = sprintf('- sub-%s run %s (%s, %s): %s', flagged(k).participant, flagged(k).run, flagged(k).mode, ...
            flagged(k).status, flagged(k).warnings); %#ok<AGROW>
    end
end
L{end + 1} = '';

L{end + 1} = '## References';
L{end + 1} = '';
refs = {
    'Delorme, A., & Makeig, S. (2004). EEGLAB: an open source toolbox for analysis of single-trial EEG dynamics including independent component analysis. Journal of Neuroscience Methods, 134(1), 9-21. https://doi.org/10.1016/j.jneumeth.2003.10.009'
    'Klug, M., & Gramann, K. (2021). Identifying key factors for improving ICA-based decomposition of EEG data in mobile and stationary experiments. European Journal of Neuroscience, 54(12), 8406-8420. https://doi.org/10.1111/ejn.14992'
    'Klug, M., Berg, T., & Gramann, K. (2024). Optimizing EEG ICA decomposition with data cleaning in stationary and mobile experiments. Scientific Reports, 14. https://doi.org/10.1038/s41598-024-64919-3'
    'Klug, M., & Kloosterman, N. A. (2022). Zapline-plus: A Zapline extension for automatic and adaptive removal of frequency-specific noise artifacts in M/EEG. Human Brain Mapping, 43(9), 2743-2758. https://doi.org/10.1002/hbm.25832'
    'Klug, M., Jeung, S., Wunderlich, A., Gehrke, L., Protzak, J., Djebbara, Z., Argubi-Wollesen, A., Wollesen, B., & Gramann, K. (2022). The BeMoBIL Pipeline for automated analyses of multimodal mobile brain and body imaging data. bioRxiv. https://doi.org/10.1101/2022.09.29.510051'
    'Palmer, J. A., Kreutz-Delgado, K., & Makeig, S. (2011). AMICA: An adaptive mixture of independent component analyzers with shared components. Technical report, Swartz Center for Computational Neuroscience, UC San Diego.'
    'Pion-Tonachini, L., Kreutz-Delgado, K., & Makeig, S. (2019). ICLabel: An automated electroencephalographic independent component classifier, dataset, and website. NeuroImage, 198, 181-197. https://doi.org/10.1016/j.neuroimage.2019.05.026'
    'Widmann, A., Schröger, E., & Maess, B. (2015). Digital filter design for electrophysiological data - a practical approach. Journal of Neuroscience Methods, 250, 34-46. https://doi.org/10.1016/j.jneumeth.2014.08.002'
    'Winkler, I., Debener, S., Müller, K.-R., & Tangermann, M. (2015). On the influence of high-pass filtering on ICA-based artifact reduction in EEG-ERP. Proceedings of the 37th Annual International Conference of the IEEE EMBC, 4101-4105. https://doi.org/10.1109/EMBC.2015.7319296'
    };
for k = 1:numel(refs)
    L{end + 1} = ['- ' refs{k}]; %#ok<AGROW>
end
L{end + 1} = '';
L{end + 1} = ['_Check before use: the author lists and DOIs above, and the BeMoBIL pipeline citation (preprint ' ...
    'or its published version)._'];
txt = sprintf('%s\n', L{:});
end

%% ------------------------------------------------------------------------------------------------------------
function r = rows_ok(rows)
r = rows(strcmp({rows.status}, 'ok'));
end

function s = stat(x)
x = x(~isnan(x));
if isempty(x)
    s = 'n/a';
elseif numel(x) == 1 || all(x == x(1))
    s = sprintf('%s', fmt(x(1)));
else
    s = sprintf('%s ± %s (%s-%s)', fmt(mean(x)), fmt(std(x)), fmt(min(x)), fmt(max(x)));
end
end

function s = stat_field(rows, field)
if isempty(rows)
    s = 'n/a';
else
    s = stat([rows.(field)]);
end
end

function s = fmt(x)
if abs(x - round(x)) < 1e-9 && abs(x) < 1e6
    s = sprintf('%d', round(x));
elseif abs(x) >= 10
    s = sprintf('%.1f', x);
else
    s = sprintf('%.2f', x);
end
end

function s = uniq_text(x, f)
x = unique(x(~isnan(x)));
if isempty(x)
    s = 'n/a';
else
    s = strjoin(arrayfun(@(k) sprintf(f, k), x(:)', 'UniformOutput', false), ' / ');
end
end

function s = num_list_text(x)
s = strjoin(arrayfun(@(k) sprintf('%g', k), x(:)', 'UniformOutput', false), ', ');
end

function s = rat_text(x)
if x > 0 && x < 1
    s = sprintf('%.0f%%', 100 * x);
else
    s = sprintf('%d', x);
end
end

function s = task_note(taskName)
s = '';
if ~isempty(taskName)
    s = sprintf(', task "%s"', taskName);
end
end

function c = motion_channels(ok_2a)
c = {};
for k = 1:numel(ok_2a)
    ch = ok_2a{k}.motion.channels;
    if ischar(ch)
        ch = {ch};
    end
    c = union(c, ch(:)');
end
if isempty(c)
    c = {'none found'};
end
end

function s = iterations_note(ok_2a)
s = '';
identical = cellfun(@(q) isfield(q.channels, 'detection_iterations_identical') && ...
    isequal(q.channels.detection_iterations_identical, true), ok_2a);
if ~isempty(identical) && all(identical)
    s = ' [note: all detection runs gave identical results, because clean_rawdata resets its random generator; consider describing this as a single detection run]';
end
end

function s = blind_note(q2c_all)
s = '';
blind = cellfun(@(q) isfield(q.manual, 'available') && q.manual.available && isfield(q.manual, 'blind_to_condition') ...
    && isequal(q.manual.blind_to_condition, true), q2c_all);
used = cellfun(@(q) isfield(q.manual, 'available') && q.manual.available, q2c_all);
if any(used) && all(blind(used))
    s = ' by a rater blind to the condition labels';
end
end

function s = versions(prov, field)
vals = {};
for k = 1:numel(prov)
    x = prov{k};
    parts = strsplit(field, '.');
    for p = 1:numel(parts)
        if isstruct(x) && isfield(x, parts{p})
            x = x.(parts{p});
        else
            x = '';
            break
        end
    end
    if ~isempty(x)
        vals{end + 1} = char(x); %#ok<AGROW>
    end
end
vals = unique(vals);
if isempty(vals)
    s = 'unknown';
elseif numel(vals) == 1
    s = vals{1};
else
    s = ['VERSIONS DIFFER BETWEEN RUNS: ' strjoin(vals, '; ')];
end
end
