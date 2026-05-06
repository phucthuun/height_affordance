function masterTrials = stimuli_randomize_preload(stimDir, saveDir)

    totalTic = tic;
    
    %% --- STEP 1: EXTRACT NAMES & METADATA ---
    fprintf('Step 1: Extracting Metadata...\n');
    allFiles = dir(fullfile(stimDir, '*.jpg'));
    
    % Initialize an empty struct with specific fields to avoid indexing errors
    tempStim = struct('name', {}, 'subID', {}, 'stance', {}, ...
                      'laterality', {}, 'scenario', {}, 'posture', {}, 'exemplar', {});
    
    % Updated Regex to match your specific filename format
    pattern = 'cropped-mat_sub-([\w\d]+)_cam-(\d+)_scenario-(\w+)_posture-(\w+)_stance-(\d+)_laterality-([\w-]+)_exemplar-(\d+)';
    
    count = 1;
    for i = 1:length(allFiles)
        tokens = regexp(allFiles(i).name, pattern, 'tokens');
        if ~isempty(tokens)
            t = tokens{1};
            tempStim(count).name       = allFiles(i).name;
            tempStim(count).subID      = string(t{1});
            tempStim(count).cam        = str2double(t{2});
            tempStim(count).scenario   = string(t{3}); % Cast to string
            tempStim(count).posture    = string(t{4}); % Cast to string
            tempStim(count).stance     = str2double(t{5});
            tempStim(count).laterality = string(t{6}); % Cast to string
            tempStim(count).exemplar   = string(t{7});
            count = count + 1;
        end
    end

    if isempty(tempStim)
        error('Regex Failed. No files matched. Check if you are looking for .png or .jpg');
    end

    %% --- STEP 2: PAIRING (Capturing All Metadata) ---
    fprintf('Step 2: Pairing Filenames & Metadata...\n');
    
    % Convert fields to arrays for speed
    allScenarios = [tempStim.scenario];
    allSubs      = [tempStim.subID];
    allExemplars = [tempStim.exemplar];
    
    % Find all Fight images
    fgtIdx = find(allScenarios == "fight");
    
    % Pre-allocate the struct with all requested fields
    rawPairs = struct('subID', {}, ...
                      'neuName', {}, 'fgtName', {}, ...
                      'cam', {}, 'posture', {}, 'stance', {}, ...
                      'laterality', {}, 'exemplar', {});
    
    pairCount = 1;
    for i = 1:length(fgtIdx)
        f = tempStim(fgtIdx(i));
        
        % Find Neutral match (Subject + Exemplar)
        nMatch = find(allScenarios == "neutral" & ...
                      allSubs      == f.subID & ...
                      allExemplars == f.exemplar);
        
        if ~isempty(nMatch)
            % Fill the table with the Fight image's specific info
            rawPairs(pairCount).subID      = f.subID;
            rawPairs(pairCount).neuName    = tempStim(nMatch(1)).name;
            rawPairs(pairCount).fgtName    = f.name;
            
            % Metadata specific to the Fight stimulus
            rawPairs(pairCount).cam        = f.cam;
            rawPairs(pairCount).posture    = f.posture;
            rawPairs(pairCount).stance     = f.stance;
            rawPairs(pairCount).laterality = f.laterality;
            rawPairs(pairCount).exemplar   = f.exemplar;
            
            pairCount = pairCount + 1;
        end
    end
    
    %% --- STEP 3: SMART RANDOMIZATION (Triple Constraints) ---
    fprintf('Step 3: Randomizing (No Sub-Pairs, No Stance Triplets, No Lat Triplets)...\n');
    n = length(rawPairs);
    shuff = rawPairs(randperm(n)); % Initial random shuffle
    
    maxPasses = 500; % Increased passes to solve tighter constraints
    for pass = 1:maxPasses
        swapsInPass = 0;
        for i = 1:n
            % --- 1. Identify Violations ---
            % Rule A: No 2 consecutive SubIDs (as requested previously)
            badSub = (i > 1 && strcmp(shuff(i).subID, shuff(i-1).subID));
            
            % Rule B: No 3 consecutive Stances
            badStance = (i > 2 && shuff(i).stance == shuff(i-1).stance && ...
                                 shuff(i).stance == shuff(i-2).stance);
                             
            % Rule C: No 3 consecutive Lateralities
            badLat = (i > 2 && strcmp(shuff(i).laterality, shuff(i-1).laterality) && ...
                             strcmp(shuff(i).laterality, shuff(i-2).laterality));
            
            % --- 2. Resolve Violations ---
            if badSub || badStance || badLat
                % Look for a candidate to swap with
                for j = randperm(n)
                    candidate = shuff(j);
                    
                    % Check if Candidate fits at position 'i'
                    % (Must not create a Sub-pair or Stance/Lat triplet at i)
                    fitAtI = true;
                    if i > 1 && strcmp(candidate.subID, shuff(i-1).subID), fitAtI = false; end
                    if i > 2 && (candidate.stance == shuff(i-1).stance && ...
                                 candidate.stance == shuff(i-2).stance), fitAtI = false; end
                    if i > 2 && (strcmp(candidate.laterality, shuff(i-1).laterality) && ...
                                 strcmp(candidate.laterality, shuff(i-2).laterality)), fitAtI = false; end
                    
                    % Check if Candidate fits with the NEXT items (i+1, i+2)
                    if i < n && strcmp(candidate.subID, shuff(i+1).subID), fitAtI = false; end
                    
                    % If it's a valid swap, execute it
                    if fitAtI && i ~= j
                        temp = shuff(i);
                        shuff(i) = shuff(j);
                        shuff(j) = temp;
                        swapsInPass = swapsInPass + 1;
                        break; % Exit inner loop, move to next i
                    end
                end
            end
        end
        
        % If we made it through the whole list with 0 swaps, the list is perfect
        if swapsInPass == 0
            fprintf('    Shuffle successful on pass %d.\n', pass);
            break; 
        end
    end

    if swapsInPass > 0
        warning('Could not perfectly resolve all constraints after %d passes.', maxPasses);
    end

    
    %% --- STEP 4: ACTUAL IMAGE LOADING (Heavy) ---
    fprintf('Step 4: Loading Images into RAM...\n');
    masterTrials = shuff;
    for t = 1:length(masterTrials)
        % Load Neutral
        masterTrials(t).neuData = imread(fullfile(stimDir, masterTrials(t).neuName));
        % Load Fight
        masterTrials(t).fgtData = imread(fullfile(stimDir, masterTrials(t).fgtName));
        
        if mod(t, 10) == 0, fprintf('    Loaded %d/%d trials...\n', t, length(masterTrials)); end
    end

    %% --- STEP 5: SAVE TO .MAT ---
    fprintf('Step 5: Saving to .mat file...\n');
    save(fullfile(saveDir, 'MASTER_EXPERIMENT_DATA_randomize_3constraints.mat'), 'masterTrials', '-v7.3');
    fprintf('Finished in %.2f seconds.\n', toc(totalTic));
end