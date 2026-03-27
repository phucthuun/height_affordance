%% Preparations 
totalTic = tic;
sca;            % Close PTB windows
close all;      % Close MATLAB figures
clearvars;      % Clear variables
clc;            % Clear command window
 
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
% List, Randomize, and Load stimuli
mat_file = fullfile(loc.stimuli, 'MASTER_EXPERIMENT_DATA_randomize_3constraints.mat');
mat_file = fullfile('C:\Data\Research\', 'MASTER_EXPERIMENT_DATA_randomize_3constraints.mat');

if exist(mat_file, 'file')
    fprintf('Found existing randomized list. Loading...\n');
    data = load(mat_file, 'masterTrials'); 
    trials = data.masterTrials;
else
    fprintf('No randomized list found. Commencing metadata extraction and loading...\n');
    % trials = stimuli_randomize_preload(loc.stimuli, loc.stimuli);
    trials = stimuli_randomize_preload(loc.stimuli, fullfile('C:\Data\Research\'));
end

numTrials = length(trials);

fprintf('Finished loading stimuli in %.2f seconds.\n', toc(totalTic));
% Get dimensions from Trial 1
[imgH, imgW, ~] = size(trials(1).neuData);
aspectRatio = imgW / imgH;

% Calculate destRect
drawH = sh * 1.0; 
drawW = drawH * aspectRatio;
left  = (sw - drawW) / 2;
top   = sh - drawH; 

posC = [left, top, left + drawW, sh];

% 1. ENABLE BLENDING (Put this right after log.config.ptb = ptb_setting(log))
Screen('BlendFunction', w1, 'GL_SRC_ALPHA', 'GL_ONE_MINUS_SRC_ALPHA');

% 2. LOAD CONSTANT IMAGE
constantPath = fullfile(loc.constantpic, 'calibration.jpg'); % Use PNG for transparency

if exist(constantPath, 'file')
    [img, ~, alpha] = imread(constantPath);
    
    % If it's a PNG with alpha, combine. If alpha is empty (JPG), skip cat.
    if ~isempty(alpha)
        rgbaData = cat(3, img, alpha);
    else
        rgbaData = img;
    end
    
    texConstant = Screen('MakeTexture', w1, rgbaData);
    
    % Calculate dimensions (using the correct variable 'img')
    [cHeight, cWidth, ~] = size(img);
    cAspectRatio = cWidth / cHeight;
    
    % Define position for Constant (Centered, 100% of screen height)
    offloadH = sh * 1.0; 
    offloadW = offloadH * cAspectRatio;
    posOffload = CenterRectOnPoint([0 0 offloadW offloadH], xc, yc);
else
    error('Constant image not found at: %s', constantPath);
end


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