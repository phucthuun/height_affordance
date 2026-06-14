%% =========================================================================
%%                       MAIN EXPERIMENT RUNNER SCRIPT
%% =========================================================================

%% ---1 Creating a log file and configuration
log = struct;
[subID, sesID, startRun, taskLabel] = subject_info2(loc, 'h');
 
%% Task setting
log.config.task = task_setting();  
log.config.stim = stim_setting();


%% ---2 List and load stimuli
blocks = stimuli_randomize_preload_double(loc.stimuli.(sprintf('%s', taskLabel)), log.config.task.numBlocks.(sprintf('%s', taskLabel)));


%% --- 3. Initialize Psychtoolbox (PTB-3) ---
log.config.ptb = ptb_setting(log);
w1  = log.config.ptb.w1;
sw  = log.config.ptb.sw;
sh  = log.config.ptb.sh;
ifi = log.config.ptb.ifi;
xc  = log.config.ptb.xc;
yc  = log.config.ptb.yc;

% Positioning Configurations
targetWidth = 400; targetHeight = 225; targetShift = 2;
verticalShift = (sh / targetHeight) * targetShift; 
heightRatio = targetHeight / targetWidth; 
drawW = sw; drawH = sw * heightRatio; 
newBottom = sh - verticalShift; newTop = newBottom - drawH;
posC = [0, newTop, sw, newBottom];

%% --- 4. Lab Streaming Layer (LSL) Synchronization Setup ---
lib = lsl_loadlib();
info = lsl_streaminfo(lib, 'MATLAB_Trigger', 'Markers', 1, 0, 'cf_string', 'mbt_sync_001');
outlet = lsl_outlet(info);

% Display greeting screen instructions
DrawFormattedText(w1, log.config.task.instruction.heightaffordance, 'center', 50, log.config.task.colour.white); 
Screen('Flip', w1);
confirmation_text('Check for LSL Signal and start EEG Recording.\n');

%% --- 5. Main Presentation Block / Run Loop ---
KbName('UnifyKeyNames'); % Ensure absolute cross-platform key mapping compatibility
terminateExperiment = 0; 
log.time.start = datestr(now); 
outlet.push_sample({'ExperimentStart'});  
totalTic = tic;  

% Determine maximum blocks available inside preloaded master array
maxBlocks = length(blocks);

% Loop sequence starts at the run number entered by the experimenter
b = startRun; 

while b <= maxBlocks && ~terminateExperiment
    trials = blocks{b}; 
    numTrials = length(trials);
    abortBlock = 0; % Reset the block abortion flag at the start of every block sequence
    
    % Allocate results data table specifically for this unique run/block execution
    results = table('Size', [numTrials, 8], ...
        'VariableTypes', {'double', 'double', 'string', 'double', 'string', 'double', 'string', 'double'}, ...
        'VariableNames', {'block', 'trial_id', 'fighterID', 'cam', 'posture', 'stance', 'laterality', 'exemplar'});
    
    % Initial active textures generation
    texNeu = Screen('MakeTexture', w1, trials(1).neuData);
    texFgt = Screen('MakeTexture', w1, trials(1).fgtData);
    
    % Clear lookahead safety pointers
    nextTexNeu = []; nextTexFgt = [];
    
    % Display block initialization screen
    DrawFormattedText(w1, sprintf('BLOCK / RUN %d\n\n %s', b, log.config.task.instruction.heightaffordance), 'center', 50, log.config.task.colour.white); 
    Screen('Flip', w1); 
    outlet.push_sample({sprintf('BlockStart%d', b)});
    confirmation_text(sprintf('Start Run %d', b));
    
    for t = 1:numTrials
        % --- Pre-trial passive check for ESC key to invoke the intercept menu ---
        [~, ~, keyCode] = KbCheck;
        if keyCode(log.config.ptb.key.esc)
            intervene = true;
        else
            intervene = false;
        end
        
        % --- INTERVENTION BRANCHING ROUTING MENU ---
        if intervene
            fprintf('\n[INTERCEPTED] Experimenter hit ESC. Presentation paused.\n');
            DrawFormattedText(w1, 'Experiment Paused by Operator.\nIntervention Menu open on operator screen.', 'center', 'center', log.config.task.colour.white);
            Screen('Flip', w1);
            
            ShowCursor;
            interceptChoice = questdlg(...
                sprintf('Run %d | Trial %d interrupted. What would you like to do?', b, t), ...
                'Operator Interrupt Menu', ...
                'Proceed to Next Trial', 'Abort & Go to Next Run', 'Abort & End Experiment', 'Proceed to Next Trial');
            HideCursor;
            
            switch interceptChoice
                case 'Proceed to Next Trial'
                    fprintf('[RESUMED] Continuing block presentation sequence.\n');
                    % Do nothing, script proceeds organically to Phase 0
                    
                case 'Abort & Go to Next Run'
                    abortBlock = 1;
                    break; % Break out of trial loop immediately
                    
                case 'Abort & End Experiment'
                    abortBlock = 1;
                    terminateExperiment = 1;
                    break; % Break out of trial loop immediately
            end
        end
        
        % --- Standard Trial Presentation Sequence ---
        infoStr = sprintf('Run %d | Trial %d/%d | Stance: %s', b, t, numTrials, string(trials(t).stance));
        fprintf('%s \n', infoStr);
        
        % PHASE 0: Calibration
        Screen('TextSize', w1, 700); 
        DrawFormattedText(w1, 'N', 'center', yc + 40*verticalShift, log.config.task.colour.white);
        Screen('TextSize', w1, 30); 
        onset_offload = Screen('Flip', w1);
        outlet.push_sample({sprintf('TrialOnset%d', t)}); 
        
        % PHASE 0.5: Pre-stimulus blank
        onset_preFix = Screen('Flip', w1, onset_offload + log.config.task.time.offload - (ifi/2));
        outlet.push_sample({'NPose'}); 
    
        % PHASE 1: Neutral Stimulus Display
        Screen('DrawTexture', w1, texNeu, [], posC);
        onset_neu = Screen('Flip', w1, onset_preFix + log.config.task.time.fixation - (ifi/2));
        outlet.push_sample({'Neutral'});
      
        % PHASE 2: Fight Stimulus Display
        Screen('DrawTexture', w1, texFgt, [], posC);
        onset_fgt = Screen('Flip', w1, onset_neu + log.config.task.time.neutral - (ifi/2));
        outlet.push_sample({'Fight'}); 
        
        % Asynchronous parallel texture generation for lookahead tracking
        if t < numTrials
            nextTexNeu = Screen('MakeTexture', w1, trials(t+1).neuData);
            nextTexFgt = Screen('MakeTexture', w1, trials(t+1).fgtData);
        end
    
        % Wait loop with continuous Esc observation to open menu at trial end
        while GetSecs < onset_fgt + log.config.task.time.fight
            [~,~,keyCode] = KbCheck;
            if keyCode(log.config.ptb.key.esc); intervene = true; end
        end
        
        % PHASE 3: Inter-Trial Interval (ITI)
        fix_iti_onset = Screen('Flip', w1); 
        outlet.push_sample({sprintf('TrialOffset%d', t)}); 
        
        % Flush graphics memory allocated for the completed trial
        Screen('Close', [texNeu, texFgt]);
        
        % Swap lookahead pipeline pointers
        if t < numTrials
            texNeu = nextTexNeu;
            texFgt = nextTexFgt;
            nextTexNeu = []; nextTexFgt = []; 
        end
        
        % Standard ITI sleep check with escaping fallback tracking
        while GetSecs < fix_iti_onset + log.config.task.time.iti
            [~,~,keyCode] = KbCheck;
            if keyCode(log.config.ptb.key.esc); intervene = true; end
        end
    
        % Log active runtime properties to table structure
        results.block(t)      = b;
        results.trial_id(t)   = t;
        results.fighterID(t)  = trials(t).subID;
        results.cam(t)        = trials(t).cam;
        results.posture(t)    = trials(t).posture;
        results.stance(t)     = trials(t).stance;
        results.laterality(t) = trials(t).laterality;
        results.exemplar(t)   = trials(t).exemplar;
        
        % Catch-all breakout check if escape was triggered deep in presentation phases
        if intervene && t == numTrials
            % Force evaluation on the final loop iteration if ESC was queued
            abortBlock = false; 
        end
    end % End of Individual Trial Loop
    
    % Memory Safeguard: Purge lookahead allocations safely if early breaking occurred
    if ~isempty(nextTexNeu); Screen('Close', nextTexNeu); end
    if ~isempty(nextTexFgt); Screen('Close', nextTexFgt); end
    Screen('Close', [texNeu, texFgt]);

    %% --- 6. Block Cleanup & BIDS Compliant Data Export ---
    if abortBlock
        % Crop missing pre-allocated trial rows before saving partial execution dataset
        results(t:end, :) = []; 
        outlet.push_sample({sprintf('BlockAborted%d', b)});
        fprintf('\n[ABORTED] Run %d cut short by operator at trial %d.\n', b, t);
    else
        outlet.push_sample({sprintf('BlockEnd%d', b)});
    end

    runFilepath = filepath_run(loc, subID, sesID, b, taskLabel);
    
    % Write incremental results directly to data directory pathing
    writetable(results, [runFilepath '_beh.tsv'], 'FileType', 'text', 'Delimiter', '\t');
    save([runFilepath '_beh.mat'], 'log', 'results');
    
    % Construct matching BIDS sidecar metadata validation JSON file
    jsonStruct = struct('block', 'Block/Run sequence number', 'trial_id', 'Trial ID inside run');
    fid = fopen([runFilepath '_beh.json'], 'w');
    if fid ~= -1; fprintf(fid, '%s', jsonencode(jsonStruct)); fclose(fid); end
    fprintf('[SAVED] Run %d tracking saved to: %s\n', b, runFilepath);
    
    % Stop further processing loops completely if 'Abort & End Experiment' was selected
    if terminateExperiment; break; end
    
    %% --- 7. NATURAL END-OF-BLOCK ROUTING (Only hit if block finished normally or via 'Next Run') ---
    ShowCursor;
    
    % High-visibility system notification sent to command console window
    fprintf('\n==================================================\n');
    fprintf('⚠ CRITICAL REMINDER FOR THE EXPERIMENTER ⚠\n');
    fprintf('Make sure to manually STOP and SAVE the other data streams\n');
    fprintf('(Xsens, LabRecorder, loadsol, Neon, camera)\n');
    fprintf('before initiating the next block!\n');
    fprintf('==================================================\n\n');
    
    % Interactive Dialogue UI warning layout
    msgString = sprintf(['Run %d Complete.\n\n' ...
        '⚠ REMINDER: Please STOP and SAVE the other data streams' ...
        '(Xsens, LabRecorder, loadsol, Neon, camera)\n\n' ...
        'What would you like to do next?'], b);
    
    choice = questdlg(msgString, ...
        'Experiment Control Menu & Data Sync Reminder', ...
        'Next Run', 'Save & End Experiment', 'Next Run'); 
    HideCursor;
    
    switch choice
        case 'Next Run'
            b = b + 1; 
            if b <= maxBlocks
                DrawFormattedText(w1, 'Take a break.\n\nExperimenter will start the next run shortly.', 'center', 'center', log.config.task.colour.white);
                Screen('Flip', w1);
            end
        case 'Save & End Experiment'
            fprintf('Experiment ended naturally by experimenter request.\n');
            terminateExperiment = 1;
    end
end 

%% --- 8. Final Session Cleanup & Termination ---
outlet.push_sample({'ExperimentEnd'});
Screen('CloseAll'); 
ShowCursor;
fprintf('\nSession ended safely. Total running time: %.2f seconds.\n', toc(totalTic));