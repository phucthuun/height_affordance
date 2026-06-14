function [ID, filepath] = subject_info(loc, defaulttask)
    name = 'BIDS Experimental Setup';
    
    % Define the prompts for the user
    prompt = {...
        'Subject ID (e.g., 001):', ...
        'Task ([t] training, [h] height-affordance, [e] estimate):', ...
        'Session ID (default S001):', ...
        'Run Number (default 001):'}; 
    
    % Set default values
    defaults = {'', defaulttask, 'S001', '001'};
    
    % Open dialog box
    answer = inputdlg(prompt, name, 1, defaults); 
    
    % 1. Validation: Ensure Subject ID is not empty
    if isempty(answer) || isempty(answer{1})
        errordlg('Subject ID is mandatory!'); 
        error('User cancelled or provided no ID.');
    end

    % 2. Parse Task Name
    taskInput = answer{2};
    switch taskInput
        case 't',       taskLabel = 'training';
        case 'h',       taskLabel = 'heightaffordance';
        case 'e',       taskLabel = 'estimate';
        otherwise,      taskLabel = lower(regexprep(taskInput, '\W', '')); % Clean custom input
    end

    % 3. Extract and Format IDs
    subID = answer{1};
    
    % Logic for Session ID: Ensure it starts with 'S' and is padded (e.g., S001)
    sesInput = answer{3};
    if startsWith(sesInput, 'S', 'IgnoreCase', true)
        numPart = sesInput(2:end); % Strip the 'S'
        sesID = ['S', sprintf('%03d', str2double(numPart))];
    else
        sesID = ['S', sprintf('%03d', str2double(sesInput))];
    end
    
    % Logic for Run ID: Ensure it is 3 digits (e.g., 001)
    runInput = answer{4};
    runID = sprintf('%03d', str2double(runInput));

    % 4. Construct BIDS filename and path
    % Format: sub-<ID>_ses-<ID>_task-<name>_run-<ID>
    ID = ['sub-' subID];
    filename = sprintf('sub-%s_ses-%s_task-%s_run-%s', subID, sesID, taskLabel, runID);
    
    % BIDS folder structure: project/sub-001/ses-S001/beh/
    destFolder = fullfile(loc.result, ID, ['ses-' sesID], 'beh');
    
    % Create folder if it doesn't exist
    if ~exist(destFolder, 'dir')
        mkdir(destFolder);
    end

    filepath = fullfile(destFolder, filename);

    % 5. Safety check for existing data
    if exist([filepath '.mat'], 'file')
        choice = questdlg(sprintf('File %s already exists. Overwrite?', filename), ...
            'Warning', 'Overwrite', 'Cancel', 'Cancel');
        if strcmp(choice, 'Cancel')
            error('Prevented overwriting existing data.');
        end
    end
    
    fprintf('BIDS path initialized: %s\n', filepath);
end