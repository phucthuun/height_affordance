function masterTrials = stimuli_preload_simple(stimDir, saveDir, numBlocks)
    % stimuli_preload_simple - Loads all images, extracts metadata, 
    % and saves blocks to a .mat file with no pairing or constraints.
    
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
            stimBase(validCount).exemplar        = string(t{7});
        end
    end
    
    fprintf('Found %d valid images matching pattern.\n', length(stimBase));

    %% --- STEP 2: PRELOAD PIXELS ---
    fprintf('Step 2: Pre-loading image pixel data...\n');
    for i = 1:length(stimBase)
        stimBase(i).imageData = imread(fullfile(stimDir, stimBase(i).name));
        if mod(i, 50) == 0, fprintf('Loaded %d/%d...\n', i, length(stimBase)); end
    end

    %% --- STEP 3: CREATE BLOCKS (Simple Shuffle) ---
    masterTrials = cell(1, numBlocks); 
    for b = 1:numBlocks
        fprintf('Generating Block %d (Random Shuffle)...\n', b);
        % Just a standard shuffle with no constraints
        masterTrials{b} = stimBase(randperm(length(stimBase)));
    end

    %% --- STEP 4: SAVE ---
    fprintf('\nStep 4: Saving to stimuli_all.mat...\n');
    save(fullfile(saveDir, 'stimuli.mat'), 'masterTrials', '-v7.3');
    fprintf('Finished! Total time: %.2f seconds.\n', toc(totalTic));
end