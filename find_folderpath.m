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
loc.stimuli = fullfile(loc.root,'stimuli','cam-165-select','cropped');
% Specify path to retrieve and save data 
loc.result = fullfile('C:\Users\exp-idgrap\Desktop\xplo-judo-data');

addpath(loc.function);
addpath(loc.stimuli);
addpath(loc.result);
end