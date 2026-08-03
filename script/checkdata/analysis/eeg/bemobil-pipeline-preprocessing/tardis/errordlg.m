function errordlg(msg, titleStr, varargin)
if nargin < 2 || isempty(titleStr), titleStr = 'Error'; end
fprintf('\n[HPC ERROR - %s]: %s\n\n', titleStr, msg);
end