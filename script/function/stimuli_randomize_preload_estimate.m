function masterTrials = stimuli_randomize_preload_estimate(stimDir, saveDir, numBlocks)
    % stimuli_preload_simple - Loads all images, extracts metadata, 
    % and saves blocks to a .mat file with NO CONSECUTIVE DUPLICATE subIDs.
    
    totalTic = tic;
    if ~exist(saveDir, 'dir'), mkdir(saveDir); end
    
    %% --- STEP 1: EXTRACT NAMES & METADATA ---
    fprintf('Step 1: Extracting Metadata for all images...\n');
    allFiles = dir(fullfile(stimDir, '*.jpg'));
    nFiles = length(allFiles);
    
    if nFiles == 0, error('No .jpg files found in: %s', stimDir); end
    
    % Pre-allocate stimulus structure
    stimBase = struct('name', {}, 'subID', {}, 'cam', {}, 'scenario', {}, ...
                      'posture', {}, 'stance', {}, 'laterality', {}, 'exemplar', {});
    
    pattern = 'face_sub-([\w\d]+)_cam-(\d+)_scenario-(\w+)_posture-(\w+)_stance-(\d+)_laterality-([\w-]+)_exemplar-(\d+)';
    
    validCount = 0;
    for i = 1:nFiles
        tokens = regexp(allFiles(i).name, pattern, 'tokens');
        if ~isempty(tokens)
            validCount = validCount + 1;
            t = tokens{1};
            stimBase(validCount).name       = allFiles(i).name;
            stimBase(validCount).subID      = string(t{1});
            stimBase(validCount).cam        = str2double(t{2});
            stimBase(validCount).scenario   = string(t{3}); 
            stimBase(validCount).posture    = string(t{4}); 
            stimBase(validCount).stance     = str2double(t{5});
            stimBase(validCount).laterality = string(t{6}); 
            stimBase(validCount).exemplar   = string(t{7});
        end
    end
    
    fprintf('Found %d valid images matching pattern.\n', length(stimBase));
    
    %% --- STEP 2: PRELOAD PIXELS ---
    fprintf('Step 2: Pre-loading image pixel data...\n');
    for i = 1:length(stimBase)
        stimBase(i).imageData = imread(fullfile(stimDir, stimBase(i).name));
        if mod(i, 50) == 0, fprintf('Loaded %d/%d...\n', i, length(stimBase)); end
    end
    
    %% --- STEP 3: CREATE BLOCKS (No Consecutive Duplicates) ---
    masterTrials = cell(1, numBlocks); 
    nStim = length(stimBase);
    
    % Edge-case validation
    [uniqueIDs, ~, idx] = unique([stimBase.subID]);
    maxCount = max(histcounts(idx, 1:length(uniqueIDs)+1));
    if maxCount > ceil(nStim / 2)
        error('Mathematical Impossibility: One subID represents more than half of the images (%d/%d). It is impossible to avoid consecutive trials.', maxCount, nStim);
    end
    
    for b = 1:numBlocks
        fprintf('Generating Block %d (No Consecutive subIDs)...\n', b);
        
        isValid = false;
        attempts = 0;
        maxAttempts = 5000; % Break potential infinite loops if constraints are tight
        
        while ~isValid && attempts < maxAttempts
            attempts = attempts + 1;
            
            % Generate random permutation
            shuffledIdx = randperm(nStim);
            shuffledBlock = stimBase(shuffledIdx);
            
            % Extract the order of IDs for this permutation
            blockIDs = [shuffledBlock.subID];
            
            % Check if any adjacent elements are identical
            % (Returns a logical array where 1 means trial(i) == trial(i+1))
            isDuplicate = (blockIDs(1:end-1) == blockIDs(2:end));
            
            if ~any(isDuplicate)
                isValid = true;
                masterTrials{b} = shuffledBlock;
            end
        end
        
        if ~isValid
            error('Could not find a valid trial distribution for Block %d within %d attempts. Try adjusting your stimulus pool.', b, maxAttempts);
        end
    end
    
    %% --- STEP 4: SAVE ---
    fprintf('\nStep 4: Saving to stimuli.mat...\n');
    save(fullfile(saveDir, 'stimuli.mat'), 'masterTrials', '-v7.3');
    fprintf('Finished! Total time: %.2f seconds.\n', toc(totalTic));
end