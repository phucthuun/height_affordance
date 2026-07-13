function experimenter_message(message)
    % Track if the user successfully clicked the OK button
    userClickedOK = false;
    
    while ~userClickedOK
        % Show the cursor so the experimenter can click the button
        ShowCursor; 
        
        % By passing 'OK' as both button choices, questdlg only renders one option.
        % If the user presses ESC or 'X', choice returns empty ('') and loops back.
        choice = questdlg(message, 'Action Required', 'OK', 'OK', 'OK');
        
        if strcmp(choice, 'OK')
            userClickedOK = true; % Break out of the loop safely
        else
            % User tried to exit via ESC or the red X button
            fprintf('User tried to bypass. Re-opening dialog...\n');
        end
    end
    
    % Hide the cursor again so it doesn't stay on the participant screen
    HideCursor; 
end