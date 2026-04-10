function masterTrials = crop_stimuli_randomize_preload(stimDir, saveDir)
    
totalTic = tic;

    %% --- STEP 1: EXTRACT NAMES & METADATA ---
    fprintf('Step 1: Extracting Metadata...\n');
    allFiles = dir(fullfile(stimDir, '*.jpg'));
    
    tempStim = struct('name', {}, 'cam', {}, 'scenario', {}, ...
                      'posture', {}, 'stance', {}, 'laterality', {}, 'exemplar', {});
    
    % Pattern updated for: cropped_cam-155_scenario-fight_posture-lowered_stance-145_laterality-feet-equal_exemplar-1.jpg
    pattern = 'cropped-mat_cam-(\d+)_scenario-([\w-]+)_posture-([\w-]+)_stance-(\d+)_laterality-([\w-]+)_exemplar-(\d+)';
    
    count = 1;
    for i = 1:length(allFiles)
        tokens = regexp(allFiles(i).name, pattern, 'tokens');
        if ~isempty(tokens)
            t = tokens{1};
            tempStim(count).name       = allFiles(i).name;
            tempStim(count).cam        = str2double(t{1});
            tempStim(count).scenario   = string(t{2}); 
            tempStim(count).posture    = string(t{3}); 
            tempStim(count).stance     = str2double(t{4});
            tempStim(count).laterality = string(t{5}); 
            tempStim(count).exemplar   = string(t{6});
            count = count + 1;
        end
    end

    %% --- STEP 2: PAIRING (Fight-Neutral via Cam Number) ---
    fprintf('Step 2: Pairing Fight images with Neutral baselines (Matching CAM)...\n');
    
    allScenarios = [tempStim.scenario];
    allCams      = [tempStim.cam];
    allExemplars = [tempStim.exemplar];
    
    fgtIdx = find(allScenarios == "fight"); % Finding all fight images
    rawPairs = [];
    pairCount = 1;
    
    for i = 1:length(fgtIdx)
        f = tempStim(fgtIdx(i));
        
        % Match by CAM and EXEMPLAR to ensure the baseline is identical context
        nIdx = find(allScenarios == "neutral" & ...
                    allCams      == f.cam);
        
        if ~isempty(nIdx)
            rawPairs(pairCount).cam        = f.cam;
            rawPairs(pairCount).stance     = f.stance;
            rawPairs(pairCount).laterality = f.laterality;
            rawPairs(pairCount).exemplar   = f.exemplar;
            rawPairs(pairCount).neuName    = tempStim(nIdx(1)).name;
            rawPairs(pairCount).fgtName    = f.name;
            pairCount = pairCount + 1;
        end
    end

    %% --- STEP 3: HIERARCHICAL SORTING (Cam High > Stance High > Random) ---
    fprintf('Step 3: Sorting by Cam (Desc), Stance (Desc), then Randomizing internal groups...\n');
    
    % Ensure rawPairs is a column vector to satisfy struct2table
    if isempty(rawPairs)
        error('No pairs were created. Check if Cam/Exemplar matches exist for Neutral and Fight.');
    end
    
    % Fix the shape: Make sure it's a 1xN or Nx1 array
    rawPairs = reshape(rawPairs, [], 1); 
    
    % Convert struct to table
    T = struct2table(rawPairs);
    
    % 1. Add a random column for the "everything else randomized" part
    T.randVal = rand(height(T), 1);
    
    % 2. Sort: Cam (Descending), Stance (Descending), then the Random Column (Ascending)
    T = sortrows(T, {'cam', 'stance', 'randVal'}, {'descend', 'descend', 'ascend'});
    
    % Convert back to struct for the rest of your PTB script
    masterTrials = table2struct(T);
    
    %% --- STEP 4: ACTUAL IMAGE LOADING ---
    fprintf('Step 4: Loading Images into RAM...\n');
    for t = 1:length(masterTrials)
        masterTrials(t).neuData = imread(fullfile(stimDir, masterTrials(t).neuName));
        masterTrials(t).fgtData = imread(fullfile(stimDir, masterTrials(t).fgtName));
        
        if mod(t, 20) == 0, fprintf('    Loaded %d/%d trials...\n', t, length(masterTrials)); end
    end
    
    %% --- STEP 5: SAVE ---
    save(fullfile(saveDir, 'MASTER_EXPERIMENT_DATA_crop.mat'), 'masterTrials', '-v7.3');
    fprintf('Finished! Cam hierarchy established in %.2f seconds.\n', toc(totalTic));
end