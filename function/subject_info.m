function [ID, filepath] = subject_info(loc)
    name = 'BIDS Experimental Setup';
    
    % Define the prompts for the user
    prompt = {...
        'Subject ID (e.g., 001):', ...
        'Task ([1] calibration, [2] training, [3] height-affordance, or custom):', ...
        'Session ID (default 01):', ...
        'Run Number (default 01):'}; 
    
    % Set default values
    defaults = {'', '3', '01', '01'};
    
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
        case '1', taskLabel = 'calibration';
        case '2', taskLabel = 'training';
        case '3', taskLabel = 'heightaffordance';
        otherwise, taskLabel = lower(regexprep(taskInput, '\W', '')); % Clean custom input
    end

    % 3. Extract IDs
    subID = answer{1};
    sesID = answer{3};
    runID = answer{4};

    % 4. Construct BIDS filename and path
    % Format: sub-<ID>_ses-<ID>_task-<name>_run-<ID>
    ID = ['sub-' subID];
    filename = sprintf('sub-%s_ses-%s_task-%s_run-%s', subID, sesID, taskLabel, runID);
    
    % BIDS folder structure: project/sub-001/ses-01/beh/
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