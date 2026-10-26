function judo_remove_fieldtrip_externals()
%JUDO_REMOVE_FIELDTRIP_EXTERNALS  Remove FieldTrip's replacement copies of MATLAB toolbox functions.
%   DIPFIT puts FieldTrip on the path; its external/signal, external/stats and external/image folders shadow
%   the real MATLAB toolboxes. bemobil removes them in the same way after dipole fitting.

ft_file = which('ft_defaults');
if isempty(ft_file)
    return
end
ft_path = fileparts(ft_file);
for sub = {'signal', 'stats', 'image'}
    folder = fullfile(ft_path, 'external', sub{1});
    if contains([pathsep path pathsep], [pathsep folder pathsep])
        rmpath(folder);
    end
end
end
