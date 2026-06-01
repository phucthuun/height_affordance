%% FUNCTION TO GET FOLDER PATH OF THE SCRIPT 

function loc = find_folderpath()
    

% Get the full path of the currently running script
loc.highorder = mfilename('fullpath');
% Extract the folder path
loc.root = fileparts(loc.highorder);
% Extract the project path
loc.folder = string(regexp(loc.highorder, '.*?height_affordance', 'match'));
loc.idgrap = string(regexp(loc.highorder, '.*?private', 'match'));

% Get folder path to functions and configs, stimuli folder
loc.script = fullfile(loc.root,'script');
loc.function = fullfile(loc.root,'function');
loc.stimuli.training = fullfile(loc.root,'stimuli', 'training', 'cam-165','cropped');
loc.stimuli.heightaffordance = fullfile(loc.root,'stimuli', 'heightaffordance', 'cam-165','cropped');
loc.stimuli.estimate = fullfile(loc.root,'stimuli', 'estimate', 'cam-165','cropped2');
% Specify path to retrieve and save data 
loc.result = fullfile('C:\Users\exp-idgrap\Desktop\xplo-judo-data');

addpath(loc.function);
addpath(loc.stimuli.training);
addpath(loc.stimuli.heightaffordance);
addpath(loc.result);
end