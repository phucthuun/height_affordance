function masterTrials = generate_trial_list(stimuli, save_path)
    % Start Global Timer
    totalTic = tic;
    fprintf('\n======================================================\n');
    fprintf('STARTING MASTER TRIAL GENERATION\n');
    fprintf('Timestamp: %s\n', datestr(now, 'HH:MM:SS'));
    fprintf('======================================================\n');

    %% --- MILESTONE 1: FILTERING TARGETS ---
    % Identify every "Fight-Lowered" image as the primary trial trigger
    fgtIdx = find([stimuli.scenario] == "fight" & [stimuli.posture] == "lowered");
    numFight = length(fgtIdx);
    rawList = [];
    
    fprintf('[Milestone 1] Found %d Fight-Lowered stimuli.\n', numFight);
    fprintf('... Searching for corresponding Neutral Upright baselines...\n');

    %% --- MILESTONE 2: PAIRING NEUTRAL & FIGHT ---
    matchTic = tic;
    count = 1;
    for i = 1:numFight
        f = stimuli(fgtIdx(i));
        
        % Search Rule: Same SubID, Same Exemplar, but Neutral/Upright
        nIdx = find([stimuli.subID] == f.subID & ...
                    [stimuli.scenario] == "neutral" & ...
                    [stimuli.exemplar] == f.exemplar);
        
        if ~isempty(nIdx)
            rawList(count).subID   = f.subID;
            rawList(count).neuData = stimuli(nIdx).imageData; % 500ms image
            rawList(count).fgtData = f.imageData;            % 2000ms image
            rawList(count).neuName = stimuli(nIdx).name;
            rawList(count).fgtName = f.name;
            rawList(count).info    = sprintf('Sub: %s | Stance: %d | Lat: %s', ...
                                     f.subID, f.stance, f.laterality);
            count = count + 1;
        else
            warning('No Neutral match for: %s', f.name);
        end
        
        % Progress Trace every 1 matches
        if mod(i, 1) == 0
            fprintf('    Matched %d/%d pairs... (%.2f sec elapsed)\n', i, numFight, toc(matchTic));
        end
    end
    
    actualTrials = length(rawList);
    fprintf('[Milestone 2] Pairing Complete. Total Trials: %d. Time: %.2f sec.\n', ...
        actualTrials, toc(matchTic));

    %% --- MILESTONE 3: SMART SHUFFLE (NO CONSECUTIVE SUBJECTS) ---
    fprintf('\n[Milestone 3] Performing Smart Shuffle for 1,000-participant standardization...\n');
    shuffleTic = tic;
    
    % Initial random shuffle
    shuff = rawList(randperm(actualTrials));
    
    % The "Check-and-Swap" Logic
    maxPasses = 100; 
    for pass = 1:maxPasses
        swapsInPass = 0;
        for i = 2:actualTrials
            % Check if Subject at (i) is same as Subject at (i-1)
            if strcmp(shuff(i).subID, shuff(i-1).subID)
                % Look for a valid swap candidate later in the list
                for j = randperm(actualTrials)
                    % Swap logic: Check if shuff(j) fits at (i) AND shuff(i) fits at (j)
                    targetSub = shuff(j).subID;
                    currentSub = shuff(i).subID;
                    
                    % Boundary conditions for index j
                    prevJ = ""; if j > 1, prevJ = shuff(j-1).subID; end
                    nextJ = ""; if j < actualTrials, nextJ = shuff(j+1).subID; end
                    % Boundary for index i
                    nextI = ""; if i < actualTrials, nextI = shuff(i+1).subID; end
                    
                    if ~strcmp(targetSub, shuff(i-1).subID) && ... % Fits new i
                       ~strcmp(targetSub, nextI) && ...            % Fits new i
                       ~strcmp(currentSub, prevJ) && ...           % Fits new j
                       ~strcmp(currentSub, nextJ) && ...           % Fits new j
                       i ~= j
                   
                        % Perform Surgical Swap
                        temp = shuff(i);
                        shuff(i) = shuff(j);
                        shuff(j) = temp;
                        swapsInPass = swapsInPass + 1;
                        break;
                    end
                end
            end
        end
        if swapsInPass == 0, break; end % List is perfectly clean
        fprintf('    Pass %d: Fixed %d subject repeats.\n', pass, swapsInPass);
    end
    
    masterTrials = shuff;
    fprintf('[Milestone 3] Smart Shuffle Complete. Time: %.4f sec.\n', toc(shuffleTic));

    %% --- MILESTONE 4: EXPORT MASTER LIST ---
    fprintf('\n[Milestone 4] Saving MASTER_EXPERIMENT_DATA.mat...\n');
    saveTic = tic;
    save(fullfile(save_path, 'MASTER_EXPERIMENT_DATA.mat'), 'masterTrials', '-v7.3');
    
    fprintf('Done! Total Process Time: %.2f seconds.\n', toc(totalTic));
    fprintf('======================================================\n');
end