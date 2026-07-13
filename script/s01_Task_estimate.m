%% 1. Creating a log file and configuration
log = struct; 
[subID, sesID, startRun, taskLabel] = subject_info2(loc, 'e');
%% 2. Task setting
log.config.task = task_setting();  
log.config.stim = stim_setting();

%% 3. List and load stimuli
mat_file = fullfile(loc.stimuli.estimate, 'stimuli.mat');
totalTic = tic;  
if exist(mat_file, 'file')
    fprintf('Found existing randomized list. Loading...\n');
    data = load(mat_file, 'masterTrials'); 
    blocks = data.masterTrials;
else
    fprintf('No randomized list found. Commencing loading...\n');
    % This calls the simple preloader we created earlier
    % blocks = stimuli_preload_simple(loc.stimuli.estimate, loc.stimuli.estimate, 1);
    blocks = stimuli_randomize_preload_estimate(loc.stimuli.estimate, loc.stimuli.estimate, 1);
end

fprintf('Finished loading stimuli after %.2f seconds.\n', toc(totalTic));

%% 4. Initialize Result Table
% Calculate total trials
numTotalTrials = sum(cellfun(@length, blocks));

% Added 'estimate' column to your table structure
results = table('Size', [numTotalTrials, 8], ...
    'VariableTypes', {'double', 'double', 'double', 'string', 'double', 'string', 'double', 'double'}, ...
    'VariableNames', {'block', 'trial_id', 'cam', 'posture', 'stance', 'laterality', 'exemplar', 'estimate'});


%% 5. Initialize PTB & Positioning
log.config.ptb = ptb_setting(log);
w1  = log.config.ptb.w1;
sw  = log.config.ptb.sw;
sh  = log.config.ptb.sh;
xc  = log.config.ptb.xc;
yc  = log.config.ptb.yc;

% Positioning logic (Width-Matched & Bottom Aligned with 2cm shift)
targetWidth = 400; 
targetHeight = 225; 
targetShift = 2;
verticalShift = (sh / targetHeight) * targetShift; 
heightRatio = targetHeight / targetWidth;

drawW = sw;             
drawH = sw * heightRatio; 
newBottom = sh - verticalShift;
newTop    = newBottom - drawH;
posC = [0, newTop, sw, newBottom];

Screen('BlendFunction', w1, 'GL_SRC_ALPHA', 'GL_ONE_MINUS_SRC_ALPHA'); 

%% 6. LSL Setup
lib = lsl_loadlib();
info = lsl_streaminfo(lib, 'MATLAB_Trigger', 'Markers', 1, 0, 'cf_string', 'mbt_sync_001');
outlet = lsl_outlet(info);

%% 7. Main Presentation Loop
DrawFormattedText(w1, log.config.task.instruction.estimate, 'center', 'center', log.config.task.colour.white); 
Screen('Flip', w1);
confirmation_text('Check for LSL Signal and start EEG Recording.\n');

terminate = 0; 
globalTrialCount = 0;    
log.time.start = datestr(now); 
outlet.push_sample({'Experiment_Start'});  

for b = 1:length(blocks)
    trials = blocks{b}; 
    numTrials = length(trials);
        
    outlet.push_sample({sprintf('Block%d_Start', b)});

    for t = 1:numTrials
        globalTrialCount = globalTrialCount + 1;
        
        % 1. Create Texture for current trial
        tex = Screen('MakeTexture', w1, trials(t).imageData);
        
        % 2. Draw Image and Text Prompt
        Screen('DrawTexture', w1, tex, [], posC);
        DrawFormattedText(w1, 'The fighter is ___ cm tall', 'center', 10*verticalShift, log.config.task.colour.white);
        
        % 3. Show Stimulus
        onset_stim = Screen('Flip', w1);
        outlet.push_sample({sprintf('Trial%d_Onset', t)});
        
        % 4. EXPERIMENTER INPUT
        % We must allow the Command Window to receive characters
        ListenChar(0); 
        fprintf('\n--- Trial %d ---\n', t);
        fprintf('Sub: %s | Stance: %d | Lat: %s\n', trials(t).subID, trials(t).stance, trials(t).laterality);
        
        % Script pauses here for experimenter input
        val = input('Enter participant estimate (cm): ');
        
        % Re-block characters from the Command Window
        ListenChar(2); 

        % 5. Log Results
        results.block(globalTrialCount)      = b;
        results.trial_id(globalTrialCount)   = t;
        results.cam(globalTrialCount)        = trials(t).cam;
        results.posture(globalTrialCount)    = trials(t).posture;
        results.stance(globalTrialCount)     = trials(t).stance;
        results.laterality(globalTrialCount) = trials(t).laterality;
        results.exemplar(globalTrialCount)   = trials(t).exemplar;
        results.estimate(globalTrialCount)   = val; % The input value
    
        % 6. Resource Cleanup
        Screen('Close', tex);
        
        % Check for Escape key
        [~,~,keyCode] = KbCheck;
        if keyCode(KbName('ESCAPE')); terminate = 1; break; end
    end
    
    if terminate; break; end
    
    outlet.push_sample({sprintf('Block%d_End', b)});
    DrawFormattedText(w1, 'Block Complete.\nPlease wait for the experimenter.', 'center', 'center', log.config.task.colour.white);
    Screen('Flip', w1);
    WaitSecs(2);
end

%% 8. Cleanup and Saving
outlet.push_sample({'Experiment_End'});
Screen('CloseAll');
ListenChar(0); % Ensure keyboard is back to normal

runFilepath = filepath_run(loc, subID, sesID, b, taskLabel);

% Save Results (BIDS Format)
tsvFilename = [runFilepath '_beh.tsv'];
writetable(results, tsvFilename, 'FileType', 'text', 'Delimiter', '\t');

matFilename = [runFilepath '_beh.mat'];
save(matFilename, 'log', 'results');

% JSON Sidecar
jsonFilename = [runFilepath '_beh.json'];
jsonStruct = struct(...
    'block', 'Block number', ...
    'trial_id', 'Trial ID', ...
    'cam', 'Camera ID', ...
    'posture', 'Fighter posture', ...
    'stance', 'Stance height in cm', ...
    'laterality', 'Fighter laterality', ...
    'exemplar', 'Stimulus exemplar ID', ...
    'estimate', 'Participant height estimate in cm');

fid = fopen(jsonFilename, 'w');
fprintf(fid, '%s', jsonencode(jsonStruct));
fclose(fid);

fprintf('\nSuccess! Data saved to results folder.\n');

%% 9. Plot Estimation Accuracy Analysis
if exist('results', 'var') && ~isempty(results)
    figure('Name', 'Estimation Accuracy Analysis', 'Color', 'w', 'Position', [100, 100, 600, 550]);
    hold on;
    
    % Plot individual trial points
    scatter(results.stance, results.estimate, 60, 'filled', ...
        'MarkerFaceColor', [0.2, 0.4, 0.8], 'MarkerEdgeColor', 'k', 'MarkerFaceAlpha', 0.7);

    % Perfect identity line (Y = X)
    minVal = min([results.stance; results.estimate]) - 5;
    maxVal = max([results.stance; results.estimate]) + 5;
    plot([minVal, maxVal], [minVal, maxVal], 'r--', 'LineWidth', 2);

    % Formatting
    xlabel('True Stance Height (cm)', 'FontSize', 12);
    ylabel('Estimated Height (cm)', 'FontSize', 12);
    title('Estimated vs. True Height', 'FontSize', 14, 'FontWeight', 'bold');
    grid on;
    set(gca, 'GridLineStyle', '--', 'GridAlpha', 0.5);
    xlim([minVal, maxVal]);
    ylim([minVal, maxVal]);
    legend({'Trial Estimates', 'Perfect Accuracy (Y=X)'}, 'Location', 'northwest', 'FontSize', 10);
    axis square;
    hold off;

else
    warning('The ''results'' table is empty or does not exist. Cannot generate accuracy plot.');
end