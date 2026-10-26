function EEG = judo_add_interval_events(EEG, intervals, type_name)
%JUDO_ADD_INTERVAL_EVENTS  Add one event per interval [start end] (samples), with a duration in samples.
%   Used to mark segments rejected in step 2B ('bad_manual') and by AMICA ('bad_amica') in the final,
%   continuous outputs, so later epoching can exclude them. Events are sorted by latency afterwards.

if isempty(intervals)
    return
end
if isempty(EEG.event)
    EEG.event = struct('type', {}, 'latency', {}, 'duration', {});
end
if ~isfield(EEG.event, 'duration')
    [EEG.event.duration] = deal(0);
end

fields = fieldnames(EEG.event);
template = cell2struct(cell(numel(fields), 1), fields, 1);
new_events = repmat(template, 1, size(intervals, 1));
for i = 1:size(intervals, 1)
    new_events(i).type     = type_name;
    new_events(i).latency  = intervals(i, 1);
    new_events(i).duration = intervals(i, 2) - intervals(i, 1) + 1;
end

EEG.event = [EEG.event(:)', new_events];
[~, order] = sort([EEG.event.latency]);
EEG.event = EEG.event(order);
EEG = eeg_checkset(EEG, 'eventconsistency');
end
