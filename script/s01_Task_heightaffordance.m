%% Creating a log file and configuration
log = struct;
[log.ID, loc.resulttable] = subject_info(loc, 'h');
 
%% Task setting
log.config.task = task_setting();  
log.config.stim = stim_setting();


%% List and load stimuli
mat_file = fullfile(loc.stimuli.heightaffordance, 'stimuli.mat');
if exist(mat_file, 'file')
    fprintf('Found existing randomized list. Loading...\n');
    data = load(mat_file, 'masterTrials'); 
    blocks = data.masterTrials;
else
    fprintf('No randomized list found. Commencing metadata extraction and loading...\n');
    blocks = stimuli_randomize_preload(loc.stimuli.heightaffordance, loc.stimuli.heightaffordance, log.config.task.numBlocks.heightaffordance);
end
 
fprintf('Finished loading stimuli after %.2f seconds.\n', toc(totalTic));

%% Result table
% Calculate total trials across all blocks
numTotalTrials = sum(cellfun(@length, blocks));

% Pre-allocate with fixed size
results = table('Size', [numTotalTrials, 7], ...
    'VariableTypes', {'double', 'double', 'double', 'string', 'double', 'string', 'double'}, ...
    'VariableNames', {'block', 'trial_id', 'cam', 'posture', 'stance', 'laterality', 'exemplar'});

%% 3. Initialize PTB
log.config.ptb = ptb_setting(log);

%% 4. Global Positioning (Width-Matched & Bottom Aligned)
w1  = log.config.ptb.w1;
sw  = log.config.ptb.sw;
sh  = log.config.ptb.sh;
ifi = log.config.ptb.ifi;
xc  = log.config.ptb.xc;
yc  = log.config.ptb.yc;

% Define the target physical dimensions
targetWidth = 400; 
targetHeight = 225; 
targetShift = 2;

% Conversion: How many pixels are in 2cm?
% (sh / 225) gives pixels per cm. Multiply by 2.
verticalShift = (sh / targetHeight) * targetShift; 

% Scaled height logic (16:9 ratio based on screen width)
heightRatio = targetHeight / targetWidth; % 0.5625

% % Or use the aspect ratio of the image
% [imgH, imgW, ~] = size(trials(1).neuData);
% heightRatio = imgH / imgR;

drawW = sw;             
drawH = sw * heightRatio; 

% NEW POSITIONING: 
% Subtract verticalShift from the standard bottom alignment (sh)
newBottom = sh - verticalShift;
newTop    = newBottom - drawH;

posC = [0, newTop, sw, newBottom];

% Enable Alpha Blending (Keep this for transparency support)
Screen('BlendFunction', w1, 'GL_SRC_ALPHA', 'GL_ONE_MINUS_SRC_ALPHA'); 

%% 5. LSL: Describe the marker stream
lib = lsl_loadlib();
info = lsl_streaminfo(lib, 'MATLAB_Trigger', 'Markers', 1, 0, 'cf_string', 'mbt_sync_001');
outlet = lsl_outlet(info);

confirmation_text('Check for LSL Signal and start EEG Recording.\n');


%% 6. Main Presentation Loop
terminate = 0; globalTrialCount = 0;    
fprintf('Preparing first trial textures...\n');
log.time.start = datestr(now); outlet.push_sample({'Experiment_Start'});  
totalTic = tic;  

for b = 1:4

    trials = blocks{b}; numTrials = length(trials);

    % Initial textures
    texNeu = Screen('MakeTexture', w1, trials(1).neuData);
    texFgt = Screen('MakeTexture', w1, trials(1).fgtData);
    
    fprintf('Starting experiment...\n');
    confirmation_text(sprintf('Start Block %d', b));
    DrawFormattedText(w1,sprintf('BLOCK %d\n\n', b), 'center', 50, log.config.task.colour.white); 
    Screen('Flip', w1); outlet.push_sample({sprintf('Block%d_Start', b)});  


    for t = 1:numTrials
        globalTrialCount = globalTrialCount + 1;
        % Prepare Info String
        infoStr = sprintf('Trial %d/%d | Stance: %s | Laterality: %s', ...
            t, numTrials, string(trials(t).stance), string(trials(t).laterality));
    
        fprintf(sprintf('%s \n', infoStr));
        % --- PHASE 0: OFFLOAD / CONSTANT (Calibration) ---
        Screen('TextSize', w1, 400); 
        DrawFormattedText(w1, 'N', 'center', yc + verticalShift, log.config.task.colour.white);
        Screen('TextSize', w1, 30); % Reset to standard size for labels
        
        onset_offload = Screen('Flip', w1);
        outlet.push_sample({'Trial_Calibration_Start'}); 
        
        % --- PHASE 0.5: PRE-STIMULUS BLANK SPACE ---
        % Flip and send specific LSL marker for EEG analysis
        onset_preFix = Screen('Flip', w1, onset_offload + log.config.task.time.offload - (ifi/2));
        outlet.push_sample({'Trial_Calibration_Done'}); 
    
        % --- PHASE 1: NEUTRAL ---
        Screen('DrawTexture', w1, texNeu, [], posC);
        DrawFormattedText(w1, [infoStr ' \n\n PHASE: NEUTRAL'], 'center', 50, log.config.task.colour.white);
        
        onset_neu = Screen('Flip', w1, onset_preFix + log.config.task.time.fixation - (ifi/2));
        outlet.push_sample({sprintf('T%d_Neutral_Stance%s_Lat%s', t, string(trials(t).stance), trials(t).laterality)});
      
        % --- PHASE 2: FIGHT ---
        Screen('DrawTexture', w1, texFgt, [], posC);
        DrawFormattedText(w1, [infoStr ' \n\n PHASE: FIGHT'], 'center', 50, log.config.task.colour.white);
        
        onset_fgt = Screen('Flip', w1, onset_neu + log.config.task.time.neutral - (ifi/2));
        outlet.push_sample({'Fight_Stimulus'}); 
        
        % --- ASYNCHRONOUS PREP (Trial T+1) ---
        if t < numTrials
            nextTexNeu = Screen('MakeTexture', w1, trials(t+1).neuData);
            nextTexFgt = Screen('MakeTexture', w1, trials(t+1).fgtData);
        end
    
        % Wait for Fight Duration with ESC check
        while GetSecs < onset_fgt + log.config.task.time.fight
            [~,~,keyCode] = KbCheck;
            if keyCode(27); terminate = 1; break; end
        end
        if terminate; break; end
        
        % --- PHASE 3: ITI / POST-TRIAL FIXATION ---
        fix_iti_onset = Screen('Flip', w1); 
        outlet.push_sample({'Trial_Offset'}); 
        
        % Resource Management: Close textures for current trial
        Screen('Close', [texNeu, texFgt]);
        
        if t < numTrials
            texNeu = nextTexNeu;
            texFgt = nextTexFgt;
        end
        
        % ITI wait
        while GetSecs < fix_iti_onset + log.config.task.time.iti
            [~,~,keyCode] = KbCheck;
            if keyCode(27); terminate = 1; break; end
        end
    
        % ----- LOG TO RESULTS TABLE -----
        results.block(globalTrialCount)      = b;
        results.trial_id(globalTrialCount)   = t;
        results.cam(globalTrialCount)        = trials(t).cam;
        results.posture(globalTrialCount)    = trials(t).posture;
        results.stance(globalTrialCount)     = trials(t).stance;
        results.laterality(globalTrialCount) = trials(t).laterality;
        results.exemplar(globalTrialCount)   = trials(t).exemplar;
    
        if terminate; break; end
    end
    if terminate; break; end
end

%% 7. Cleanup and BIDS Saving
outlet.push_sample({'Experiment_End'});
Screen('CloseAll'); 
fprintf('Experiment Complete in %.2f seconds.\n', toc(totalTic));

% --- BIDS SAVING LOGIC ---
% loc.resulttable (from subject_info) contains the path: 
% ../results/sub-XXX/ses-XX/beh/sub-XXX_ses-XX_task-name_run-XX

% 1. Save the primary results table as a BIDS-compliant .tsv file
tsvFilename = [loc.resulttable '_beh.tsv'];
writetable(results, tsvFilename, 'FileType', 'text', 'Delimiter', '\t');

% 2. Save the MATLAB-specific log structure (includes configs and timestamps)
matFilename = [loc.resulttable '_beh.mat'];
save(matFilename, 'log', 'results');

% 3. Save a BIDS Sidecar JSON (Recommended for BIDS compliance)
% This describes the columns in your TSV
jsonFilename = [loc.resulttable '_beh.json'];
jsonStruct = struct(...
    'block', 'Block number in the session', ...
    'trial_id', 'Trial number within the block', ...
    'cam', 'Camera height', ...
    'posture', 'Fight posture of virtual opponent', ...
    'stance', 'Height of stance of virtual opponent in cm', ...
    'laterality', 'Left or right-forward stance of virtual opponent', ...
    'exemplar', 'Specific stimulus ID');

% Use jsonencode and write to file
fid = fopen(jsonFilename, 'w');
if fid ~= -1
    fprintf(fid, '%s', jsonencode(jsonStruct));
    fclose(fid);
end

fprintf('\nData saved to BIDS structure:\nTSV: %s\nMAT: %s\n', tsvFilename, matFilename);