function [res, curves] = judo_erp_check(EEG, cfg, bad_mask)
%JUDO_ERP_CHECK  Quick per-condition average response and signal-to-noise ratio, as a sanity check.
%
%   [res, curves] = judo_erp_check(EEG, cfg, bad_mask)
%
%   Epochs cfg.erp_window_s around every condition event (cfg.condition_names), subtracts the
%   cfg.erp_baseline_s mean and averages. Epochs are skipped if they run past the data, cross a boundary,
%   or overlap bad_mask (samples rejected manually or by AMICA in this mode; pass [] to use all).
%
%   SNR (dB) = 20*log10( RMS of the average / RMS of the plus-minus average ) over all channels and the
%   post-stimulus window; the plus-minus average (every other epoch sign-flipped) estimates the residual
%   noise in the average (Schimmel, 1967). This is only meant to compare cleaning levels and modes.
%
%   res.(condition)    n_events, n_used, n_overlap_bad, n_edge, snr_db
%   curves.(condition) channel (1 x time), gfp (1 x time); curves.times_s, curves.channel

srate = EEG.srate;
n = EEG.pnts;
if isempty(bad_mask)
    bad_mask = false(1, n);
end
offsets = round(cfg.erp_window_s(1) * srate):round(cfg.erp_window_s(2) * srate);
times = offsets / srate;
is_base = times >= cfg.erp_baseline_s(1) & times <= cfg.erp_baseline_s(2);
is_post = times > 0;

% Plot the first channel of cfg.erp_channels that exists (channel 1 if none does)
labels = {EEG.chanlocs.labels};
ch = 1;
for k = 1:numel(cfg.erp_channels)
    hit = find(strcmpi(labels, cfg.erp_channels{k}), 1);
    if ~isempty(hit)
        ch = hit;
        break
    end
end
plot_label = labels{ch};

types = judo_event_types(EEG.event);
lat = [];
if ~isempty(types)
    lat = [EEG.event.latency];
end
bound = lat(strcmp(types, 'boundary'));

res = struct();
curves = struct('times_s', times, 'channel', plot_label);
for c = 1:numel(cfg.condition_names)
    name = cfg.condition_names{c};
    r = struct('n_events', 0, 'n_used', 0, 'n_overlap_bad', 0, 'n_edge', 0, 'snr_db', NaN);
    cv = struct('channel', nan(1, numel(times)), 'gfp', nan(1, numel(times)));
    if ~isempty(types)
        idx = find(~cellfun(@isempty, regexp(types, ['^' name '\d*$'], 'once')));
        r.n_events = numel(idx);
        epochs = zeros(EEG.nbchan, numel(times), numel(idx));
        k = 0;
        for i = idx
            s = round(lat(i)) + offsets(1);
            e = round(lat(i)) + offsets(end);
            if s < 1 || e > n || any(bound > s & bound < e)
                r.n_edge = r.n_edge + 1;
            elseif any(bad_mask(s:e))
                r.n_overlap_bad = r.n_overlap_bad + 1;
            else
                k = k + 1;
                x = double(EEG.data(:, s:e));
                epochs(:, :, k) = x - mean(x(:, is_base), 2);
            end
        end
        epochs = epochs(:, :, 1:k);
        r.n_used = k;
        if k >= 2
            avg = mean(epochs, 3);
            m = 2 * floor(k / 2);
            signs = reshape((-1) .^ (0:m - 1), 1, 1, m);
            pm = mean(epochs(:, :, 1:m) .* signs, 3);
            r.snr_db = 20 * log10(rms_all(avg(:, is_post)) / rms_all(pm(:, is_post)));
            cv.channel = avg(ch, :);
            cv.gfp = std(avg, 1, 1);
        end
    end
    res.(name) = r;
    curves.(name) = cv;
end
end

function v = rms_all(x)
v = sqrt(mean(x(:) .^ 2));
end
