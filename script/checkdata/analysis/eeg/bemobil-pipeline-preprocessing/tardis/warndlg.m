function warndlg(msg, titleStr, varargin)
% Headless-safe replacement for MATLAB's Swing-based warndlg.
% Shadows the real warndlg for any code running from this folder,
% so calls from bemobil-pipeline (or elsewhere) don't crash under -nodisplay.
if nargin < 2 || isempty(titleStr)
    titleStr = 'Warning';
end
fprintf('\n[HPC WARN - %s]: %s\n\n', titleStr, msg);
end