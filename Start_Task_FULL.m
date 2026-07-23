%% 1. Preparations 
sca;            % Close PTB windows
close all;      % Close MATLAB figures
clearvars;      % Clear variables
clc;            % Clear command window

%% Set paths
loc = find_folderpath();

%% Master Sequence Definition
% Column 1: Task Label
% Column 2: Default task flag passed to subject_info2
% Column 3: Script filename to execute
allSteps = {
    'training',         't', 's01_Task_heightaffordance.m'; ...
    'heightaffordance', 'h', 's01_Task_heightaffordance.m'; ...
    'estimate',         'e', 's01_Task_estimate.m'          ...
};

%% Participant language
languageChoice = questdlg('Which language does participant prefer?', ...
    'language', ...
    'Englisch', 'Deutsch','Englisch');

switch languageChoice 
    case 'Englisch'
        languageInput = 'en';
    case 'Deutsch'
        languageInput = 'de';
    otherwise
        fprintf('Initialization cancelled by user.\n');
        return;
end

%% Select Starting Task
startChoice = questdlg('Which task step do you want to start with?', ...
    'Run Experiment', ...
    'Training', 'Height Affordance', 'Estimate', 'Training');

switch startChoice
    case 'Training'
        startIndex = 1;
    case 'Height Affordance'
        startIndex = 2;
    case 'Estimate'
        startIndex = 3;
    otherwise
        fprintf('Initialization cancelled by user.\n');
        return;
end

%% Run Pipeline
for step = startIndex:size(allSteps, 1)
    taskLabel = allSteps{step, 1};
    defaultTaskFlag = allSteps{step, 2};
    scriptName = allSteps{step, 3};
    
    fprintf('\n=========================================\n');
    fprintf(' Starting Task %d/%d: %s\n', step, size(allSteps, 1), upper(taskLabel));
    fprintf('=========================================\n\n');
    
    % Execute the task script
    % (Inside the script, subject_info2 will run using the defaultTaskFlag)
    run(fullfile(loc.script, scriptName));
    
    % If this was the last script, finish sequence
    if step == size(allSteps, 1)
        msgbox('Experiment 3 Sequence Completed Successfully!', 'Experiment Finished');
        break;
    end
    
    % Inter-Script GUI Dialog (Between Training, Height Affordance, and Estimate)
    nextTaskLabel = allSteps{step+1, 1};
    promptMsg = sprintf(['Finished Task: %s\n\n' ...
                         'Next Task in Queue: %s\n\n' ...
                         'What would you like to do next?'], ...
                         upper(taskLabel), upper(nextTaskLabel));
                     
    choice = questdlg(promptMsg, ...
                      sprintf('Completed Phase: %s', upper(taskLabel)), ...
                      'Run Next Script', 'Stop Experiment', 'Run Next Script');
                  
    if ~strcmp(choice, 'Run Next Script')
        fprintf('\nExperiment sequence stopped by operator after %s.\n', taskLabel);
        break;
    end
end