function choice = run_block_break_menu(currentBlock, log)
% RUN_BLOCK_BREAK_MENU Displays a local experimenter UI countdown window
% without affecting the active Psychtoolbox visual presentation display.

    % Show cursor on the experimenter's laptop screen
    ShowCursor;
    
    % High-visibility system notification in the command window
    fprintf('\n==================================================\n');
    fprintf('⚠ CRITICAL REMINDER FOR THE EXPERIMENTER ⚠\n');
    fprintf('Make sure to manually STOP and SAVE the other data streams\n');
    fprintf('1. Eye Tracking  [NEON         - STOP]\n');
    fprintf('2. Motion        [XSENS        - STOP]\n');
    fprintf('3. LSL           [LAB RECORDER - STOP]\n');
    fprintf('4. EEG           [MBT          - STOP]\n');
    fprintf('5. Force         [LOADAPP      - STOP]\n');
    fprintf('6. Video         [Video frames - press q]\n');
    fprintf('==================================================\n\n');
    
    % --- 1. Construct Custom MATLAB Figure Window ---
    countdownDuration = 420; % 7 Minutes in seconds
    endTime = GetSecs + countdownDuration;
    
    % Create a clean, floating UI window on the experimenter's desktop
    f = figure('Name', 'BREAK COUNTDOWN', ...
               'NumberTitle', 'off', ...
               'MenuBar', 'none', ...
               'ToolBar', 'none', ...
               'Position', [500, 400, 550, 300], ...
               'WindowStyle', 'normal', ...
               'Resize', 'off');
           
    % Add the critical reminder text
    uicontrol(f, 'Style', 'text', ...
              'String', sprintf(['BREAK %d \n\n' ...
              'Technician  : STOP EYE TRACING NOW AND TELL EXPERIMENTER'...
              'Experimenter: UNPLUG AND COOL DOWN PHONE!\n' ...
              'Technician  : Save data streams according to command instruction'], currentBlock), ...
              'Position', [20, 160, 510, 100], ...
              'FontSize', 12, ...
              'FontWeight', 'bold', ...
              'HorizontalAlignment', 'center');
          
    % Add the dynamic countdown timer label
    hTimer = uicontrol(f, 'Style', 'text', ...
                       'String', 'Break Time Remaining: 10:00', ...
                       'Position', [20, 100, 510, 40], ...
                       'FontSize', 16, ...
                       'ForegroundColor', [0.8, 0, 0], ...
                       'FontWeight', 'bold', ...
                       'HorizontalAlignment', 'center');
    
    % Define persistent user choices
    userChoice = 'Next Run'; 
    keepCounting = true;
    
    % Callback functions for the interaction buttons
    uicontrol(f, 'Style', 'pushbutton', ...
              'String', 'Bypass Timer (Next Run)', ...
              'Position', [60, 30, 180, 40], ...
              'Callback', @(~,~) setChoiceAndClose('Next Run'));
          
    uicontrol(f, 'Style', 'pushbutton', ...
              'String', 'Save & End Experiment', ...
              'Position', [310, 30, 180, 40], ...
              'Callback', @(~,~) setChoiceAndClose('Save & End Experiment'));
          
    % Nested tracking functions to capture the button click inside the loop
    function setChoiceAndClose(selected)
        userChoice = selected;
        keepCounting = false;
        delete(f);
    end

    % --- 2. Dynamic UI Update Loop ---
    while GetSecs < endTime && keepCounting && ishghandle(f)
        remainingTime = max(0, endTime - GetSecs);
        minutes = floor(remainingTime / 60);
        seconds = floor(mod(remainingTime, 60));
        
        % Update only the timer text string seamlessly inside the UI box
        set(hTimer, 'String', sprintf('Time Remaining: %02d:%02d', minutes, seconds));
        
        drawnow;     % Force MATLAB UI graphics rendering refresh
        WaitSecs(0.1); % Prevent CPU usage spikes
    end
    
    % Clean up window handle if the 10 minutes run out naturally
    if ishghandle(f)
        delete(f);
    end
    
    % Hide cursor back before returning to Psychtoolbox tasks
    HideCursor;
    choice = userChoice;
end