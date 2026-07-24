%% ---1 Creating a log file and configuration
log = struct;
[subID, sesID, startRun, taskLabel, PHONE_IP] = subject_info2(loc, taskLabel(1));

if taskLabel(1) == "training" % if training, then always run the first block of training
    startRun = 1;
end

% Task setting
log.config.task = task_setting();  
log.config.stim = stim_setting();


%% --- 2. Initialize Psychtoolbox (PTB-3) ---
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
DrawFormattedText(w1, sprintf('WELCOME TO XPLO-Judo\n %s', log.config.task.instruction.(sprintf('%s', languageInput)).(sprintf('%s', taskLabel))), 'center', 'center', log.config.task.colour.white); 
    Screen('Flip', w1); 

% %% --- 3 List and load stimuli
% blocks = stimuli_randomize_preload_double32(loc.stimuli.(sprintf('%s', taskLabel)), log.config.task.numBlocks.(sprintf('%s', taskLabel)));

%% --- 4. Lab Streaming Layer (LSL) Synchronization Setup ---
lib = lsl_loadlib();
info = lsl_streaminfo(lib, 'MATLAB_Trigger', 'Markers', 1, 0, 'cf_string', 'mbt_sync_001');
outlet = lsl_outlet(info);

%% --- 5. Main Presentation Block ---
KbName('UnifyKeyNames'); % Ensure absolute cross-platform key mapping compatibility
terminateExperiment = 0; 
log.time.start = datestr(now); 
outlet.push_sample({'ExperimentStart'}); 
totalTic = tic;  

% Determine maximum blocks available inside preloaded master array
maxBlocks = length(blocks.(sprintf('%s', taskLabel)));

% Loop sequence starts at the run number entered by the experimenter
b = startRun; 

while b <= maxBlocks && ~terminateExperiment

    experimenter_message(sprintf('RUN %d', b));
    
    %% --- 5a - SENSORS PREPARATION
    experimenter_message({'XPLO-Judo App: Input', '', ...
        sprintf('1. Participant ID: %s', subID),...
        sprintf('2. Task: %s', taskLabel),...
        sprintf('3. Run: 00%d', b),...
        '>>> click [Initialize BIDS Structure]'});

    % Video
    experimenter_message({'Video', '', ...
        '1. Run  : Python Script', ...
        sprintf('2. Input: Participant ID (%s), Task (%s), Session (%s), Run (00%d)', subID, taskLabel, sesID, b),...
        '3. Check: video streams: SideView + UpperView'});
    
    % EEG check
    DrawFormattedText(w1, log.config.task.instruction.check_eeg, 'center', 'center', log.config.task.colour.white); 
    Screen('Flip', w1);
    experimenter_message({'EEG', '', ...
        '1. Gel  : tell experimenter about bad channels (if any)', ...
        '2. Start: mbtStreamer STREAMS '});

    % Xsens calibration
    DrawFormattedText(w1, log.config.task.instruction.check_motion, 'center', 'center', log.config.task.colour.white); 
    Screen('Flip', w1);
    experimenter_message({'XSENS', '', ...
        '0. Open     : MVN and streaming_protocol', ...
        '0. Measure  : measure participant body and save config (if not done)','',...
        'Communicate with participant and experimenter what we will do:',...
        '1. Naming   : choose correct folder and file name ', ...
        '2. Calibrate: inform participant to N-Pose and Walk', ...
        '3. Check    : Calibration quality GOOD ',...
        '            (if not GOOD  : calibrate max. 2 more times to achieve GOOD)',...
        '            (from 3rd time: calibrate until at least ACCEPTABLE)'});
    
    % Loadsol calibration and recording
    DrawFormattedText(w1, log.config.task.instruction.check_force, 'center', 'center', log.config.task.colour.white); 
    Screen('Flip', w1);
    experimenter_message({'LOADSOL', '', ...
        '(if not done)',...
        '0. Go turn on bluetooth of loadsync behind the PC', ...
        '0. Add      : [Settings] User Profile >> enter Body weight and Body height','',...
        '1. Connect  : [Measurement] Manage sensors: detect 2 loadsols and 1 loadsync', ...
        '2. Zero     : [Measurement] Measurement >> Live chart; ask participant: We will calibrate the shoes now, please lift each foot as I say; zero each foot as loadapp instructs', ...
        '3. Start    : loadapp starts recording'});

    % Eye-tracking connection
    DrawFormattedText(w1, log.config.task.instruction.check_eye, 'center', 'center', log.config.task.colour.white); 
    Screen('Flip', w1);
    experimenter_message({'Eye-Tracking', '', ...
        '1. Wear  : Experimenter brings phone back to participant', ...
        '2. Check : fixation is at the right position'});

    % Recording
    DrawFormattedText(w1, log.config.task.instruction.eyetracking, 'center', 'center', log.config.task.colour.white); 
    Screen('Flip', w1);
    experimenter_message({'LabRecorder', '', ...
        '1. Update: CHECK THAT ALL STREAMS ARE VISIBLE', ...
        sprintf('2. Enter : Task [%s], Run [00%d], Participant[%s]', taskLabel, b, subID), ...
        '3. Start : Lab Recorder starts recording'});

    experimenter_message({'XSENS', '', ...
        '1. Record: MVN starts recording', ...
        '2. Check : loadapp shows frequently distributed BLACK PINS'});

    experimenter_message({'Eye-Tracking', '', ...
        '1. Record: Neon Monitor starts recording'});

    experimenter_message({'Communicate:',...
        'ARE YOU READY FOR EYE-TRACKING CALIBRATION?',...
        '(you = technician AND participant)'});


    %% --- 5b - EYE TRACKING CALIBRATION
    abortBlock = 0; % Reset the block abortion flag at the start of every block sequence
    calibrationComplete = false;
        
    while ~calibrationComplete
        try
            fprintf('[NEON CALIBRATION] Starting calibration for Run %d...\n', b);
            calibration_eyetracking(w1, sw, sh, ifi, log, PHONE_IP);
            fprintf('[NEON CALIBRATION] Sequence finished.\n');
            
            % Bring up the cursor to interact with the dialog box
            ShowCursor;
            calibChoice = questdlg(...
                sprintf('Run %d | Eye Tracking Calibration Finished.', b), ...
                'Calibration Quality Check', ...
                sprintf('Start Task - RUN %d', b), 'Redo Calibration', 'Continue to Trials');
            HideCursor;
            
            switch calibChoice
                case sprintf('Start Task - RUN %d', b)
                    calibrationComplete = true;
                    fprintf('[NEON CALIBRATION] Confirmed. Proceeding to trials.\n');
                    
                case 'Redo Calibration'
                    fprintf('[NEON CALIBRATION] Restarting calibration...\n');
                    % Loop continues naturally, rerunning calibration
            end
            
        catch ME
            if strcmp(ME.identifier, 'EyeTracker:EscapePressed')
                fprintf('\n[CALIBRATION INTERRUPTED] Technician pressed ESC during calibration.\n');
                ShowCursor;
                escChoice = questdlg(...
                    'Calibration interrupted via ESC. What would you like to do?', ...
                    'Calibration Interrupt Menu', ...
                    'Retry Calibration', sprintf('Skip Calibration & Start RUN %d', b), 'Abort Block', 'Retry Calibration');
                HideCursor;
                
                switch escChoice
                    case 'Retry Calibration'
                        % Do nothing, let the loop repeat
                    case sprintf('Skip Calibration & Start RUN %d', b)
                        calibrationComplete = true; 
                    case 'Abort Block'
                        abortBlock = 1;
                        break; % Break out of the calibration while-loop immediately
                end
            else
                rethrow(ME);
            end
        end
    end
    
    % Early exit safety checkpoint if the block was completely aborted during calibration
    if abortBlock
        if ~isempty(nextTexNeu); Screen('Close', nextTexNeu); end
        if ~isempty(nextTexFgt); Screen('Close', nextTexFgt); end
        Screen('Close', [texNeu, texFgt]);
        results(t:end, :) = []; 
        writetable(results, [filepath_run(loc, subID, sesID, b, taskLabel) '_beh.tsv'], 'FileType', 'text', 'Delimiter', '\t');
        continue; % Skip directly to the natural end-of-block routing logic
    end

    %% --- 5c - HEIGHT AFFORDANCE 
    trials = blocks.(sprintf('%s', taskLabel)){b}; 
    numTrials = length(trials);
    
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
    DrawFormattedText(w1, sprintf('BLOCK / RUN %d\n\n %s \nExperimenter can leave the tatami', b, log.config.task.instruction.(sprintf('%s', languageInput)).(sprintf('%s', taskLabel))), 'center', 'center', log.config.task.colour.white); 
    Screen('Flip', w1); 
    experimenter_message({'Communicate:',...
        'ARE YOU READY TO FIGHT?',...
        '(Click OK after Experimenter has left)'});
    outlet.push_sample({sprintf('BlockStart%d', b)});

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
            DrawFormattedText(w1, 'Experiment Paused by Technician.\nWe are coming to you now', 'center', 'center', log.config.task.colour.white);
            Screen('Flip', w1);
            
            ShowCursor;
            interceptChoice = questdlg(...
                sprintf('Run %d | Trial %d interrupted. What would you like to do?', b, t), ...
                'Technician Interrupt Menu', ...
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
        outlet.push_sample({sprintf('NPose%d', t)});
    
        % PHASE 1: Neutral Stimulus Display
        Screen('DrawTexture', w1, texNeu, [], posC);
        onset_neu = Screen('Flip', w1, onset_preFix + log.config.task.time.fixation - (ifi/2));
        outlet.push_sample({sprintf('Neutral%d', t)});
      
        % PHASE 2: Fight Stimulus Display
        Screen('DrawTexture', w1, texFgt, [], posC);
        onset_fgt = Screen('Flip', w1, onset_neu + log.config.task.time.neutral - (ifi/2));
        outlet.push_sample({sprintf('Fight%d', t)}); lsl_send_corrected_neon_event(sprintf('Fight%d', t), PHONE_IP);
    
        % Wait loop with continuous Esc observation to open menu at trial end
        while GetSecs < onset_fgt + log.config.task.time.fight
            [~,~,keyCode] = KbCheck;
            if keyCode(log.config.ptb.key.esc); intervene = true; end
        end
        
        % PHASE 3: Inter-Trial Interval (ITI)
        fix_iti_onset = Screen('Flip', w1); 
        outlet.push_sample({sprintf('TrialOffset%d', t)}); 
                
        % Asynchronous parallel texture generation for lookahead tracking
        if t < numTrials
            nextTexNeu = Screen('MakeTexture', w1, trials(t+1).neuData);
            nextTexFgt = Screen('MakeTexture', w1, trials(t+1).fgtData);
        end
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
        fprintf('\n[ABORTED] Run %d cut short by Technician at trial %d.\n', b, t);
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
    

    %% --- 7. BREAK (10min) after each RUN---
    % Call the local desktop countdown function UI
    if taskLabel == "training"
        choice = run_training_break_menu(b, log); 
    elseif taskLabel == "heightaffordance"
        choice = run_block_break_menu(b, log); 
    end
    switch choice
        case 'Next Run'
            b = b + 1; 
            if b <= maxBlocks
                DrawFormattedText(w1, 'Experimenter will start the next run shortly.', 'center', 'center', log.config.task.colour.white);
                Screen('Flip', w1);
            end
        case 'Save & End Experiment'
            fprintf('Experiment ended by experimenter request during break session.\n');
            terminateExperiment = 1;
    end
end 

%% --- 8. Final Session Cleanup & Termination ---
outlet.push_sample({'ExperimentEnd'});
Screen('CloseAll'); 
ShowCursor;
fprintf('\nSession ended safely. Total running time: %.2f seconds.\n', toc(totalTic));