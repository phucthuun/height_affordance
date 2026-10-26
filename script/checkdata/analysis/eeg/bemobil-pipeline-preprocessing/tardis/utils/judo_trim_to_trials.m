function [EEG, info] = judo_trim_to_trials(EEG, cfg)
%JUDO_TRIM_TO_TRIALS  Keep the data from cfg.trim_padding_s before the first trial onset to
%   cfg.trim_padding_s after the last trial offset, and remove everything outside.
%
%   Trial onsets/offsets are events matching cfg.trial_onset_regex / cfg.trial_offset_regex. If a run has
%   neither, the first and last non-boundary events are used instead and info.used_fallback is true.
%   All times in info are in seconds of the original (untrimmed) recording.

types = judo_event_types(EEG.event);
if isempty(types)
    error('judo:trim', 'The dataset has no events; cannot trim to the trials.');
end
lat = [EEG.event.latency];
is_on  = ~cellfun(@isempty, regexp(types, cfg.trial_onset_regex, 'once'));
is_off = ~cellfun(@isempty, regexp(types, cfg.trial_offset_regex, 'once'));

info = struct();
info.padding_s         = cfg.trim_padding_s;
info.n_trial_onsets    = sum(is_on);
info.n_trial_offsets   = sum(is_off);
info.duration_before_s = EEG.pnts / EEG.srate;
info.used_fallback     = ~any(is_on) || ~any(is_off);

if info.used_fallback
    usable = ~strcmp(types, 'boundary');
    if ~any(usable)
        error('judo:trim', 'No trial markers and no other events found; cannot trim.');
    end
    warning('judo:trim', 'No %s / %s events found; trimming around the first and last event instead.', ...
        cfg.trial_onset_regex, cfg.trial_offset_regex);
    first_lat = min(lat(usable));
    last_lat  = max(lat(usable));
else
    first_lat = min(lat(is_on));
    last_lat  = max(lat(is_off));
end

pad = round(cfg.trim_padding_s * EEG.srate);
first_keep = max(1, floor(first_lat) - pad);
last_keep  = min(EEG.pnts, ceil(last_lat) + pad);

regions = zeros(0, 2);
if first_keep > 1
    regions(end + 1, :) = [1, first_keep - 1];
end
if last_keep < EEG.pnts
    regions(end + 1, :) = [last_keep + 1, EEG.pnts];
end

info.first_trial_onset_s     = (first_lat - 1) / EEG.srate;
info.last_trial_offset_s     = (last_lat - 1) / EEG.srate;
info.kept_from_s             = (first_keep - 1) / EEG.srate;
info.kept_to_s               = (last_keep - 1) / EEG.srate;
info.removed_start_s         = (first_keep - 1) / EEG.srate;
info.removed_end_s           = (EEG.pnts - last_keep) / EEG.srate;
info.padding_before_actual_s = (floor(first_lat) - first_keep) / EEG.srate; % shorter if the recording started late
info.padding_after_actual_s  = (last_keep - ceil(last_lat)) / EEG.srate;

if ~isempty(regions)
    EEG = eeg_eegrej(EEG, regions);
end
info.duration_after_s = EEG.pnts / EEG.srate;
end
