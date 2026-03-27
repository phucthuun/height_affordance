function stimuli = preload_image(stim_path, save_path)
    startTime = tic; % Global start timer
    
    % 1. Get all JPG files
    allimg = dir(fullfile(stim_path, '*.jpg'));
    numfiles = length(allimg);
    if numfiles == 0, error('No files found in %s', stim_path); end

    % 2. Preallocate
    stimuli(1:numfiles) = struct('path', [], 'name', [], 'subID', [], ...
        'scenario', [], 'posture', [], 'stance', [], 'laterality', [], ...
        'exemplar', [], 'imageData', []);
    
    fprintf('\n[Milestone 1] Starting Preload of %d images at %s\n', numfiles, datestr(now, 'HH:MM:SS'));
    
    preloadTic = tic;
    for k = 1:numfiles
        stimuli(k).path = fullfile(allimg(k).folder, allimg(k).name);
        stimuli(k).name = allimg(k).name;
        
        % Regex Extraction
        stimuli(k).subID = string(regexp(stimuli(k).name, 'sub-[^_]+', 'match', 'once'));
        stimuli(k).scenario = string(regexp(stimuli(k).name, 'scenario-([^_]+)', 'tokens', 'once'));
        stimuli(k).posture = string(regexp(stimuli(k).name, 'posture-([^_]+)', 'tokens', 'once'));
        stimuli(k).stance = str2double(string(regexp(stimuli(k).name, 'stance-(\d+)', 'tokens', 'once')));
        stimuli(k).laterality = string(regexp(stimuli(k).name, 'laterality-([^_]+)', 'tokens', 'once'));
        stimuli(k).exemplar = str2double(string(regexp(stimuli(k).name, 'exemplar-(\d+)', 'tokens', 'once')));
        
        % Read pixels to RAM
        stimuli(k).imageData = imread(stimuli(k).path);
        
        if mod(k,50) == 0
            fprintf('... Loaded %d/%d (Elapsed: %.1f sec)\n', k, numfiles, toc(preloadTic));
        end
    end
    fprintf('[Milestone 2] Preloading finished. Total load time: %.2f seconds.\n', toc(preloadTic));

    % --- 3. SIZE ESTIMATION & DISK CHECK ---
    sampleImg = stimuli(1).imageData;
    [h, w, c] = size(sampleImg);
    bytesPerImg = h * w * c; 
    estTotalGB = (bytesPerImg * numfiles) / (1024^3);
    
    fprintf('\n--- Resource Report (%s) ---\n', datestr(now, 'HH:MM:SS'));
    fprintf('Resolution: %d x %d | Est. File Size: %.2f GB\n', w, h, estTotalGB);
    
    % Check Disk Space
    try
        fileSys = java.io.File(save_path);
        freeSpaceGB = fileSys.getFreeSpace / (1024^3);
        fprintf('Target Drive Free Space: %.2f GB\n', freeSpaceGB);
    catch
        fprintf('Could not verify disk space on network path.\n');
        freeSpaceGB = Inf;
    end

    % 4. SAVE DECISION
    reply = input('\nDo you want to proceed with saving? (y/n): ', 's');
    
    if strcmpi(reply, 'y')
        if freeSpaceGB < estTotalGB
            warning('Estimated size (%.2f GB) exceeds free space (%.2f GB)!', estTotalGB, freeSpaceGB);
        end
        
        fprintf('\n[Milestone 3] Starting Save to .mat at %s\n', datestr(now, 'HH:MM:SS'));
        fprintf('Note: Saving %.2f GB over network can take several minutes...\n', estTotalGB);
        
        saveTic = tic;
        save(fullfile(save_path, 'preloaded_stimuli_XXX.mat'), 'stimuli', '-v7.3');
        
        saveDuration = toc(saveTic);
        fprintf('[Milestone 4] Save complete at %s.\n', datestr(now, 'HH:MM:SS'));
        fprintf('Save Duration: %.2f seconds (Avg Speed: %.2f MB/s)\n', ...
            saveDuration, (estTotalGB*1024)/saveDuration);
    else
        disp('Save cancelled. Data remains in variable "stimuli".');
    end
    
    fprintf('\nTotal Script Execution Time: %.2f seconds.\n', toc(startTime));
end