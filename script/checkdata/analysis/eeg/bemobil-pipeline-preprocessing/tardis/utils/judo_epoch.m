function [EEG_ep, info] = judo_epoch(EEG, type_regex, window_s, bad_types)
%JUDO_EPOCH  Epoch a cleaned run around matching events, leaving out epochs that overlap bad segments.
%
%   [EEG_ep, info] = judo_epoch(EEG, '^NPose\d*$', [-0.2 0.8])
%   [EEG_ep, info] = judo_epoch(EEG, '^(NPose|Neutral|Fight)\d*$', [-0.2 0.8], {'bad_manual'})
%
%   For downstream analyses of the step 2C outputs. bad_types defaults to {'bad_manual', 'bad_amica'}: the
%   segments step 2B and AMICA excluded from ICA training. Pass {} to keep every epoch, or {'bad_manual'}
%   for the manual marks only. Epochs that would run past the data or cross a boundary are also left out
%   (pop_epoch would drop those anyway). info lists what was kept and why the rest was not.

if nargin < 4
    bad_types = {'bad_manual', 'bad_amica'};
end

[~, order] = sort([EEG.event.latency]); % pop_epoch indexes the events in latency order
EEG.event = EEG.event(order);
types = judo_event_types(EEG.event);
lat = [EEG.event.latency];

bad = false(1, EEG.pnts);
dur = zeros(size(lat));
if isfield(EEG.event, 'duration')
    d = {EEG.event.duration};
    d(cellfun(@isempty, d)) = {0};
    dur = cell2mat(d);
end
for i = find(ismember(types, bad_types))
    a = max(1, round(lat(i)));
    b = min(EEG.pnts, round(lat(i) + dur(i) - 1));
    bad(a:b) = true;
end
bound = lat(strcmp(types, 'boundary'));

candidates = find(~cellfun(@isempty, regexp(types, type_regex, 'once')));
off = round(window_s * EEG.srate);
keep = [];
n_bad = 0;
n_edge = 0;
for i = candidates
    s = round(lat(i)) + off(1);
    e = round(lat(i)) + off(2);
    if s < 1 || e > EEG.pnts || any(bound > s & bound < e)
        n_edge = n_edge + 1;
    elseif any(bad(s:e))
        n_bad = n_bad + 1;
    else
        keep(end + 1) = i; %#ok<AGROW>
    end
end
if isempty(keep)
    error('judo:epoch', 'No usable epochs for "%s".', type_regex);
end

EEG_ep = pop_epoch(EEG, {}, window_s, 'eventindices', keep, 'epochinfo', 'yes');
info = struct('type_regex', type_regex, 'window_s', window_s, 'bad_types', {bad_types}, ...
    'n_events', numel(candidates), 'n_kept', numel(keep), 'n_overlap_bad', n_bad, 'n_edge', n_edge, ...
    'kept_event_types', {types(keep)});
fprintf('[judo] %s: %d of %d epochs kept (%d overlap %s, %d at edges/boundaries).\n', type_regex, ...
    numel(keep), numel(candidates), n_bad, strjoin(bad_types, '/'), n_edge);
end
