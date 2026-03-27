%% Preparations 
% sca;            % Close PTB windows
% close all;      % Close MATLAB figures
% clearvars;      % Clear variables
% clc;            % Clear command window
% 
% %% Set paths (using your existing logic)
% loc = find_folderpath(); 
% add_paths(loc);
% 
% %% Creating a log file and configuration
% log = struct;
% [log.ID, loc.resulttable] = subject_info(loc);
% cfg = task_config; 
% cfg.loc = loc;
% 
% %% List and load stimuli
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


%% 3. Initialize PTB & Settings
cfg = initialize_PTB(cfg);
log.config.ptb.window1 = cfg.screens.window;          
log.config.ptb.window2 = cfg.screens.windowInstructor; 
log.time.start = datestr(now);
log.config.background = backgroundsetting();
log.config.ptb = ptbsetting(log);
log.config.task = tasksetting(log);
log.config.stim = stimsetting();

%% 4. Global Positioning (Aspect Ratio & Bottom Alignment)
% Get dimensions once (assuming all images are identical)
[imgH, imgW, ~] = size(trials(1).neuData);
aspectRatio = imgW / imgH;

% Calculate destRect for the participant screen (window1)
sw = cfg.screenXpixels; % Screen Width
sh = cfg.screenYpixels; % Screen Height

drawH = sh * 0.90;       % Scale to 90% of screen height
drawW = drawH * aspectRatio;
left  = (sw - drawW) / 2;
top   = sh - drawH;      % Aligns the bottom of the image to the bottom of the screen

% Final standardized destination rectangle
posC = [left, top, left + drawW, sh];
ifi  = Screen('GetFlipInterval', log.config.ptb.window1);

%% 5. Main Presentation Loop
terminate = 0; 
fprintf('Preparing first trial textures...\n');
% Prepare Trial 1 textures BEFORE the loop starts
texNeu = Screen('MakeTexture', log.config.ptb.window1, trials(1).neuData);
texFgt = Screen('MakeTexture', log.config.ptb.window1, trials(1).fgtData);

fprintf('Starting experiment. Press Space to begin.\n');
waitforkey(32); 

for t = 1:numTrials
    % --- PHASE 1: NEUTRAL (500ms) ---
    Screen('DrawTexture', log.config.ptb.window1, texNeu, [], posC);
    onset_neu = Screen('Flip', log.config.ptb.window1);
    
    % --- PHASE 2: FIGHT (2000ms) ---
    Screen('DrawTexture', log.config.ptb.window1, texFgt, [], posC);
    
    statusTxt = sprintf('Trial %d/%d', t, numTrials);
    DrawFormattedText(log.config.ptb.window1, statusTxt, 'center', 50, [255,255,255]);
    
    % Sample-accurate flip at 500ms
    onset_fgt = Screen('Flip', log.config.ptb.window1, onset_neu + 0.500 - (ifi/2));
    
    % --- ASYNCHRONOUS PREP (Trial T+1) ---
    % While participant looks at the Fight image, we prep the next one in RAM
    if t < numTrials
        nextTexNeu = Screen('MakeTexture', log.config.ptb.window1, trials(t+1).neuData);
        nextTexFgt = Screen('MakeTexture', log.config.ptb.window1, trials(t+1).fgtData);
    end

    % Wait for remainder of 2000ms
    while GetSecs < onset_fgt + 2.000
        [~,~,keyCode] = KbCheck;
        if keyCode(27); terminate = 1; break; end
    end
    if terminate; break; end
    
    % --- PHASE 3: ITI / FIXATION ---
    Screen('DrawLines', log.config.ptb.window1, log.config.stim.fix.allCoords, ...
        log.config.stim.fix.lineWidthPix, log.config.background.colour.black, ...
        [cfg.screens.xCenter, cfg.screens.yCenter]);
    
    fix_onset = Screen('Flip', log.config.ptb.window1);
    
    % Clear the textures we just showed to free GPU memory
    Screen('Close', [texNeu, texFgt]);
    
    % Promote the "next" textures to "current" status
    if t < numTrials
        texNeu = nextTexNeu;
        texFgt = nextTexFgt;
    end
    
    % ITI wait with ESC check
    while GetSecs < fix_onset + log.config.task.enc.iti
        [~,~,keyCode] = KbCheck;
        if keyCode(27); terminate = 1; break; end
    end
    if terminate; break; end
end

sca;
disp('Experiment Complete.');