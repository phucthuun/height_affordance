function fp = judo_file_fingerprint(set_file)
%JUDO_FILE_FINGERPRINT  Cheap ID of a .set file (and its .fdt): sizes and modification dates.
%   Step 2A uses it to notice that the imported run changed since preprocessed.set was made.

fp = '';
files = {set_file, regexprep(set_file, '\.set$', '.fdt')};
for i = 1:numel(files)
    d = dir(files{i});
    if isempty(d)
        continue
    end
    fp = [fp sprintf('%s:%d:%.6f;', d.name, d.bytes, d.datenum)]; %#ok<AGROW>
end
if isempty(fp)
    error('judo:file_fingerprint', 'File not found: %s', set_file);
end
end
