function res = judo_motion_ic_correlation(EEG, EEG_motion, cfg)
%JUDO_MOTION_IC_CORRELATION  Flag independent components whose activity follows the head-motion sensors.
%
%   res = judo_motion_ic_correlation(EEG, EEG_motion, cfg)
%
%   EEG is the full preprocessed run with ICA weights, EEG_motion the motion channels saved by step 2A for
%   the same run (same samples). IC activations and the accelerometer/gyroscope channels are band-passed to
%   cfg.qc.motion_band_hz and compared in two ways:
%     max_abs_r   largest |Pearson r| between an IC and any single motion channel
%     envelope_r  Pearson r between 1-s RMS envelopes of the IC and of the head-acceleration magnitude
%   ICs above cfg.qc.motion_corr_threshold or cfg.qc.motion_envelope_corr_threshold are listed in
%   res.flagged. This is a heuristic for review in the QC report; nothing is removed because of it.

res = struct('available', false, 'reason', '', 'channels', {{}}, 'band_hz', cfg.qc.motion_band_hz, ...
    'max_abs_r', [], 'max_abs_r_channel', {{}}, 'envelope_r', [], 'flagged', [], ...
    'threshold_r', cfg.qc.motion_corr_threshold, 'threshold_envelope_r', cfg.qc.motion_envelope_corr_threshold);

if isempty(EEG_motion)
    res.reason = 'No motion channels were saved for this run.';
    return
end
if EEG_motion.srate ~= EEG.srate
    EEG_motion = pop_resample(EEG_motion, EEG.srate);
end
if abs(EEG_motion.pnts - EEG.pnts) > 2
    res.reason = sprintf('Motion data (%d samples) and EEG (%d samples) do not line up.', EEG_motion.pnts, EEG.pnts);
    return
end
labels = {EEG_motion.chanlocs.labels};
use = startsWith(labels, 'Acc') | startsWith(labels, 'Gyro');
if ~any(use)
    res.reason = 'No accelerometer or gyroscope channels found.';
    return
end

n = min(EEG.pnts, EEG_motion.pnts);
mot_labels = labels(use);
W = EEG.icaweights * EEG.icasphere;
n_ic = size(W, 1);

T = eeg_emptyset();
T.data = [W * double(EEG.data(EEG.icachansind, 1:n)); double(EEG_motion.data(use, 1:n))];
T.nbchan = size(T.data, 1);
T.pnts = n;
T.trials = 1;
T.srate = EEG.srate;
T.xmin = 0;
T.xmax = (n - 1) / EEG.srate;
T.event = boundary_events(EEG.event, n);
T = pop_eegfiltnew(T, 'locutoff', cfg.qc.motion_band_hz(1), 'hicutoff', cfg.qc.motion_band_hz(2), ...
    'usefftfilt', judo_use_fftfilt(), 'plotfreqz', 0);

step = max(1, floor(EEG.srate / (4 * cfg.qc.motion_band_hz(2))));
A = T.data(1:n_ic, 1:step:end);
M = T.data(n_ic + 1:end, 1:step:end);
clear T

r = corr_rows(A, M);
[max_abs, idx] = max(abs(r), [], 2);

win = max(1, round(EEG.srate / step)); % 1 s
is_acc = startsWith(mot_labels, 'Acc');
if ~any(is_acc)
    is_acc = true(size(mot_labels));
end
magnitude = sqrt(sum(M(is_acc, :) .^ 2, 1));
env_motion = sqrt(movmean(magnitude .^ 2, win));
env_ic = sqrt(movmean(A .^ 2, win, 2));
env_r = corr_rows(env_ic, env_motion);

res.available = true;
res.channels = mot_labels;
res.max_abs_r = max_abs(:)';
res.max_abs_r_channel = mot_labels(idx);
res.envelope_r = env_r(:)';
res.flagged = find(max_abs(:)' > cfg.qc.motion_corr_threshold | env_r(:)' > cfg.qc.motion_envelope_corr_threshold);
end

function r = corr_rows(A, B)
A = A - mean(A, 2);
B = B - mean(B, 2);
A = A ./ max(sqrt(sum(A .^ 2, 2)), eps);
B = B ./ max(sqrt(sum(B .^ 2, 2)), eps);
r = A * B';
end

function ev = boundary_events(event, n)
ev = struct('type', {}, 'latency', {});
types = judo_event_types(event);
if isempty(types)
    return
end
lat = [event.latency];
for i = find(strcmp(types, 'boundary') & lat > 1.5 & lat < n - 0.5)
    ev(end + 1).type = 'boundary'; %#ok<AGROW>
    ev(end).latency = lat(i);
end
end
