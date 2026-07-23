function [taskLabel, languageInput] = subject_info(loc)
    name = 'Choosing Task';
    
    % Define the prompts for the user
    prompt = {...
        'Task ([t] training, [h] height-affordance, [e] estimate, [test] test, [Or type custom]):',...
        'Language ([en] english, [de] deutsch)'
        }; 
    
    % Set default values
    defaults = {'','en'};
    
    % Open dialog box
    answer = inputdlg(prompt, name, 1, defaults); 
    
    % 1. Parse Task Name
    taskInput = answer{1};
    switch taskInput
        case 't',       taskLabel = 'training';
        case 'h',       taskLabel = 'heightaffordance';
        case 'e',       taskLabel = 'estimate';
        case 'test',    taskLabel = 'test';
        otherwise, taskLabel = lower(regexprep(taskInput, '\W', '')); % Clean custom input
    end

    % 2. Languae
    languageInput = answer{2};
end