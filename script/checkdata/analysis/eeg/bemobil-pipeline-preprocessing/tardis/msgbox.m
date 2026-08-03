function msgbox(msg, titleStr, varargin)
if nargin < 2 || isempty(titleStr), titleStr = 'Message'; end
fprintf('\n[HPC MSG - %s]: %s\n\n', titleStr, msg);
end