function masterTrials = stimuli_randomize_preload(stimDir, numBlocks)
    
mat_file = fullfile(stimDir, 'stimuli.mat');
if exist(mat_file, 'file')
    fprintf('Found existing randomized list. Loading...\n');
    data = load(mat_file, 'masterTrials'); 
    masterTrials = data.masterTrials;
else
    fprintf('No randomized list found. Commencing metadata extraction and loading...\n');

    totalTic = tic;
    
    %% --- STEP 1: EXTRACT NAMES & METADATA ---
    fprintf('Step 1: Extracting Metadata...\n');
    allFiles = dir(fullfile(stimDir, '*.jpg'));
    
    tempStim = struct('name', {}, 'subID', {}, 'stance', {}, ...
                      'laterality', {}, 'scenario', {}, 'posture', {}, 'exemplar', {}, 'cam', {});
    
    pattern = 'cropped-mat_sub-([\w\d]+)_cam-(\d+)_scenario-(\w+)_posture-(\w+)_stance-(\d+)_laterality-([\w-]+)_exemplar-(\d+)';
    
    count = 1;
    for i = 1:length(allFiles)
        tokens = regexp(allFiles(i).name, pattern, 'tokens');
        if ~isempty(tokens)
            t = tokens{1};
            tempStim(count).name       = allFiles(i).name;
            tempStim(count).subID      = string(t{1});
            tempStim(count).cam        = str2double(t{2});
            tempStim(count).scenario   = string(t{3}); 
            tempStim(count).posture    = string(t{4}); 
            tempStim(count).stance     = str2double(t{5});
            tempStim(count).laterality = string(t{6}); 
            tempStim(count).exemplar   = string(t{7});
            count = count + 1;
        end
    end
    
    if isempty(tempStim), error('No files matched the pattern.'); end

    %% --- STEP 2: PAIRING ---
    fprintf('Step 2: Pairing Fight/Neutral sets...\n');
    allScenarios = [tempStim.scenario];
    allSubs      = [tempStim.subID];
    allExemplars = [tempStim.exemplar];
    fgtIdx       = find(allScenarios == "fight");
    
    rawPairs = []; 
    pairCount = 1;
    for i = 1:length(fgtIdx)
        f = tempStim(fgtIdx(i));
        nMatch = find(allScenarios == "neutral" & allSubs == f.subID & allExemplars == f.exemplar);
        
        if ~isempty(nMatch)
            rawPairs(pairCount).subID      = f.subID;
            rawPairs(pairCount).neuName    = tempStim(nMatch(1)).name;
            rawPairs(pairCount).fgtName    = f.name;
            rawPairs(pairCount).cam        = f.cam;
            rawPairs(pairCount).posture    = f.posture;
            rawPairs(pairCount).stance     = f.stance;
            rawPairs(pairCount).laterality = f.laterality;
            rawPairs(pairCount).exemplar   = f.exemplar;
            pairCount = pairCount + 1;
        end
    end

    %% --- STEP 3 & 4: GENERATE 4 UNIQUE BLOCKS ---
    numBlocks = numBlocks;
    masterTrials = cell(1, numBlocks); 
    
    for b = 1:numBlocks
        fprintf('\n--- Generating Block %d ---\n', b);
        
        % Smart Randomization Loop
        n = length(rawPairs);
        shuff = rawPairs(randperm(n)); 
        maxPasses = 500;
        
        for pass = 1:maxPasses
            swapsInPass = 0;
            for i = 1:n
                badSub = (i > 1 && strcmp(shuff(i).subID, shuff(i-1).subID));
                badStance = (i > 2 && shuff(i).stance == shuff(i-1).stance && ...
                                     shuff(i).stance == shuff(i-2).stance);
                badLat = (i > 2 && strcmp(shuff(i).laterality, shuff(i-1).laterality) && ...
                                 strcmp(shuff(i).laterality, shuff(i-2).laterality));
                
                if badSub || badStance || badLat
                    for j = randperm(n)
                        candidate = shuff(j);
                        fitAtI = true;
                        if i > 1 && strcmp(candidate.subID, shuff(i-1).subID), fitAtI = false; end
                        if i > 2 && (candidate.stance == shuff(i-1).stance && candidate.stance == shuff(i-2).stance), fitAtI = false; end
                        if i > 2 && (strcmp(candidate.laterality, shuff(i-1).laterality) && strcmp(candidate.laterality, shuff(i-2).laterality)), fitAtI = false; end
                        if i < n && strcmp(candidate.subID, shuff(i+1).subID), fitAtI = false; end
                        
                        if fitAtI && i ~= j
                            temp = shuff(i); shuff(i) = shuff(j); shuff(j) = temp;
                            swapsInPass = swapsInPass + 1;
                            break; 
                        end
                    end
                end
            end
            if swapsInPass == 0, break; end
        end

        % Load Images for this specific block shuffle
        fprintf('Loading images for Block %d...\n', b);
        for t = 1:length(shuff)
            shuff(t).neuData = imread(fullfile(stimDir, shuff(t).neuName));
            shuff(t).fgtData = imread(fullfile(stimDir, shuff(t).fgtName));
        end
        
        masterTrials{b} = shuff;
    end

    %% --- STEP 5: SAVE ---
    fprintf('\nStep 5: Saving all blocks to .mat file...\n');
    save(fullfile(stimDir, 'stimuli.mat'), 'masterTrials', '-v7.3');
    fprintf('Finished! Total time: %.2f seconds.\n', toc(totalTic));

end


end