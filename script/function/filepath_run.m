function [runFilepath] = filepath_run(loc, subID, sesID, runID, taskLabel)

% Construct individual run destinations dynamically
currentRunStr = sprintf('%03d', runID);
filename = sprintf('sub-%s_ses-S%s_task-%s_run-%s', subID, sesID, taskLabel, currentRunStr);
destFolder = fullfile(loc.result, ['sub-' subID], ['ses-S' sesID], 'beh');
if ~exist(destFolder, 'dir'); mkdir(destFolder); end
runFilepath = fullfile(destFolder, filename);

end