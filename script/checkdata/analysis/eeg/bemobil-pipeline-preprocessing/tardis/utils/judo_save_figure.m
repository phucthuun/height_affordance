function ok = judo_save_figure(fig, png_file, dpi)
%JUDO_SAVE_FIGURE  Save a figure as PNG in a way that also works on the cluster (no display), then close it.
%   UI controls cannot be printed without a display, so they are deleted first. A failed export only
%   produces a warning: figures are diagnostics, they must never stop the processing.

if nargin < 3
    dpi = 110;
end
ok = false;
try
    folder = fileparts(png_file);
    if ~isempty(folder) && ~exist(folder, 'dir')
        mkdir(folder);
    end
    delete(findall(fig, 'Type', 'uicontrol'));
    set(fig, 'Color', 'w', 'InvertHardcopy', 'off', 'PaperPositionMode', 'auto');
    print(fig, png_file, '-dpng', sprintf('-r%d', dpi));
    ok = true;
catch err
    warning('judo:figure', 'Could not save figure %s: %s', png_file, err.message);
end
try
    close(fig);
catch
end
end
