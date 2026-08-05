function print(varargin)
% Headless-safe stub for print(). Without a display (-nodisplay, no xvfb),
% print() can crash exporting figures with uicontrols ("Printing of
% uicontrols is not supported on this platform") or hit PaperPosition/
% resolution errors. These calls in bemobil-pipeline only export
% non-essential diagnostic PNGs, so skip the export instead of crashing
% the batch job.
fprintf('\n[HPC INFO] print() call skipped (no display available) -- diagnostic image not exported.\n\n');
end