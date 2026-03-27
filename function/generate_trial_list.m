function masterTrials = generate_trial_list(stimuli, save_path)
    % Start Global Timer
    totalTic = tic;
    fprintf('\n======================================================\n');
    fprintf('STARTING MASTER TRIAL GENERATION\n');
    fprintf('Timestamp: %s\n', datestr(now, 'HH:MM:SS'));
    fprintf('======================================================\n');

    %% --- MILESTONE 1: FILTERING TARGETS ---
    fgtIdx = find([stimuli.scenario] == "fight" & [stimuli.posture] == "lowered");
    numFight = length(fgtIdx);
    rawList = [];
    
    fprintf('[Milestone 1] Found %d Fight-Lowered stimuli.\n', numFight);

    %% --- MILESTONE 2: PAIRING NEUTRAL & FIGHT ---
    matchTic = tic;
    count = 1;
    for i = 1:numFight
        f = stimuli(fgtIdx(i));
        nIdx = find([stimuli.subID] == f.subID & ...
                    [stimuli.scenario] == "neutral" & ...
                    [stimuli.exemplar] == f.exemplar);
        
        if ~isempty(nIdx)
            rawList(count).subID      = f.subID;
            rawList(count).stance     = f.stance;      % Needed for Shuffle
            rawList(count).laterality = f.laterality;  % Needed for Shuffle
            rawList(count).neuData    = stimuli(nIdx).imageData;
            rawList(count).fgtData    = f.imageData;
            rawList(count).info       = sprintf('Sub: %s | Stance: %d | Lat: %s', ...
                                         f.subID, f.stance, f.laterality);
            count = count + 1;
        end
    end
    
    actualTrials = length(rawList);
    fprintf('[Milestone 2] Pairing Complete. Total Trials: %d.\n', actualTrials);

    %% --- MILESTONE 3: SMART SHUFFLE (CONSTRAINED) ---
    % Rules: 
    % 1. No 2 consecutive SubIDs (Pairs)
    % 2. No 3 consecutive Stances (Triplets)
    % 3. No 3 consecutive Lateralities (Triplets)
    
    fprintf('\n[Milestone 3] Performing Smart Shuffle (SubID pairs, Stance/Lat triplets)...\n');
    shuffleTic = tic;
    shuff = rawList(randperm(actualTrials));
    
    maxPasses = 200; % Increased passes for stricter constraints
    for pass = 1:maxPasses
        swapsInPass = 0;
        for i = 1:actualTrials
            
            % --- Check Constraints at Index i ---
            badSub = false; badStance = false; badLat = false;
            
            % 1. Check SubID Pairs (i vs i-1)
            if i > 1 && strcmp(shuff(i).subID, shuff(i-1).subID)
                badSub = true;
            end
            
            % 2. Check Stance Triplets (i vs i-1 AND i-2)
            if i > 2 && (shuff(i).stance == shuff(i-1).stance && shuff(i).stance == shuff(i-2).stance)
                badStance = true;
            end
            
            % 3. Check Laterality Triplets (i vs i-1 AND i-2)
            if i > 2 && (strcmp(shuff(i).laterality, shuff(i-1).laterality) && ...
                         strcmp(shuff(i).laterality, shuff(i-2).laterality))
                badLat = true;
            end

            % If any rule is broken, find a swap candidate
            if badSub || badStance || badLat
                for j = randperm(actualTrials)
                    candidate = shuff(j);
                    
                    % Check if Candidate fits at 'i'
                    % (Must not break SubID pair OR Stance/Lat triplet rules at index i)
                    fitAtI = true;
                    if i > 1 && strcmp(candidate.subID, shuff(i-1).subID), fitAtI = false; end
                    if i < actualTrials && strcmp(candidate.subID, shuff(i+1).subID), fitAtI = false; end
                    
                    if i > 2 && (candidate.stance == shuff(i-1).stance && candidate.stance == shuff(i-2).stance), fitAtI = false; end
                    if i > 2 && (strcmp(candidate.laterality, shuff(i-1).laterality) && ...
                                 strcmp(candidate.laterality, shuff(i-2).laterality)), fitAtI = false; end
                    
                    % Check if Current(i) fits at 'j'
                    % (Simplified check for j to keep speed up)
                    fitAtJ = true;
                    if j > 1 && strcmp(shuff(i).subID, shuff(j-1).subID), fitAtJ = false; end
                    
                    if fitAtI && fitAtJ && i ~= j
                        % Swap
                        temp = shuff(i);
                        shuff(i) = shuff(j);
                        shuff(j) = temp;
                        swapsInPass = swapsInPass + 1;
                        break;
                    end
                end
            end
        end
        if swapsInPass == 0, break; end 
        fprintf('    Pass %d: Fixed %d violations.\n', pass, swapsInPass);
    end
    
    masterTrials = shuff;
    fprintf('[Milestone 3] Smart Shuffle Complete. Time: %.4f sec.\n', toc(shuffleTic));

    %% --- MILESTONE 4: EXPORT ---
    save(fullfile(save_path, 'MASTER_EXPERIMENT_DATA_Rand2.mat'), 'masterTrials', '-v7.3');
    fprintf('Done! Total Time: %.2f seconds.\n', toc(totalTic));
end