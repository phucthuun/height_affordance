function report_file = judo_qc_report(cfg, P)
%JUDO_QC_REPORT  Write the per-run HTML QC report from the step 2A / 2B / 2C QC files.
%
%   report_file = judo_qc_report(cfg, judo_paths(cfg, id, ses, task, run))
%
%   Reads 8_quality-control/sub-<run>/*_qc-2a.json, *_qc-2c_<mode>.json and the step 2B marks JSON, and
%   writes 8_quality-control/sub-<run>/sub-<run>_qc-report.html. Figures are embedded, so the HTML file can
%   be copied and opened on its own. Missing steps are shown as "not run yet".

q2a = judo_json_read(P.qc_2a_json);
marks = judo_json_read(fullfile(P.pre_folder, P.marks_json));
modes = cfg.amica_modes;
q2c = cell(1, numel(modes));
for m = 1:numel(modes)
    Pm = judo_paths(cfg, P.participant, P.session, P.task, P.run, modes{m});
    q2c{m} = judo_json_read(Pm.qc_2c_json);
end

h = {};
h{end + 1} = '<!doctype html><html lang="en"><head><meta charset="utf-8">';
h{end + 1} = '<meta name="viewport" content="width=device-width, initial-scale=1">';
h{end + 1} = sprintf('<title>QC %s</title>', esc(P.sub_base));
h{end + 1} = ['<style>' css() '</style></head><body><main>'];
h{end + 1} = sprintf('<h1>EEG quality control <span class="id">%s</span></h1>', esc(P.sub_base));
h{end + 1} = sprintf('<p class="meta">Report generated %s &middot; %s %s</p>', ...
    esc(char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm'))), esc(cfg.pipeline_name), esc(cfg.pipeline_version));

%% Warnings
w = {};
if isempty(q2a)
    w{end + 1} = 'Step 2A has not written a QC file for this run.';
else
    w = [w, prefixed('2A', cellify(getf(q2a, 'warnings', {})))];
    if ~strcmp(getf(q2a, 'status', ''), 'ok')
        w{end + 1} = ['2A: ' getf(q2a, 'error', 'failed')];
    end
end
for m = 1:numel(modes)
    q = q2c{m};
    if isempty(q)
        w{end + 1} = sprintf('2C %s: not run yet.', modes{m}); %#ok<AGROW>
    elseif ~strcmp(q.status, 'ok')
        w{end + 1} = sprintf('2C %s %s: %s', modes{m}, q.status, getf(q, 'reason', '')); %#ok<AGROW>
    else
        w = [w, prefixed(['2C ' modes{m}], cellify(getf(q, 'warnings', {})))]; %#ok<AGROW>
    end
end
h{end + 1} = '<section><h2>Flags for review</h2>';
if isempty(w)
    h{end + 1} = '<p class="ok">No flags. The thresholds are set in s00_judo_bemobil_config.m (bemobil_config.qc).</p>';
else
    h{end + 1} = ['<ul class="warn">' strjoin(cellfun(@(x) ['<li>' esc(x) '</li>'], w, 'UniformOutput', false), '') '</ul>'];
end
h{end + 1} = '</section>';

%% Step 2A
h{end + 1} = '<section><h2>Recording and preprocessing (step 2A)</h2>';
if isempty(q2a) || ~strcmp(getf(q2a, 'status', ''), 'ok')
    h{end + 1} = '<p>Not available.</p>';
else
    rec = q2a.recording;
    rows = {
        'Sampling rate', sprintf('%g Hz', rec.srate)
        'Duration before / after trimming', sprintf('%s / %s', mmss(rec.duration_before_trim_s), mmss(rec.duration_s))
        'Kept', sprintf('%.1f s before the first trial onset to %.1f s after the last trial offset (set: %g s)', ...
            rec.padding_before_actual_s, rec.padding_after_actual_s, rec.trim_padding_s)
        'Trials (onset / offset markers)', sprintf('%d / %d', rec.n_trial_onsets, rec.n_trial_offsets)
        'Condition events', condition_counts(q2a.events, cfg)
        'Motion channels', list_or_none(cellify(getf(q2a, 'motion.channels', {})))
        'Reused existing preprocessed.set', yesno(getf(q2a, 'reused_existing_output', false))
        };
    h{end + 1} = kv_table(rows);

    ch = q2a.channels;
    interp = cellify(getf(ch, 'interpolated', {}));
    rows = {
        'Channels (incl. restored reference)', sprintf('%d (reference %s, re-referenced to average)', ch.n_channels, esc(ch.reference))
        'Interpolated', sprintf('%d (%.1f%%): %s', ch.n_interpolated, 100 * ch.fraction_interpolated, list_or_none(interp))
        'Detection', sprintf('flagged in &ge; %s of %s iterations%s', num(ch.detection_fraction_threshold, '%.2f'), ...
            num(getf(ch, 'detection_iterations', NaN), '%d'), identical_note(getf(ch, 'detection_iterations_identical', [])))
        'Data rank', num(ch.rank, '%d')
        };
    h{end + 1} = '<h3>Channels</h3>';
    h{end + 1} = kv_table(rows);

    z = q2a.zapline;
    h{end + 1} = '<h3>Line noise (ZapLine-Plus)</h3>';
    h{end + 1} = kv_table({
        'Target frequencies', [num_list(getf(z, 'noisefreqs', [])) ' Hz']
        'Noise found', yesno_list(getf(z, 'found_noise', []))
        'Components removed', num_list(getf(z, 'n_components_removed', []))
        'Proportion of power removed', num_list(getf(z, 'proportion_removed', []), '%.4f')
        'Noise ratio before / after', [num_list(getf(z, 'ratio_noise_raw', []), '%.2f') ' / ' num_list(getf(z, 'ratio_noise_clean', []), '%.2f')]
        });
end
h{end + 1} = '</section>';

%% Step 2B
h{end + 1} = '<section><h2>Manual segment rejection (step 2B)</h2>';
if isempty(marks)
    h{end + 1} = '<p>No marks for this run yet.</p>';
else
    h{end + 1} = kv_table({
        'Rater / date', sprintf('%s / %s', esc(marks.rater), esc(getf(marks, 'provenance.date', '')))
        'Protocol version', esc(marks.protocol)
        'Blind to condition labels', yesno(marks.blind_to_condition)
        'Display high-pass', [num(marks.display_highpass_hz, '%g') ' Hz (display only)']
        'Segments', sprintf('%d, %.1f s (%.1f%% of the run)', marks.n_segments, marks.rejected_seconds, marks.rejected_percent)
        'Notes', esc(marks.notes)
        });
end
h{end + 1} = '</section>';

%% Movement and rejected segments
h{end + 1} = '<section><h2>Head motion and excluded segments</h2>';
h{end + 1} = img(fullfile(P.qc_folder, [P.sub_base '_movement.png']), 'Head motion and rejected segments');
h{end + 1} = '</section>';

%% Step 2C comparison
h{end + 1} = '<section><h2>ICA decomposition and cleaning (step 2C)</h2>';
h{end + 1} = comparison_table(cfg, modes, q2c);
h{end + 1} = ['<p class="note">The two modes differ only in the data AMICA is trained on. In both, the weights ' ...
    'are applied to the full run, segments excluded from training stay in the data (events <code>bad_manual</code>, ' ...
    '<code>bad_amica</code>), and the average responses exclude epochs overlapping those segments. SNR compares ' ...
    'the average with its plus-minus average (residual noise); use it to compare levels and modes, not as an absolute measure.</p>'];
for m = 1:numel(modes)
    q = q2c{m};
    if isempty(q) || ~strcmp(q.status, 'ok')
        continue
    end
    h{end + 1} = sprintf('<h3>%s <span class="sub">(%s)</span></h3>', esc(modes{m}), esc(q.mode_label)); %#ok<AGROW>
    figs = getf(q, 'figures', struct());
    for f = {'iclabel', 'removed_ics', 'motion_ics', 'erp', 'amica_ll'}
        if isfield(figs, f{1})
            h{end + 1} = img(figs.(f{1}), f{1}); %#ok<AGROW>
        end
    end
    h{end + 1} = ['<details><summary>Per-component table</summary>' ic_table(q) '</details>']; %#ok<AGROW>
end
h{end + 1} = '</section>';

%% bemobil diagnostics from step 2A
if ~isempty(q2a) && isfield(q2a, 'figures')
    h{end + 1} = '<section><h2>bemobil diagnostic figures (step 2A)</h2>';
    f = q2a.figures;
    for name = {'raw', 'bad_channels', 'bad_channels_detection', 'interpolated_channels'}
        if isfield(f, name{1})
            h{end + 1} = sprintf('<details><summary>%s</summary>%s</details>', esc(strrep(name{1}, '_', ' ')), img(f.(name{1}), name{1})); %#ok<AGROW>
        end
    end
    zfigs = cellify(getf(f, 'zapline', {}));
    for k = 1:numel(zfigs)
        h{end + 1} = sprintf('<details><summary>ZapLine-Plus %d</summary>%s</details>', k, img(zfigs{k}, 'zapline')); %#ok<AGROW>
    end
    h{end + 1} = '</section>';
end

%% Provenance
h{end + 1} = '<section><h2>Provenance</h2>';
prov_rows = {};
if ~isempty(q2a) && isfield(q2a, 'provenance')
    prov_rows(end + 1, :) = {'2A', prov_text(q2a.provenance)};
end
if ~isempty(marks) && isfield(marks, 'provenance')
    prov_rows(end + 1, :) = {'2B', prov_text(marks.provenance)};
end
for m = 1:numel(modes)
    if ~isempty(q2c{m}) && isfield(q2c{m}, 'provenance')
        prov_rows(end + 1, :) = {['2C ' modes{m}], prov_text(q2c{m}.provenance)}; %#ok<AGROW>
    end
end
h{end + 1} = kv_table(prov_rows);
h{end + 1} = '</section></main></body></html>';

report_file = P.qc_report;
if ~exist(P.qc_folder, 'dir')
    mkdir(P.qc_folder);
end
fid = fopen(report_file, 'w', 'n', 'UTF-8');
fprintf(fid, '%s\n', h{:});
fclose(fid);
fprintf('[judo] QC report: %s\n', report_file);
end

%% ============================================================================================================
function t = comparison_table(cfg, modes, q2c)
head = '<tr><th></th>';
for m = 1:numel(modes)
    head = [head sprintf('<th>%s</th>', esc(modes{m}))]; %#ok<AGROW>
end
head = [head '</tr>'];

% Each row: label and a function that turns one mode's QC struct into an HTML cell value
rows = {
    'Status', @(q) status_html(q)
    'Manual rejection', @(q) ifok(q, @() manual_text(q))
    'AMICA training data', @(q) ifok(q, @() sprintf('%.1f min', q.amica.training_s / 60))
    'AMICA high-pass', @(q) ifok(q, @() sprintf('edge %g Hz, cutoff %.2f Hz, order %d', ...
        q.amica.highpass_passband_hz, q.amica.highpass_cutoff_hz, q.amica.highpass_order))
    'AMICA sample rejection', @(q) ifok(q, @() sprintf('%.1f%% of training data (%d x %g SD)', ...
        q.amica.rejected_percent_of_training, q.amica.n_rej, q.amica.rej_sigma))
    'Excluded in total', @(q) ifok(q, @() sprintf('%.1f%% of the run', q.excluded.total_percent_of_run))
    'Components', @(q) ifok(q, @() sprintf('%d; %.0f samples per component&sup2;', ...
        q.amica.n_components, q.amica.samples_per_channel_sq))
    'AMICA iterations', @(q) ifok(q, @() sprintf('%s of %d%s', num(q.amica.n_iterations, '%d'), ...
        q.amica.max_iter, reused_note(q.amica.reused)))
    'ICLabel (popularity)', @(q) ifok(q, @() class_counts(q.iclabel.counts))
    'Dipoles', @(q) ifok(q, @() sprintf('median RV %.1f%%; %d with RV &lt; 15%%', ...
        q.dipfit.rv_median_percent, q.dipfit.n_rv_below_15))
    'Motion-correlated ICs', @(q) ifok(q, @() motion_text(q))
    };
for L = 1:numel(cfg.ic_cleaning_levels)
    lev_name = cfg.ic_cleaning_levels(L).name;
    rows(end + 1, :) = {cfg.ic_cleaning_levels(L).label, @(q) ifok(q, @() level_text(q, lev_name))}; %#ok<AGROW>
end
rows(end + 1, :) = {'Final high-pass', @(q) ifok(q, @() sprintf('edge %g Hz, cutoff %.3f Hz, order %d (%.0f s)', ...
    q.final_filter.passband_edge_hz, q.final_filter.cutoff_hz, q.final_filter.order, q.final_filter.length_s))};
for c = 1:numel(cfg.condition_names)
    cond = cfg.condition_names{c};
    rows(end + 1, :) = {sprintf('%s: epochs used', cond), @(q) ifok(q, @() epochs_text(q, cond))}; %#ok<AGROW>
    rows(end + 1, :) = {sprintf('%s: SNR (dB)', cond), @(q) ifok(q, @() snr_text(q, cond, cfg))}; %#ok<AGROW>
end

body = '';
for r = 1:size(rows, 1)
    cells = '';
    for k = 1:numel(q2c)
        try
            v = rows{r, 2}(q2c{k});
        catch
            v = '&ndash;';
        end
        cells = [cells '<td>' v '</td>']; %#ok<AGROW>
    end
    body = [body sprintf('<tr><th>%s</th>%s</tr>', esc(rows{r, 1}), cells)]; %#ok<AGROW>
end
t = ['<div class="scroll"><table class="cmp">' head body '</table></div>'];
end

function v = ifok(q, fn)
if isempty(q) || ~strcmp(q.status, 'ok')
    v = '&ndash;';
else
    v = fn();
end
end

function v = status_html(q)
if isempty(q)
    v = '<span class="pill grey">not run yet</span>';
elseif strcmp(q.status, 'ok')
    v = '<span class="pill green">ok</span>';
else
    v = sprintf('<span class="pill amber">%s</span> %s', esc(q.status), esc(getf(q, 'reason', '')));
end
end

function v = manual_text(q)
if ~getf(q, 'manual.available', false)
    v = 'none (not used in this mode)';
else
    v = sprintf('%.1f%% (%d segments, rater %s, protocol %s)', q.manual.rejected_percent, q.manual.n_segments, ...
        esc(q.manual.rater), esc(q.manual.protocol));
end
end

function v = class_counts(counts)
names = fieldnames(counts);
parts = cellfun(@(n) sprintf('%s %d', n, counts.(n)), names, 'UniformOutput', false);
v = esc(strjoin(parts', ', '));
end

function v = motion_text(q)
if ~q.motion.available
    v = ['not available: ' esc(q.motion.reason)];
elseif isempty(q.motion.flagged)
    v = 'none';
else
    v = esc(strjoin(arrayfun(@(k) sprintf('IC%d', k), q.motion.flagged(:)', 'UniformOutput', false), ', '));
end
end

function v = level_text(q, name)
lev = [];
L = q.levels;
for k = 1:numel(L)
    if strcmp(L(k).name, name)
        lev = L(k);
    end
end
if isempty(lev)
    v = '&ndash;';
    return
end
removed = lev.removed(:)';
v = sprintf('%d ICs removed (%.1f%% of variance)', numel(removed), lev.variance_removed_percent);
if ~isempty(removed)
    v = [v ': ' esc(strjoin(arrayfun(@(k) sprintf('%d', k), removed, 'UniformOutput', false), ', '))];
end
end

function v = epochs_text(q, name)
r = q.erp.by_level.none.(name);
v = sprintf('%d of %d (%d overlap excluded segments, %d at edges/boundaries)', r.n_used, r.n_events, ...
    r.n_overlap_bad, r.n_edge);
end

function v = snr_text(q, name, cfg)
levels = [{'none'}, {cfg.ic_cleaning_levels.name}];
parts = {};
for k = 1:numel(levels)
    if isfield(q.erp.by_level, levels{k})
        parts{end + 1} = sprintf('%s %s', levels{k}, num(q.erp.by_level.(levels{k}).(name).snr_db, '%.1f')); %#ok<AGROW>
    end
end
v = esc(strjoin(parts, ' | '));
end

function v = reused_note(reused)
v = '';
if reused
    v = ' (reused)';
end
end

function t = ic_table(q)
C = q.iclabel.probabilities;
classes = cellify(q.iclabel.classes);
n_ic = size(C, 1);
popular = q.iclabel.popular_class(:)';
p_max = q.iclabel.popular_probability(:)';
rv = q.dipfit.rv(:)';
L = q.levels;
head = '<tr><th>IC</th><th>Class (p)</th>';
for c = 1:numel(classes)
    head = [head sprintf('<th>%s</th>', esc(classes{c}))]; %#ok<AGROW>
end
head = [head '<th>Dipole RV</th><th>Motion |r| (channel)</th><th>Motion envelope r</th>'];
for k = 1:numel(L)
    head = [head sprintf('<th>Removed in %s</th>', esc(L(k).name))]; %#ok<AGROW>
end
head = [head '</tr>'];
rows = cell(1, n_ic);
for i = 1:n_ic
    r = sprintf('<tr><td>%d</td><td>%s (%.2f)</td>', i, esc(classes{popular(i)}), p_max(i));
    for c = 1:numel(classes)
        r = [r sprintf('<td>%.2f</td>', C(i, c))]; %#ok<AGROW>
    end
    if i <= numel(rv)
        r = [r sprintf('<td>%s</td>', num(100 * rv(i), '%.1f%%'))]; %#ok<AGROW>
    else
        r = [r '<td>&ndash;</td>']; %#ok<AGROW>
    end
    if q.motion.available
        ch = cellify(q.motion.max_abs_r_channel);
        r = [r sprintf('<td>%.2f (%s)</td><td>%.2f</td>', q.motion.max_abs_r(i), esc(ch{i}), q.motion.envelope_r(i))]; %#ok<AGROW>
    else
        r = [r '<td>&ndash;</td><td>&ndash;</td>']; %#ok<AGROW>
    end
    for k = 1:numel(L)
        r = [r '<td>' yesno(any(L(k).removed(:) == i)) '</td>']; %#ok<AGROW>
    end
    rows{i} = [r '</tr>'];
end
t = ['<div class="scroll"><table class="ics">' head strjoin(rows, '') '</table></div>'];
end

%% ------------------------------------------------------------------------------------------------------------
function s = img(file, alt)
if isempty(file) || ~exist(file, 'file')
    s = sprintf('<p class="note">Figure not available (%s).</p>', esc(alt));
    return
end
fid = fopen(file, 'r');
bytes = fread(fid, inf, '*uint8')';
fclose(fid);
s = sprintf('<figure><img alt="%s" src="data:image/png;base64,%s"></figure>', esc(alt), ...
    matlab.net.base64encode(bytes));
end

function t = kv_table(rows)
if isempty(rows)
    t = '<p>&ndash;</p>';
    return
end
body = '';
for r = 1:size(rows, 1)
    body = [body sprintf('<tr><th>%s</th><td>%s</td></tr>', esc(rows{r, 1}), rows{r, 2})]; %#ok<AGROW>
end
t = ['<table class="kv">' body '</table>'];
end

function v = prov_text(p)
tb = getf(p, 'toolboxes', struct());
tb_names = fieldnames(tb);
tb_text = strjoin(cellfun(@(n) sprintf('%s: %s', n, tb.(n)), tb_names', 'UniformOutput', false), '; ');
v = esc(sprintf('%s | MATLAB %s | EEGLAB %s | %s | code %s%s | job %s on %s by %s', getf(p, 'date', ''), ...
    getf(p, 'matlab', ''), getf(p, 'eeglab', ''), tb_text, shorten(getf(p, 'code_hash', ''), 12), ...
    git_note(getf(p, 'git_commit', '')), getf(p, 'slurm_job_id', '-'), getf(p, 'host', ''), getf(p, 'user', '')));
end

function v = git_note(c)
v = '';
if ~isempty(c)
    v = [' (git ' c ')'];
end
end

function s = shorten(s, n)
if numel(s) > n
    s = s(1:n);
end
end

function v = condition_counts(events, cfg)
parts = cell(1, numel(cfg.condition_names));
for c = 1:numel(cfg.condition_names)
    parts{c} = sprintf('%s %d', cfg.condition_names{c}, getf(events, cfg.condition_names{c}, 0));
end
v = esc(strjoin(parts, ', '));
end

function v = identical_note(identical)
v = '';
if isequal(identical, true)
    v = ' (all iterations gave the same result)';
end
end

function v = mmss(seconds)
v = sprintf('%d:%02d min', floor(seconds / 60), floor(mod(seconds, 60)));
end

function v = getf(s, path, default)
% Nested field access with a default, e.g. getf(q, 'motion.channels', {})
v = default;
parts = strsplit(path, '.');
for k = 1:numel(parts)
    if ~isstruct(s) || ~isfield(s, parts{k})
        return
    end
    s = s.(parts{k});
end
if ~isempty(s) || isempty(default)
    v = s;
end
end

function c = cellify(x)
if isempty(x)
    c = {};
elseif iscell(x)
    c = x(:)';
elseif ischar(x)
    c = {x};
else
    c = num2cell(x(:)');
end
end

function c = prefixed(prefix, items)
c = cellfun(@(x) sprintf('%s: %s', prefix, x), items, 'UniformOutput', false);
end

function v = num(x, fmt)
if isempty(x) || (isnumeric(x) && any(isnan(x)))
    v = '&ndash;';
else
    v = sprintf(fmt, x);
end
end

function v = num_list(x, fmt)
if nargin < 2
    fmt = '%g';
end
if isempty(x)
    v = '&ndash;';
else
    v = strjoin(arrayfun(@(k) sprintf(fmt, k), x(:)', 'UniformOutput', false), ', ');
end
end

function v = yesno(x)
if isempty(x)
    v = '&ndash;';
elseif x
    v = 'yes';
else
    v = 'no';
end
end

function v = yesno_list(x)
if isempty(x)
    v = '&ndash;';
else
    v = strjoin(arrayfun(@(k) yesno(k), logical(x(:)'), 'UniformOutput', false), ', ');
end
end

function v = list_or_none(c)
if isempty(c)
    v = 'none';
else
    v = esc(strjoin(c, ', '));
end
end

function s = esc(s)
if isnumeric(s) || islogical(s)
    s = num2str(s);
end
s = char(s);
s = strrep(s, '&', '&amp;');
s = strrep(s, '<', '&lt;');
s = strrep(s, '>', '&gt;');
s = strrep(s, '"', '&quot;');
end

function s = css()
s = [ ...
    ':root{--fg:#1d232b;--muted:#5d6670;--line:#d8dde3;--bg:#ffffff;--panel:#f5f7f9;--warn:#fff4e0;--warnline:#e7a33e;' ...
    '--green:#2f7d32;--amber:#b26a00}' ...
    'body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 -apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif}' ...
    'main{max-width:1180px;margin:0 auto;padding:24px 16px 64px}' ...
    'h1{font-size:24px;margin:0 0 4px}h1 .id{font-weight:400;color:var(--muted)}' ...
    'h2{font-size:19px;margin:32px 0 10px;padding-top:12px;border-top:1px solid var(--line)}' ...
    'h3{font-size:16px;margin:22px 0 8px}h3 .sub{font-weight:400;color:var(--muted)}' ...
    '.meta,.note{color:var(--muted);font-size:13px}.ok{color:var(--green)}' ...
    'ul.warn{background:var(--warn);border-left:4px solid var(--warnline);margin:0;padding:10px 12px 10px 30px}' ...
    'table{border-collapse:collapse;font-size:13.5px;margin:6px 0}' ...
    'th,td{border:1px solid var(--line);padding:4px 8px;text-align:left;vertical-align:top}' ...
    'table.kv th{background:var(--panel);width:270px;font-weight:600}' ...
    'table.cmp th{background:var(--panel);min-width:170px}table.cmp td{min-width:260px}' ...
    'table.ics td,table.ics th{padding:2px 6px;white-space:nowrap}' ...
    '.scroll{overflow-x:auto}' ...
    'figure{margin:10px 0}img{max-width:100%;height:auto;border:1px solid var(--line)}' ...
    'details{margin:6px 0}summary{cursor:pointer;color:#2457a6}' ...
    '.pill{display:inline-block;padding:0 8px;border-radius:10px;font-size:12px;color:#fff}' ...
    '.pill.green{background:var(--green)}.pill.amber{background:var(--amber)}.pill.grey{background:#8a939c}' ...
    'code{background:var(--panel);padding:0 3px}'];
end
