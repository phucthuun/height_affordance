function ok = judo_qc_plots(kind, png_file, cfg, varargin)
%JUDO_QC_PLOTS  QC figures for the per-run report. Every figure is saved as PNG and closed.
%
%   judo_qc_plots('iclabel',  png, cfg, EEG, levels, motion)   class counts and per-IC labels
%   judo_qc_plots('topos',    png, cfg, EEG, ic_list, titles)  scalp maps of the listed ICs
%   judo_qc_plots('erp',      png, cfg, curves_by_level, level_labels)
%   judo_qc_plots('amica_ll', png, cfg, LL)                    AMICA log-likelihood per iteration
%   judo_qc_plots('movement', png, cfg, movement)              head motion and rejected segments over time
%
%   Returns true if the PNG was written.

ok = false;
try
    switch kind
        case 'iclabel'
            fig = plot_iclabel(cfg, varargin{:});
        case 'topos'
            fig = plot_topos(cfg, varargin{:});
        case 'erp'
            fig = plot_erp(cfg, varargin{:});
        case 'amica_ll'
            fig = plot_amica_ll(varargin{:});
        case 'movement'
            fig = plot_movement(cfg, varargin{:});
        otherwise
            error('judo:plots', 'Unknown figure type "%s".', kind);
    end
    if isempty(fig)
        return
    end
    ok = judo_save_figure(fig, png_file, cfg.qc.figure_dpi);
catch err
    warning('judo:plots', 'Figure "%s" failed: %s', kind, err.message);
    close all hidden
end
end

%% ------------------------------------------------------------------------------------------------------------
function colors = class_colors()
colors = [0.20 0.60 0.20;   % Brain
          0.85 0.33 0.10;   % Muscle
          0.00 0.45 0.74;   % Eye
          0.64 0.08 0.18;   % Heart
          0.93 0.69 0.13;   % Line Noise
          0.49 0.18 0.56;   % Channel Noise
          0.55 0.55 0.55];  % Other
end

function fig = new_figure(width, height)
fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [50 50 width height]);
end

%% ------------------------------------------------------------------------------------------------------------
function fig = plot_iclabel(~, EEG, levels, motion)
C = EEG.etc.ic_classification.ICLabel.classifications;
names = EEG.etc.ic_classification.ICLabel.classes;
[p, popular] = max(C, [], 2);
n_ic = size(C, 1);
colors = class_colors();

fig = new_figure(1100, 420);
subplot(1, 3, 1);
counts = accumarray(popular(:), 1, [numel(names) 1])';
hold on
for k = 1:numel(names)
    bar(k, counts(k), 0.8, 'FaceColor', colors(k, :), 'EdgeColor', 'none');
end
hold off
set(gca, 'XTick', 1:numel(names), 'XTickLabel', names, 'Box', 'off');
try
    set(gca, 'XTickLabelRotation', 40);
catch
end
xlim([0.3 numel(names) + 0.7]);
ylabel('Number of ICs');
title(sprintf('ICLabel classes (%d ICs)', n_ic));
for k = 1:numel(names)
    text(k, counts(k), sprintf('%d', counts(k)), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
end

subplot(1, 3, [2 3]);
hold on
for k = 1:numel(names)
    sel = popular == k;
    if any(sel)
        scatter(find(sel), p(sel), 36, colors(k, :), 'filled', 'DisplayName', names{k});
    end
end
marker = {'x', '+'};
for L = 1:numel(levels)
    rm = levels(L).removed;
    if ~isempty(rm)
        plot(rm, p(rm), marker{min(L, 2)}, 'Color', 'k', 'MarkerSize', 9 + 2 * L, 'LineWidth', 1.2, ...
            'DisplayName', ['removed: ' levels(L).name]);
    end
end
if ~isempty(motion) && isfield(motion, 'available') && motion.available && ~isempty(motion.flagged)
    plot(motion.flagged, p(motion.flagged), 'o', 'Color', [0.85 0 0], 'MarkerSize', 13, 'LineWidth', 1.2, ...
        'DisplayName', 'motion-correlated');
end
hold off
xlim([0 n_ic + 1]);
ylim([0 1.05]);
xlabel('Independent component');
ylabel('Probability of its most likely class');
title('Label per IC');
legend('Location', 'eastoutside');
box off
end

%% ------------------------------------------------------------------------------------------------------------
function fig = plot_topos(cfg, EEG, ic_list, titles)
fig = [];
if isempty(ic_list)
    return
end
ic_list = ic_list(1:min(numel(ic_list), cfg.qc.max_topoplots));
n = numel(ic_list);
n_cols = min(7, n);
n_rows = ceil(n / n_cols);
fig = new_figure(150 * n_cols, 165 * n_rows);
chanlocs = EEG.chanlocs(EEG.icachansind);
for k = 1:n
    subplot(n_rows, n_cols, k);
    topoplot(EEG.icawinv(:, ic_list(k)), chanlocs, 'electrodes', 'off');
    title(titles{k}, 'FontSize', 8, 'Interpreter', 'none');
end
end

%% ------------------------------------------------------------------------------------------------------------
function fig = plot_erp(cfg, curves_by_level, level_labels)
conds = cfg.condition_names;
n_c = numel(conds);
fig = new_figure(330 * n_c, 520);
line_colors = [0.55 0.55 0.55; 0.00 0.45 0.74; 0.85 0.33 0.10; 0.47 0.67 0.19; 0.49 0.18 0.56];
t = curves_by_level{1}.times_s * 1000;
for c = 1:n_c
    for row = 1:2
        subplot(2, n_c, (row - 1) * n_c + c);
        hold on
        for L = 1:numel(curves_by_level)
            cv = curves_by_level{L}.(conds{c});
            if row == 1
                y = cv.channel;
            else
                y = cv.gfp;
            end
            plot(t, y, 'Color', line_colors(min(L, size(line_colors, 1)), :), 'LineWidth', 1.2, ...
                'DisplayName', level_labels{L});
        end
        hold off
        xline_compat(0);
        xlim([t(1) t(end)]);
        box off
        if row == 1
            title(sprintf('%s: %s', conds{c}, curves_by_level{1}.channel), 'Interpreter', 'none');
            ylabel('\muV');
        else
            title(sprintf('%s: global field power', conds{c}), 'Interpreter', 'none');
            ylabel('\muV');
            xlabel('Time (ms)');
        end
        if c == n_c && row == 1
            legend('Location', 'best');
        end
    end
end
end

function xline_compat(x)
yl = ylim;
line([x x], yl, 'Color', [0.3 0.3 0.3], 'LineStyle', ':', 'HandleVisibility', 'off');
end

%% ------------------------------------------------------------------------------------------------------------
function fig = plot_amica_ll(LL)
fig = [];
LL = LL(:)';
last = find(LL ~= 0, 1, 'last');
if isempty(last)
    return
end
fig = new_figure(600, 300);
plot(1:last, LL(1:last), 'k', 'LineWidth', 1.2);
xlabel('Iteration');
ylabel('Log-likelihood');
title(sprintf('AMICA convergence (%d iterations)', last));
box off
end

%% ------------------------------------------------------------------------------------------------------------
function fig = plot_movement(~, mv)
% mv.duration_s, mv.trial_onsets_s, mv.motion_t_s / mv.motion_env (optional),
% mv.modes(k).label, .manual_s (N x 2 seconds), .amica_s (N x 2 seconds)
n_modes = numel(mv.modes);
has_motion = isfield(mv, 'motion_env') && ~isempty(mv.motion_env);
n_rows = n_modes + has_motion;
fig = new_figure(1200, 140 + 120 * n_rows);
row = 0;
if has_motion
    row = row + 1;
    subplot(n_rows, 1, row);
    plot(mv.motion_t_s, mv.motion_env, 'k', 'LineWidth', 0.8);
    hold on
    yl = ylim;
    for t0 = mv.trial_onsets_s(:)'
        line([t0 t0], yl, 'Color', [0.2 0.6 0.2], 'LineWidth', 0.5);
    end
    hold off
    xlim([0 mv.duration_s]);
    ylabel(mv.motion_unit_label, 'Interpreter', 'none');
    title('Head motion: 1-s RMS of acceleration (gravity and drift removed); trial onsets in green');
    box off
end
for k = 1:n_modes
    row = row + 1;
    subplot(n_rows, 1, row);
    hold on
    draw_intervals(mv.modes(k).manual_s, 1.5, [0.93 0.55 0.13]);
    draw_intervals(mv.modes(k).amica_s, 0.5, [0.35 0.35 0.35]);
    for t0 = mv.trial_onsets_s(:)'
        line([t0 t0], [0 2], 'Color', [0.2 0.6 0.2], 'LineWidth', 0.5);
    end
    hold off
    xlim([0 mv.duration_s]);
    ylim([0 2]);
    set(gca, 'YTick', [0.5 1.5], 'YTickLabel', {'AMICA', 'manual'});
    title(sprintf('%s: rejected segments (%s)', mv.modes(k).label, mv.modes(k).summary), 'Interpreter', 'none');
    box off
    if row == n_rows
        xlabel('Time in the trimmed run (s)');
    end
end
end

function draw_intervals(iv, y_center, color)
if isempty(iv)
    return
end
for i = 1:size(iv, 1)
    patch([iv(i, 1) iv(i, 2) iv(i, 2) iv(i, 1)], y_center + [-0.4 -0.4 0.4 0.4], color, 'EdgeColor', 'none');
end
end
