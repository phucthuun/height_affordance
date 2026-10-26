function counts = judo_count_conditions(EEG, cfg)
%JUDO_COUNT_CONDITIONS  Number of events per condition (cfg.condition_names, optional trial number suffix).

types = judo_event_types(EEG.event);
counts = struct();
for c = 1:numel(cfg.condition_names)
    name = cfg.condition_names{c};
    if isempty(types)
        counts.(name) = 0;
    else
        counts.(name) = sum(~cellfun(@isempty, regexp(types, ['^' name '\d*$'], 'once')));
    end
end
end
