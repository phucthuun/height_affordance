%% Preparations 
% sca;            % Close PTB windows
% close all;      % Close MATLAB figures
% clearvars;      % Clear variables
% clc;            % Clear command window
 
%% Set paths (using your existing logic)
loc = find_folderpath(); 
add_paths(loc);
 

%% Creating a log file and configuration
log = struct;
[log.ID, loc.resulttable] = subject_info(loc);

%% Task setting
log.config.task = task_setting();
log.config.stim = stim_setting();




%% 3. Initialize PTB
% Pass the WHOLE log. ptb_setting now returns everything into log.config.ptb
log.config.ptb = ptb_setting(log);

%% 4. Global Positioning (Aspect Ratio & Bottom Alignment)
% Using the new short names from log.config.ptb
w1  = log.config.ptb.w1;
sw  = log.config.ptb.sw;
sh  = log.config.ptb.sh;
ifi = log.config.ptb.ifi;
xc  = log.config.ptb.xc;
yc  = log.config.ptb.yc;

%% List and load stimuli
% mat_file = fullfile(loc.stimuli, 'preloaded_stimuli.mat');
% 
% % List and load image stimuli
% if exist(mat_file, 'file')
%     fprintf('Loading preloaded stimulus file... please wait.\n');
%     load(mat_file); % This brings the 'stimuli' variable into the workspace
% else
%     % Fallback if the .mat doesn't exist yet
%     stimuli = preload_image(loc.stimuli, loc.stimuli);
% end
% 
% numTrials = length(stimuli);
% 
% % Build Trials
% trials = generate_trial_list(stimuli, loc.stimuli);
% clear stimuli; % Free up RAM after building trial list

%% List, Randomize, and Load stimuli
% mat_file = fullfile(loc.stimuli, 'MASTER_EXPERIMENT_DATA_rand3.mat');
% 
% if exist(mat_file, 'file')
%     fprintf('Found existing randomized list. Loading...\n');
%     data = load(mat_file, 'masterTrials'); 
%     trials = data.masterTrials;
% else
%     fprintf('No randomized list found. Commencing metadata extraction and loading...\n');
%     trials = stimuli_randomize_preload(loc.stimuli, loc.stimuli);
% end
% 
% numTrials = length(trials);


% Get dimensions from Trial 1
[imgH, imgW, ~] = size(trials(1).neuData);
aspectRatio = imgW / imgH;

% Calculate destRect
drawH = sh * 1.0; 
drawW = drawH * aspectRatio;
left  = (sw - drawW) / 2;
top   = sh - drawH; 

posC = [left, top, left + drawW, sh];

% --- Load Constant/Offload Image ---
constantPath = fullfile(loc.constantpic, 'calibration.jpg');

if exist(constantPath, 'file')
    % [img, ~, alpha] catches the RGB and the Transparency layer separately
    [img, ~, alpha] = imread(constantPath);
    
    % Concatenate them into a 4-layer RGBA matrix
    rgbaData = cat(3, img, alpha);
    
    % Create the texture using the 4-layer matrix
    texConstant = Screen('MakeTexture', w1, rgbaData);
else
    error('Constant image not found at: %s', constantPath);
end

% Define position for Constant (Centered, 100% of screen height)
offloadH = sh * 1.0; 
offloadW = offloadH * (size(constantData,2)/size(constantData,1));
posOffload = CenterRectOnPoint([0 0 offloadW offloadH], xc, yc);

%% 5. Main Presentation Loop
terminate = 0; 
fprintf('Preparing first trial textures...\n');

% Initial textures
texNeu = Screen('MakeTexture', w1, trials(1).neuData);
texFgt = Screen('MakeTexture', w1, trials(1).fgtData);

fprintf('Starting experiment. Press Space to begin.\n');
waitforkey(32); 
log.time.start = datestr(now);


for t = 1:numTrials
    % Prepare Info String (Trial X | Stance X | Laterality X)
    % Note: Replace '.stance' with whatever field name is in your 'trials' struct
    infoStr = sprintf('Trial %d/%d | Stance: %s | Lat: %s', ...
        t, numTrials, string(trials(t).stance), string(trials(t).laterality));
    
    % --- PHASE 0: OFFLOAD / CONSTANT (2.0s) ---
    Screen('DrawTexture', w1, texConstant, [], posC);
    DrawFormattedText(w1, [infoStr ' \n\n PHASE: OFFLOAD'], 'center', 50, log.config.task.colour.white);
    
    Screen('DrawLines', w1, log.config.stim.fix.allCoords, ...
        log.config.stim.fix.lineWidthPix, log.config.task.colour.white, [xc, yc]);
    
    onset_offload = Screen('Flip', w1);

    % --- PHASE 0.5: PRE-STIMULUS FIXATION (0.25s) ---
    Screen('DrawLines', w1, log.config.stim.fix.allCoords, ...
        log.config.stim.fix.lineWidthPix, log.config.task.colour.white, [xc, yc]);
    DrawFormattedText(w1, [infoStr ' \n\n PHASE: FIXATION'], 'center', 50, log.config.task.colour.white);
    onset_preFix = Screen('Flip', w1, onset_offload + log.config.task.time.offload - (ifi/2));

    % --- PHASE 1: NEUTRAL (0.5s) ---
    Screen('DrawTexture', w1, texNeu, [], posC);
    DrawFormattedText(w1, [infoStr ' \n\n PHASE: NEUTRAL'], 'center', 50, log.config.task.colour.white);
    onset_neu = Screen('Flip', w1, onset_preFix + log.config.task.time.fixation - (ifi/2));
    
    % --- PHASE 2: FIGHT (1.5s) ---
    Screen('DrawTexture', w1, texFgt, [], posC);
    DrawFormattedText(w1, [infoStr ' \n\n PHASE: FIGHT'], 'center', 50, log.config.task.colour.white);
    onset_fgt = Screen('Flip', w1, onset_neu + log.config.task.time.neutral - (ifi/2));
    
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
    Screen('DrawLines', w1, log.config.stim.fix.allCoords, ...
        log.config.stim.fix.lineWidthPix, log.config.task.colour.white, [xc, yc]);
    DrawFormattedText(w1, [infoStr ' \n\n PHASE: ITI'], 'center', 50, log.config.task.colour.white);
    fix_iti_onset = Screen('Flip', w1);
    
    % Resource Management
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
    if terminate; break; end
end

Screen('Close', texConstant);
sca;
% save(log.savePath, 'log');
disp('Experiment Complete.');