function types = judo_event_types(event)
%JUDO_EVENT_TYPES  Event types as a cell array of char (numeric and string types converted).

if isempty(event) || ~isfield(event, 'type')
    types = {};
    return
end
types = {event.type};
not_char = ~cellfun(@ischar, types);
types(not_char) = cellfun(@to_char, types(not_char), 'UniformOutput', false);
end

function c = to_char(x)
if isnumeric(x) || islogical(x)
    c = num2str(x);
else
    c = char(x);
end
end
