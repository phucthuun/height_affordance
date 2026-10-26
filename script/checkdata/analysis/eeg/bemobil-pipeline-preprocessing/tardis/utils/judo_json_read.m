function s = judo_json_read(filename)
%JUDO_JSON_READ  Read a JSON file into a struct; returns [] if the file does not exist.

s = [];
if ~exist(filename, 'file')
    return
end
txt = fileread(filename);
if isempty(strtrim(txt))
    return
end
s = jsondecode(txt);
end
