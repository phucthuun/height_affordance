%% Run the script

%% preparations 
% sca;          % close PTB windows
close all;    % close MATLAB figures
clearvars;    % clear variables only
clc;          % clear command window
tic;
%% debug mode
%PsychDebugWindowConfiguration (0,0.5); % helpful for debugging (transparent screen)

%% set paths
loc = find_folderpath(); add_paths(loc);

%% creating a log file
log = struct;

[log.ID, loc.resulttable] = subject_info(loc);

% load general configuration-settings   
cfg = task_config; cfg.loc = loc;
 
%% list and load images
stimuli = loadstim(loc.stimuli);

% %% Initialize PsychToolbox Settings & open screen
% cfg = initialize_PTB(cfg);

% Test trials
log.time.start=datestr(now);

% set background (e.g., colors, shapes)
log.config.background=backgroundsetting();

% standard ptb settings (screen, windows, keys and keyboard settings) 
log.config.ptb=ptbsetting(log);

% task setting (e.g., instructions, durations, positions)
log.config.task = tasksetting(log);

% stimsetting (settings fixation cross)
log.config.stim=stimsetting();

% presentation
terminate = 0;
% [log.result.enc,terminate]=present_enc(log,loc);

%% Positioning
[window1, window2]=loadpresentationwindow(log);
% Coordinates of encoding image (see ...\function\img-position.jpg)
window1.posC = [(window1.w+8*window1.Wunit) (window1.h+3*window1.Hunit) (window1.w+17*window1.Wunit) (window1.h+12*window1.Hunit)];
window2.posC = [(window2.w+5*window2.Wunit) (window2.h+0*window2.Hunit) (window2.w+20*window2.Wunit) (window2.h+15*window2.Hunit)];
window2.posC = [(window2.w+0*window2.Wunit) (window2.h-5*window2.Hunit) (window2.w+25*window2.Wunit) (window2.h+20*window2.Hunit)];

for encblock = 1
    terminate=waitforkey(32); 
    
    t0 = GetSecs(); % Start (and preload function GetSecs) timing
%     %% Prepare presentationresult table
%     presentationresult.(sprintf('enc%d',encblock)) = struct('soundenc',[],'imageenc',[]);
%     presentationresult.(sprintf('enc%d',encblock)) = repmat(presentationresult.(sprintf('enc%d',encblock)),length(stimuli),1);

    if terminate == 0

        Screen ('DrawLines', log.config.ptb.window1, log.config.stim.fix.allCoords, log.config.stim.fix.lineWidthPix, log.config.background.colour.black,[log.config.ptb.xCenter1, log.config.ptb.yCenter1]);
        Screen ('DrawLines', log.config.ptb.window2, log.config.stim.fix.allCoords, log.config.stim.fix.lineWidthPix, log.config.background.colour.black,[log.config.ptb.xCenter2, log.config.ptb.yCenter2]);
        fixation_onset=GetSecs();
        Screen('Flip', log.config.ptb.window1); 
        Screen('Flip', log.config.ptb.window2); 

        % wait until iti
        while GetSecs() < fixation_onset+log.config.task.enc.iti   
        end
        
        for currenttrial=2:length({stimuli.name})

            % --- First show image 1 ---
            window1.image = Screen('MakeTexture', log.config.ptb.window1, stimuli(1).image);
            window2.image = Screen('MakeTexture', log.config.ptb.window2, stimuli(1).image);
        
            Screen('DrawTexture', log.config.ptb.window1, window1.image, [], window1.posC);
            Screen('DrawTexture', log.config.ptb.window2, window2.image, [], window2.posC);
        
            DrawFormattedText(log.config.ptb.window1, ...
                ['Trial ' num2str(currenttrial,'%d') '/32 - First image'], ...
                'center','center',[0,0,0]);
        
            trial_onset = GetSecs();
            Screen('Flip', log.config.ptb.window1);
            Screen('Flip', log.config.ptb.window2);
        
            while GetSecs() < trial_onset + log.config.task.enc.baselinedur.image
            end
            
            % --- Then show the current trial image ---
            window1.image=Screen('MakeTexture',log.config.ptb.window1,stimuli(currenttrial).image);
            Screen('FillRect',log.config.ptb.window1,[96,96,96],window1.posC);
            Screen('DrawTexture',log.config.ptb.window1,window1.image,[],window1.posC); 
            window2.image=Screen('MakeTexture',log.config.ptb.window2,stimuli(currenttrial).image);
            Screen('FillRect',log.config.ptb.window2,[96,96,96],window2.posC);
            Screen('DrawTexture',log.config.ptb.window2,window2.image,[],window2.posC); 
            
            DrawFormattedText(log.config.ptb.window1, sprintf('Height: %s cm', stimuli(currenttrial).height{1}), 'center',window1.h+5*window1.Hunit,[255,255,255]);
            DrawFormattedText(log.config.ptb.window2, sprintf('Height: %s cm', stimuli(currenttrial).height{1}), 'center',window2.h+5*window2.Hunit,[255,255,255]);
            DrawFormattedText(log.config.ptb.window1, ['Trial ' num2str(currenttrial, '%d') '/32'], 'center','center',[0,0,0]);
            


            % flip
            trial_onset=GetSecs();
            Screen('Flip', log.config.ptb.window1); 
            Screen('Flip', log.config.ptb.window2);
            
            % wait until iti
            while GetSecs() < trial_onset+log.config.task.enc.stimdur.image        
            end

             
            Screen ('DrawLines', log.config.ptb.window1, log.config.stim.fix.allCoords, log.config.stim.fix.lineWidthPix, log.config.background.colour.black,[log.config.ptb.xCenter1, log.config.ptb.yCenter1]);
            Screen ('DrawLines', log.config.ptb.window2, log.config.stim.fix.allCoords, log.config.stim.fix.lineWidthPix, log.config.background.colour.black,[log.config.ptb.xCenter2, log.config.ptb.yCenter2]);
            fixation_onset=GetSecs();
            Screen('Flip', log.config.ptb.window1); 
            Screen('Flip', log.config.ptb.window2); 
          
% % %             % wait until iti
% % %             while GetSecs() < fixation_onset+log.config.task.enc.iti 
% % % 
% % %             end

            % ITI loop with ESC check
            terminate = 0;
            while GetSecs() < fixation_onset + log.config.task.enc.iti
                [keyIsDown, ~, keyCode] = KbCheck;
                if keyIsDown
                    if keyCode == 27   % ESC pressed
                        disp('Escape key pressed. Exiting...');
                        terminate = 1;
                        break;
                    end
                end
            end

%             presentationresult.(sprintf('enc%d',encblock))(currenttrial).soundenc   = log.presentation.(sprintf('enc%d',encblock)).sound(currenttrial).name;
%             presentationresult.(sprintf('enc%d',encblock))(currenttrial).imageenc   = stimuli(currenttrial).name;
%             presentationresult.(sprintf('enc%d',encblock))(currenttrial).start_time = trial_onset - t0;
%             presentationresult.(sprintf('enc%d',encblock))(currenttrial).end_time = fixation_onset - t0;
            
% 
%             Screen('Close');
         end
    elseif terminate == 1
        Screen('Close');clear screen;  
        break
    end
end
Screen('Close');clear screen; 