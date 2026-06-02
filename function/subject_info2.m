function [subID, sesID, startRun, taskLabel] = subject_info2(loc, defaulttask)
    name = 'BIDS Experimental Setup';
    
    prompt = {...
        'Subject ID (e.g., 001):', ...
        'Task ([t] training, [h] height-affordance, [e] estimate):', ...
        'Session ID (default S001):', ...
        'Starting Run Number (default 001):'}; 
    
    defaults = {'', defaulttask, 'S001', '001'};
    answer = inputdlg(prompt, name, 1, defaults); 
    
    if isempty(answer) || isempty(answer{1})
        errordlg('Subject ID is mandatory!'); 
        error('User cancelled or provided no ID.');
    end

    taskInput = answer{2};
    switch taskInput
        case 't',       taskLabel = 'training';
        case 'h',       taskLabel = 'heightaffordance';
        case 'e',       taskLabel = 'estimate';
        otherwise,      taskLabel = lower(regexprep(taskInput, '\W', ''));
    end
    
    subID = answer{1};
    
    sesInput = answer{3};
    if startsWith(sesInput, 'S', 'IgnoreCase', true)
        numPart = sesInput(2:end);
        sesID = sprintf('%03d', str2double(numPart)); % Just the number part, e.g., '001'
    else
        sesID = sprintf('%03d', str2double(sesInput));
    end
    
    startRun = str2double(answer{4}); % Convert to double so we can loop mathematically
    if isnan(startRun); startRun = 1; end
end