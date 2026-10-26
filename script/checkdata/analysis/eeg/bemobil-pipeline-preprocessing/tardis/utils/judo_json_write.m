function judo_json_write(filename, s)
%JUDO_JSON_WRITE  Write a struct as pretty-printed UTF-8 JSON, creating the folder if needed.
%   Single-precision numbers are written as double (data loaded in single precision would otherwise
%   produce values some JSON encoders reject).

folder = fileparts(filename);
if ~isempty(folder) && ~exist(folder, 'dir')
    mkdir(folder);
end
txt = jsonencode(sanitize(s), 'PrettyPrint', true);
fid = fopen(filename, 'w', 'n', 'UTF-8');
if fid < 0
    error('judo:json_write', 'Cannot write %s', filename);
end
fprintf(fid, '%s\n', txt);
fclose(fid);
end

function x = sanitize(x)
if isstruct(x)
    for i = 1:numel(x)
        f = fieldnames(x);
        for k = 1:numel(f)
            x(i).(f{k}) = sanitize(x(i).(f{k}));
        end
    end
elseif iscell(x)
    x = cellfun(@sanitize, x, 'UniformOutput', false);
elseif isa(x, 'single')
    x = double(x);
elseif isa(x, 'function_handle')
    x = func2str(x);
end
end
