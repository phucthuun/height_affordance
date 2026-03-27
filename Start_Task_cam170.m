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

% Get dimensions from Trial 1
[imgH, imgW, ~] = size(trials(1).neuData);
aspectRatio = imgW / imgH;

% Calculate destRect
drawH = sh * 1.0; 
drawW = drawH * aspectRatio;
left  = (sw - drawW) / 2;
top   = sh - drawH; 

posC = [left, top, left + drawW, sh];


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
    % --- PHASE 1: NEUTRAL (500ms) ---
    Screen('DrawTexture', w1, texNeu, [], posC);
    onset_neu = Screen('Flip', w1);
    
    % --- PHASE 2: FIGHT (2000ms) ---
    Screen('DrawTexture', w1, texFgt, [], posC);
    
    statusTxt = sprintf('Trial %d/%d', t, numTrials);
    DrawFormattedText(w1, statusTxt, 'center', 50, log.config.task.colour.white);
    
    % Sample-accurate flip at 500ms
    onset_fgt = Screen('Flip', w1, onset_neu + log.config.task.time.neutral - (ifi/2));
    
    % --- ASYNCHRONOUS PREP (Trial T+1) ---
    if t < numTrials
        nextTexNeu = Screen('MakeTexture', w1, trials(t+1).neuData);
        nextTexFgt = Screen('MakeTexture', w1, trials(t+1).fgtData);
    end

    % Wait for Fight Duration
    while GetSecs < onset_fgt + log.config.task.time.fight
        [~,~,keyCode] = KbCheck;
        if keyCode(27); terminate = 1; break; end
    end
    if terminate; break; end
    
    % --- PHASE 3: ITI / FIXATION ---
    % Note: Using log.config.task.colour.white so it's visible on dark bg
    Screen('DrawLines', w1, log.config.stim.fix.allCoords, ...
        log.config.stim.fix.lineWidthPix, log.config.task.colour.white, [xc, yc]);
    
    fix_onset = Screen('Flip', w1);
    
    % Resource Management
    Screen('Close', [texNeu, texFgt]);
    
    if t < numTrials
        texNeu = nextTexNeu;
        texFgt = nextTexFgt;
    end
    
    % ITI wait with ESC check
    while GetSecs < fix_onset + log.config.task.time.iti
        [~,~,keyCode] = KbCheck;
        if keyCode(27); terminate = 1; break; end
    end
    if terminate; break; end
end

sca;
% Save the log at the very end
% save(log.savePath, 'log');
% disp(['Experiment Complete. Data saved to: ' log.savePath]);
disp(['Experiment Complete.']);