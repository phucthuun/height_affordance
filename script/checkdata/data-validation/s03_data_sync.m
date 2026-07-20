%% Unified BIDS Multi-Modal Synchronization & Slicing Pipeline
% Description: Automates extraction, timeline synchronization, and trial-slicing
%              across Xsens kinematics, Loadsol dynamics, raw Dual-View videos, 
%              and LSL global tracking streams. Exports frame-synchronized 
%              BIDS derivatives (.mat, .json, .tsv, and 3 MP4 video clips per trial).
% clear; clc; close all;

%% 0. BIDS Paths & Multi-Modal Run Selection
fprintf('============ BIDS UNIFIED MULTI-MODAL SYNCHRONIZER & SLICER ============ \n');
% BASE_LOC        = '\\mpib-berlin.mpg.de\Share\Projects\1223-xplo-judo\private\10_Data\sourcedata';
% DERIVATIVES_LOC = '\\mpib-berlin.mpg.de\Share\Projects\1223-xplo-judo\private\10_Data\derivatives';
BASE_LOC        = 'C:\Data\Research\10_Data\sourcedata';
DERIVATIVES_LOC = 'C:\Data\Research\10_Data\derivatives';
PIPELINE_NAME   = 'syncdata';
PIPELINE_ROOT   = fullfile(DERIVATIVES_LOC, PIPELINE_NAME);

% --- Request Processing Target Metadata via Dialog Box ---
prompt = {'Enter Subject ID (e.g., MH9HXJ):', 'Enter Session ID (e.g., S001):', 'Enter Run ID (e.g., 001):', 'Enter Task Name:', 'Trim buffer before TrialOffset (s):'};
dlgtitle = 'Data Pipeline Target Selection';
dims = [1 50];
definput = {'MH9HXJ', 'S001', '001', 'heightaffordance', '3.0'};
userInput = inputdlg(prompt, dlgtitle, dims, definput);
if isempty(userInput); error('Execution cancelled by user.'); end

subLabel = regexprep(userInput{1}, '^sub-', '');
sesLabel = regexprep(userInput{2}, '^ses-', '');
runID    = sprintf('%03d', str2double(userInput{3}));
taskName = userInput{4};
PRE_OFFSET_REDUCTION = str2double(userInput{5});

subID = ['sub-' subLabel]; sesID = ['ses-' sesLabel];

% --- Establish Direct Absolute BIDS Workspace Directories ---
MOCAP_DIR      = fullfile(BASE_LOC, subID, sesID, 'motion');
FORCE_DIR      = fullfile(BASE_LOC, subID, sesID, 'force');
VIDEO_DIR      = fullfile(BASE_LOC, subID, sesID, 'video');
LSL_GLOBAL_DIR = fullfile(BASE_LOC, subID, sesID, 'lslglobal');

OUTPUT_MOTION_DIR = fullfile(PIPELINE_ROOT, subID, sesID, 'motion');
OUTPUT_VIDEO_DIR  = fullfile(PIPELINE_ROOT, subID, sesID, 'video');

if ~exist(OUTPUT_MOTION_DIR, 'dir'), mkdir(OUTPUT_MOTION_DIR); end
if ~exist(OUTPUT_VIDEO_DIR, 'dir'), mkdir(OUTPUT_VIDEO_DIR); end

% --- Identify Multi-Modal File Dependencies ---
search_prefix  = sprintf('%s_%s_task-%s_run-%s', subID, sesID, taskName, runID);
fullXdfPath    = fullfile(LSL_GLOBAL_DIR, [search_prefix '_lslglobal.xdf']);
mvnxDirStruct  = dir(fullfile(MOCAP_DIR, [search_prefix '*.mvnx']));
forceDirStruct = dir(fullfile(FORCE_DIR, [search_prefix '*.txt']));

if ~exist(fullXdfPath, 'file'), error('Missing master timeline trace XDF: %s', fullXdfPath); end
if isempty(mvnxDirStruct), error('Missing reprocessed Xsens trajectory file (.mvnx) inside: %s', MOCAP_DIR); end
if isempty(forceDirStruct), error('Missing Loadsol sensor text log (.txt) inside: %s', FORCE_DIR); end

fullMvnxPath  = fullfile(MOCAP_DIR,  mvnxDirStruct(1).name);
fullForcePath = fullfile(FORCE_DIR, forceDirStruct(1).name);

% --- Automatically Locate Available Video Views ---
view1Struct = dir(fullfile(VIDEO_DIR, [search_prefix '*acq-SideView_beh.avi']));
view2Struct = dir(fullfile(VIDEO_DIR, [search_prefix '*acq-UpperView_beh.avi']));
has_video1 = ~isempty(view1Struct); has_video2 = ~isempty(view2Struct);

% --- Automatically Generate BIDS Dataset Description ---
descJsonPath = fullfile(PIPELINE_ROOT, 'dataset_description.json');
if ~exist(descJsonPath, 'file')
    descStruct = struct(...
        'Name', 'BIDS Video Slicing and Multi-Modal Synchronization Pipeline', ...
        'BIDSVersion', '1.11.1', ...
        'DatasetType', 'derivative', ...
        'GeneratedBy', {{struct('Name', 'MATLAB Integrated Synchronizer Script', 'Version', '3.0.0', ...
                        'Description', 'Unifies and slices kinematics, forces, and multi-view video feeds into BIDS structures.')}}, ...
        'SourceDatasets', {{struct('Description', 'Local project workspace raw BIDS baseline tracking streams')}} ...
    );
    fid = fopen(descJsonPath, 'w'); fprintf(fid, '%s', jsonencode(descStruct, 'PrettyPrint', true)); fclose(fid);
end

%% 1. Ingest & Unpack Data Streams (XDF, MVNX, Loadsol)
fprintf('Loading master XDF file logs...\n');
streams = load_xdf(fullXdfPath);

mIdx = find(cellfun(@(x) contains(x.info.name, 'Trigger', 'IgnoreCase', true) || ...
                        contains(x.info.name, 'Markers', 'IgnoreCase', true), streams), 1);
xIdx = find(cellfun(@(x) contains(x.info.name, {'LinearSegmentKinematicsDatagram1', 'LinearSegmentKinematicsDatagram2'}) ...
    && ~isempty(x.time_series) ...
    && size(x.time_series, 1) == 207, streams), 1);
if isempty(mIdx) || isempty(xIdx); error('Required LSL Marker or Xsens Kinematic stream elements missing inside XDF.'); end

mText = streams{mIdx}.time_series(:); mTime = streams{mIdx}.time_stamps(:);
xData_lsl = double(streams{1,xIdx}.time_series); xTime_lsl = streams{1,xIdx}.time_stamps;
fs_lsl = str2double(streams{xIdx}.info.nominal_srate);
if isnan(fs_lsl) || fs_lsl == 0; fs_lsl = 1 / mean(diff(xTime_lsl)); end

% Optional: Locate Video FrameMarker Streams for exact frame-to-timestamp lookup mapping
sideCamMarkerIdx  = find(cellfun(@(x) strcmp(x.info.name, 'FrameMarker_1'), streams), 1);
upperCamMarkerIdx = find(cellfun(@(x) strcmp(x.info.name, 'FrameMarker_0'), streams), 1);

fprintf('Parsing reprocessed MVNX structural frame elements...\n');
% tree = load_mvnx(fullMvnxPath);
frameRate_mvnx = str2num(tree.metaData.subject_frameRate); numSegments = str2num(tree.metaData.subject_segmentCount); nSamples_mvnx = length(tree.frame);
segmentNames = cell(numSegments, 1); for s = 1:numSegments; segmentNames{s} = tree.segmentData(s).label; end
mvnx_allPos = zeros(numSegments * 3, nSamples_mvnx);
for i = 1:numSegments
    if isfield(tree.segmentData(i), 'position') && ~isempty(tree.segmentData(i).position)
        mvnx_allPos(3*i-2:3*i, :) = tree.segmentData(i).position';
    end
end

fprintf('Parsing Loadsol data metrics...\n');
fid = fopen(fullForcePath, 'r', 'n', 'UTF-8'); allLines = {}; while ~feof(fid); allLines{end+1} = fgetl(fid); end; fclose(fid);
unitRowIdx = find(cellfun(@(l) ischar(l) && contains(l,'Time[secs]'), allLines), 1);
label_cells = strsplit(allLines{unitRowIdx - 1}, '\t', 'CollapseDelimiters', false);
unit_cells  = strsplit(allLines{unitRowIdx}, '\t', 'CollapseDelimiters', false);
max_cols = max(length(label_cells), length(unit_cells)); combined_headers = cell(1, max_cols);
for i = 1:max_cols
    lbl = ''; if i <= length(label_cells); lbl = strtrim(label_cells{i}); end
    unit = ''; if i <= length(unit_cells); unit = strtrim(unit_cells{i}); end
    combined_headers{i} = regexprep(sprintf('%s%d%s', unit, i, lbl), '[\[\]\-:]', '_');
    if isempty(combined_headers{i}), combined_headers{i} = sprintf('Var%d', i); end
end
opts = detectImportOptions(fullForcePath, 'FileType', 'text', 'Delimiter', '\t'); opts.DataLines = [unitRowIdx + 1, Inf]; opts.VariableNamingRule = 'modify';
allDataTab = readtable(fullForcePath, opts); allDataTab.Properties.VariableNames(1:width(allDataTab)) = combined_headers(1:width(allDataTab));
vars = allDataTab.Properties.VariableNames;

name_R_tot   = vars{contains(vars, 'KGW304_R') & ~contains(vars, 'lateral') & ~contains(vars, 'medial') & ~contains(vars, 'heel') & contains(vars, 'Force_N')};
name_L_tot   = vars{contains(vars, 'KGW305_L') & ~contains(vars, 'lateral') & ~contains(vars, 'medial') & ~contains(vars, 'heel') & contains(vars, 'Force_N')};
name_ttl_sig = vars{contains(vars, 'KYN058') & ~contains(vars, 'area') & contains(vars, 'Force_N')};
all_time_indices = find(startsWith(vars, 'Time_secs'));
name_R_time  = vars{all_time_indices(find(all_time_indices < find(strcmp(vars, name_R_tot), 1), 1, 'last'))};
name_L_time  = vars{all_time_indices(find(all_time_indices < find(strcmp(vars, name_L_tot), 1), 1, 'last'))};
name_ttl_time= vars{all_time_indices(find(all_time_indices < find(strcmp(vars, name_ttl_sig), 1), 1, 'last'))};
loadsol.time  = allDataTab.(name_R_time); loadsol.right = allDataTab.(name_R_tot); loadsol.left = allDataTab.(name_L_tot); loadsol.ttl = allDataTab.(name_ttl_sig); loadsol.ttl_t = allDataTab.(name_ttl_time);

%% 2. Chronological Multi-Device Core Cross-Synchronization
fprintf('Synchronizing timelines across systems...\n');
if size(xData_lsl, 1) > size(xData_lsl, 2), xData_lsl = xData_lsl.'; end

lsl_vel  = sqrt(sum(diff(xData_lsl(1:3, :), 1, 2).^2, 1));
mvnx_vel = sqrt(sum(diff(mvnx_allPos(1:3, :), 1, 2).^2, 1));
if frameRate_mvnx ~= fs_lsl
    mvnx_time = (0:length(mvnx_vel)-1) / frameRate_mvnx; mvnx_vel_resampled = resample(mvnx_vel, mvnx_time, fs_lsl);
else
    mvnx_vel_resampled = mvnx_vel;
end
[correlation, Lags] = xcorr(lsl_vel - mean(lsl_vel), mvnx_vel_resampled - mean(mvnx_vel_resampled));
[~, maxIdx] = max(correlation); time_lag_seconds = Lags(maxIdx) / fs_lsl;
mvnx_sync_time = (0:nSamples_mvnx-1)/frameRate_mvnx + (xTime_lsl(1) + time_lag_seconds);
fprintf(' -> Sync Match: HD MVNX stream trace started %.3f seconds relative to Master LSL.\n', time_lag_seconds);

sigMin = min(loadsol.ttl); sigMax = max(loadsol.ttl); thresh = sigMin + 0.4 * (sigMax - sigMin);
pulseIdx = find(([0; diff(loadsol.ttl > thresh)] == 1), 1, 'first');
t0_loadsol = 0; if ~isempty(pulseIdx); t0_loadsol = loadsol.ttl_t(pulseIdx); end
loadsol_aligned_time = loadsol.time - t0_loadsol;

%% 3. Map Continuous Arrays onto Unified Master Timeline
totalMasterSamples = length(xTime_lsl);
master_PosData = zeros(numSegments * 3, totalMasterSamples); master_ForceR = zeros(1, totalMasterSamples); master_ForceL = zeros(1, totalMasterSamples);
for t = 1:totalMasterSamples
    [mvnxDiff, closestMvnxIdx] = min(abs(mvnx_sync_time - xTime_lsl(t)));
    if mvnxDiff > (1 / frameRate_mvnx) * 2; master_PosData(:, t) = NaN; else; master_PosData(:, t) = mvnx_allPos(:, closestMvnxIdx); end
    relative_mTime = xTime_lsl(t) - (xTime_lsl(1) + time_lag_seconds);
    [loadsolDiff, closestLsIdx] = min(abs(loadsol_aligned_time - relative_mTime));
    if loadsolDiff > 0.02; master_ForceR(t) = NaN; master_ForceL(t) = NaN; else; master_ForceR(t) = loadsol.right(closestLsIdx); master_ForceL(t) = loadsol.left(closestLsIdx); end
end

%% 4. Reconstruct & Segment Trial Timelines
trials = struct('trial_id', {}, 'start_sample', {}, 'end_sample', {}, 'start_ts', {}, 'end_ts', {});
trialCount = 0; activeTrialStartTS = [];
for i = 1:numel(mText)
    if strcmp(mText{i}, sprintf('Neutral%d',trialCount+1))
        activeTrialStartTS = mTime(i);
    elseif contains(mText{i}, 'TrialOffset') && ~isempty(activeTrialStartTS)
        calculatedEndTS = mTime(i) - PRE_OFFSET_REDUCTION;
        if calculatedEndTS > activeTrialStartTS
            trialCount = trialCount + 1;
            [~, s_Sample] = min(abs(xTime_lsl - activeTrialStartTS)); [~, e_Sample] = min(abs(xTime_lsl - calculatedEndTS));
            if e_Sample > totalMasterSamples; e_Sample = totalMasterSamples; end
            trials(trialCount).trial_id = trialCount; trials(trialCount).start_sample = s_Sample; trials(trialCount).end_sample = e_Sample;
            trials(trialCount).start_ts = activeTrialStartTS; trials(trialCount).end_ts = calculatedEndTS;
        else
            warning('Skipping trial sequence: NPose to TrialOffset duration was shorter than the window reduction criteria.');
        end
        activeTrialStartTS = [];
    end
end
if trialCount == 0; error('Zero trials matching required marker parameters extracted.'); end
fprintf('Extracted %d trial segments windowed dynamically.\n', trialCount);

%% 5. Setup Graphic Visualizer Configuration
idx_match = @(name) find(contains(segmentNames, name, 'IgnoreCase', true), 1);
boneDefs = {'Pelvis','L5'; 'L5','L3'; 'L3','T12'; 'T12','T8'; 'T8','Neck'; 'Neck','Head'; 'T8','RightShoulder'; 'RightShoulder','RightUpperArm'; 'RightUpperArm','RightForeArm'; 'RightForeArm','RightHand'; 'T8','LeftShoulder'; 'LeftShoulder','LeftUpperArm'; 'LeftUpperArm','LeftForeArm'; 'LeftForeArm','LeftHand'; 'Pelvis','RightUpperLeg'; 'RightUpperLeg','RightLowerLeg'; 'RightLowerLeg','RightFoot'; 'RightFoot','RightToe'; 'Pelvis','LeftUpperLeg'; 'LeftUpperLeg','LeftLowerLeg'; 'LeftLowerLeg','LeftFoot'; 'LeftFoot','LeftToe';};
bones = zeros(size(boneDefs,1), 2); for b = 1:size(boneDefs,1); bones(b,1) = idx_match(boneDefs{b,1}); bones(b,2) = idx_match(boneDefs{b,2}); end
nBones = size(bones, 1); headIdx = idx_match('Head'); if isempty(headIdx); headIdx = 6; end
boneColor = [0.20 0.60 1.00]; rightColor = [1.00 0.35 0.35]; leftColor = [0.35 1.00 0.55];
maxForceLimit = max([master_ForceR, master_ForceL], [], 'omitnan') * 1.05; if isempty(maxForceLimit) || ~isfinite(maxForceLimit); maxForceLimit = 1000; end

%% 6. Loop and Export Trial Subsections (MAT Data & 3 Video Derivatives per Trial)
contrastVal = 1.3; brightnessVal = 0.2; gammaExponent = 1 / 1.3; % Video processing parameters

for t = 1:trialCount
    sIdx = trials(t).start_sample; eIdx = trials(t).end_sample;
    trialStartTS = trials(t).start_ts; trialEndTS = trials(t).end_ts;
    trialDuration = xTime_lsl(eIdx) - xTime_lsl(sIdx);
    
    baseOutName = sprintf('%s_%s_task-%s_run-%s_trial-%03d', subID, sesID, taskName, runID, trials(t).trial_id);
    outMatPath  = fullfile(OUTPUT_MOTION_DIR, [baseOutName '_desc-synchronized_motion.mat']);
    fprintf(' -> Processing Trial %03d/%03d (Duration: %.2f s)\n', t, trialCount, trialDuration);
        
    % --- Step 6a: Identify Intermittent Event Markers ---
    trialMarkerMask = (mTime >= trialStartTS) & (mTime <= trialEndTS);
    trialMarkerTexts = mText(trialMarkerMask); trialMarkerTimes = mTime(trialMarkerMask);
    for m = 1:numel(trialMarkerTexts)
        if contains(trialMarkerTexts{m}, 'Fgt', 'IgnoreCase', true); trialMarkerTexts{m} = 'Fight'; end
        if contains(trialMarkerTexts{m}, 'Neu', 'IgnoreCase', true); trialMarkerTexts{m} = 'Neutral'; end
    end
    
    % --- Step 6b: Save Unified MAT Payload Matrix ---
    syncTrialData = struct(...
        'trial_id', trials(t).trial_id, ...
        'lsl_master_timestamps', xTime_lsl(sIdx:eIdx), ...
        'elapsed_trial_time', xTime_lsl(sIdx:eIdx) - xTime_lsl(sIdx), ...
        'xsens_segment_labels', {segmentNames}, ...
        'xsens_positions_3D', master_PosData(:, sIdx:eIdx), ...
        'loadsol_force_N_right', master_ForceR(sIdx:eIdx), ...
        'loadsol_force_N_left', master_ForceL(sIdx:eIdx), ...
        'event_marker_strings', {trialMarkerTexts}, ...
        'event_master_timestamps', trialMarkerTimes, ...
        'event_relative_timestamps', trialMarkerTimes - xTime_lsl(sIdx) ...
    );
    % save(outMatPath, 'syncTrialData', '-v7.3');
    
    % --- Step 6c: Video 1 & 2 - Process and Crop Raw Camera Views ---
    videoViewsToSlice = {}; videoAcqLabels = {}; videoFrameMarkerIndices = {};
    if has_video1
        videoViewsToSlice{end+1} = fullfile(VIDEO_DIR, view1Struct(1).name); videoAcqLabels{end+1} = 'SideView'; videoFrameMarkerIndices{end+1} = sideCamMarkerIdx;
    end
    if has_video2
        videoViewsToSlice{end+1} = fullfile(VIDEO_DIR, view2Struct(1).name); videoAcqLabels{end+1} = 'UpperView'; videoFrameMarkerIndices{end+1} = upperCamMarkerIdx;
    end

    % Define the hardware video lag (10 frames)
    HARDWARE_FRAME_LAG = 10; 
    
    for v = 1:numel(videoViewsToSlice)
        try
            reader = VideoReader(videoViewsToSlice{v});
            acqLabel = videoAcqLabels{v};
    
            outVideoPath   = fullfile(OUTPUT_VIDEO_DIR, [baseOutName '_acq-' acqLabel '_beh.avi']);
            outSidecarPath = fullfile(OUTPUT_VIDEO_DIR, [baseOutName '_acq-' acqLabel '_beh.json']);
            outLutPath     = fullfile(OUTPUT_VIDEO_DIR, [baseOutName '_acq-' acqLabel '_desc-frameLUT_beh.tsv']);
    
            % --- 1. RESOLVE FRAME INDEXES WITH HARDWARE LAG COMPENSATION ---
            if ~isempty(videoFrameMarkerIndices{v})
                vFrames = streams{videoFrameMarkerIndices{v}}.time_series(:);
                vTime   = streams{videoFrameMarkerIndices{v}}.time_stamps(:);
                
                % Exact index in LSL stream where Neutral event occurred
                [~, neutralLutIdx]  = min(abs(vTime - trialStartTS));
                [~, endFrameLutIdx] = min(abs(vTime - trialEndTS));
                
                % Physical Neutral timestamp (t = 0.00s)
                trialStartLSLTimestamp = vTime(neutralLutIdx);
                
                % Add +10 frames so we pull the delayed visual frame corresponding to Neutral
                startFrame = double(vFrames(neutralLutIdx)) + HARDWARE_FRAME_LAG;
                endFrame   = double(vFrames(endFrameLutIdx)) + HARDWARE_FRAME_LAG;
            else
                % Fallback if FrameMarker is missing
                fps = reader.FrameRate;
                trialStartLSLTimestamp = trialStartTS;
                startFrame = min(reader.NumFrames, round((trialStartTS - xTime_lsl(1)) * fps) + HARDWARE_FRAME_LAG);
                endFrame   = min(reader.NumFrames, round((trialEndTS - xTime_lsl(1)) * fps) + HARDWARE_FRAME_LAG);
                
                vFrames = (1:reader.NumFrames)'; 
                vTime   = (0:reader.NumFrames-1)'./fps + xTime_lsl(1);
            end
    
            % Ensure frame bounds remain within raw video file boundaries
            if startFrame < 1; startFrame = 1; end
            if endFrame > reader.NumFrames; endFrame = reader.NumFrames; end
    
            writer = VideoWriter(outVideoPath, 'MPEG-4'); writer.FrameRate = reader.FrameRate; writer.Quality = 95; open(writer);
            reader.CurrentTime = (startFrame - 1) / reader.FrameRate;
    
            currentFrameNum = startFrame; 
            totalFramesInTrial = (endFrame - startFrame) + 1;
            frameLUTData = zeros(totalFramesInTrial, 3); 
            lutRowIdx = 1;
    
            eventDisplayWindow = 0.5; % Display event text for 0.5s
    
            % --- 2. FRAME PROCESSING & TEXT BURNING LOOP ---
            while hasFrame(reader) && (currentFrameNum <= endFrame)
                imgRaw = readFrame(reader);
                
                % Map current video frame (N + 10) back to physical LSL time N
                physicalFrameNum = currentFrameNum - HARDWARE_FRAME_LAG;
                lslEntryIdx = find(vFrames == physicalFrameNum, 1);
                if isempty(lslEntryIdx); [~, lslEntryIdx] = min(abs(vFrames - physicalFrameNum)); end
            
                % Compute exact elapsed trial time relative to the Neutral event timestamp
                globalLslTimestamp = vTime(lslEntryIdx); 
                elapsedTrialTime   = globalLslTimestamp - trialStartLSLTimestamp;
                
                pythonFrameIdx = lutRowIdx - 1;
                frameLUTData(lutRowIdx, :) = [pythonFrameIdx, globalLslTimestamp, elapsedTrialTime];
            
                % Image Color Correction
                imgDouble = double(imgRaw) / 255.0;
                imgProcessed = (imgDouble - 0.5) * contrastVal + 0.5 + brightnessVal;
                imgProcessed = imgProcessed .^ gammaExponent;
                imgProcessed(imgProcessed < 0) = 0; imgProcessed(imgProcessed > 1) = 1;
                img = uint8(imgProcessed * 255);
            
                % Dynamic Event Lookup
                activeIdx = find((globalLslTimestamp >= trialMarkerTimes) & ...
                                 (globalLslTimestamp <= (trialMarkerTimes + eventDisplayWindow)), 1);
            
                % Top-Left Overlay: Frame 0 will now strictly show Time: 0.00s
                lblText = sprintf('Trial: %03d | Frame: %d | Time: %.2fs', ...
                                  trials(t).trial_id, pythonFrameIdx, elapsedTrialTime);
                img = insertText(img, [15, 15], lblText, 'FontSize', 18, ...
                                 'TextColor', 'white', 'BoxColor', 'black', 'BoxOpacity', 0.5);
            
                % Top-Center Event Banner
                if ~isempty(activeIdx)
                    eventStr = sprintf('EVENT: %s', trialMarkerTexts{activeIdx});
                    img = insertText(img, [round(reader.Width/2 - 150), 50], eventStr, ...
                                     'FontSize', 28, 'TextColor', 'red');
                end
            
                writeVideo(writer, img);
                currentFrameNum = currentFrameNum + 1; 
                lutRowIdx = lutRowIdx + 1;
            end
            close(writer);
            if lutRowIdx <= totalFramesInTrial; frameLUTData(lutRowIdx:end, :) = []; end
    
            % Save LUT and Sidecar JSON
            lutTable = array2table(frameLUTData, 'VariableNames', {'video_frame', 'raw_lsl_timestamp', 'elapsed_trial_time'});
            writetable(lutTable, outLutPath, 'FileType', 'text', 'Delimiter', '\t');
    
            sidecar = struct('SpatialReference', 'Native camera frame space pixel matrix arrays (1280x720)', ...
                             'RawSourceFile', view1Struct(1).name, 'TrialID', trials(t).trial_id, ...
                             'FrameRate', reader.FrameRate, 'TargetAnalysisEngine', 'DeepLabCut Pose Estimation', ...
                             'TemporalAlignment', struct('TimeSynchronizedVia', ['LSL FrameMarker_' num2str(contains(acqLabel, 'Side', 'IgnoreCase', true)) ' Stream'], ...
                             'LookupTableFile', [baseOutName '_acq-' acqLabel '_desc-frameLUT_beh.tsv'], ...
                             'StartMarker', 'NPose', 'EndMarker', 'TrialOffset Reduction Buffer window'));
            fid = fopen(outSidecarPath, 'w'); fprintf(fid, '%s', jsonencode(sidecar, 'PrettyPrint', true)); fclose(fid);
        catch ME
            fprintf('    ! Warning processing video slice [%s]: %s\n', acqLabel, ME.message);
        end
    end

    % --- Step 6d: Video 3 - Analytical Multi-Modal Sync Plot ---
    plotOutPath = fullfile(OUTPUT_MOTION_DIR, [baseOutName '_desc-motion-force.mp4']);
    fig = figure('Color','k', 'Position',[50 50 1600 900], 'Visible','off');

    ax3d = subplot(1,2,1,'Parent',fig); set(ax3d,'Color','k','XColor','w','YColor','w','ZColor','w','GridColor',[0.3 0.3 0.3],'GridAlpha',0.4); hold(ax3d,'on'); grid(ax3d,'on'); view(ax3d, 35, 20); ax3d.DataAspectRatio = [1 1 1];
    trialPos3D = master_PosData(:, sIdx:eIdx);
    xlim(ax3d, [min(trialPos3D(:),[],'omitnan')-0.2, max(trialPos3D(:),[],'omitnan')+0.2]); ylim(ax3d, [min(trialPos3D(:),[],'omitnan')-0.2, max(trialPos3D(:),[],'omitnan')+0.2]); zlim(ax3d, [0, max(trialPos3D(:),[],'omitnan')+0.2]);

    hBones = gobjects(nBones, 1);
    for b = 1:nBones
        bname = segmentNames{bones(b,2)};
        if contains(bname,'Right','IgnoreCase',true); col = rightColor; elseif contains(bname,'Left','IgnoreCase',true); col = leftColor; else; col = boneColor; end
        hBones(b) = plot3(ax3d, [0 0],[0 0],[0 0], '-o','Color',col,'LineWidth',2.5,'MarkerFaceColor',col);
    end
    hHead = plot3(ax3d, 0,0,0, 'o', 'MarkerSize',12,'MarkerFaceColor',[1 0.85 0.6], 'MarkerEdgeColor','w');
    hTime = text(ax3d, ax3d.XLim(1)+0.05, ax3d.YLim(2)-0.05, ax3d.ZLim(2)-0.05, 't = 0.00 s','Color','w','FontSize',12,'FontWeight','bold');
    hEventLabel = text(ax3d, ax3d.XLim(1)+0.05, ax3d.YLim(1)+0.2, ax3d.ZLim(2)-0.05, '','Color','r','FontSize',24,'FontWeight','bold','HorizontalAlignment','left');
    title(ax3d, sprintf('Trial %03d: 3D Segment Kinematics', trials(t).trial_id), 'Color', 'w', 'FontSize', 14);

    ax2d = subplot(1,2,2,'Parent',fig); set(ax2d,'Color','k','XColor','w','YColor','w', 'GridColor',[0.3 0.3 0.3],'GridAlpha',0.4); hold(ax2d,'on'); grid(ax2d,'on'); ylim(ax2d,[0 maxForceLimit]); xlim(ax2d, [0, 3]);
    xlabel(ax2d, 'Elapsed Trial Time (s)'); ylabel(ax2d, 'Force (N)'); title(ax2d, 'Loadsol Dynamic Force Distribution', 'Color', 'w', 'FontSize', 14);

    tAxis = syncTrialData.elapsed_trial_time;
    hFR = plot(ax2d, tAxis, syncTrialData.loadsol_force_N_right, '-', 'Color', rightColor, 'LineWidth', 2.0, 'DisplayName', 'Right Foot');
    hFL = plot(ax2d, tAxis, syncTrialData.loadsol_force_N_left, '-', 'Color', leftColor,  'LineWidth', 2.0, 'DisplayName', 'Left Foot');
    hVline = xline(ax2d, 0, '--','Color',[1 1 0.4],'LineWidth',1.5, 'HandleVisibility','off');
    legend(ax2d, 'show', 'TextColor', 'w', 'Color', 'k', 'Location', 'northeast');

    vw_plot = VideoWriter(plotOutPath, 'MPEG-4'); vw_plot.FrameRate = 30; vw_plot.Quality = 90; open(vw_plot);
    frameStep = max(1, round(fs_lsl / vw_plot.FrameRate)); highlightWindowSamples = round(0.5 * fs_lsl);

    for s = 1:frameStep:(eIdx - sIdx + 1)
        if isnan(trialPos3D(1, s)); continue; end
        globalMasterTimestamp = xTime_lsl(sIdx + s - 1);

        currentFramePos = reshape(trialPos3D(:, s), 3, numSegments)';
        for b = 1:nBones
            p1 = bones(b,1); p2 = bones(b,2);
            set(hBones(b), 'XData', [currentFramePos(p1,1) currentFramePos(p2,1)], 'YData', [currentFramePos(p1,2) currentFramePos(p2,2)], 'ZData', [currentFramePos(p1,3) currentFramePos(p2,3)]);
        end
        set(hHead, 'XData', currentFramePos(headIdx,1), 'YData', currentFramePos(headIdx,2), 'ZData', currentFramePos(headIdx,3));

        currentTimeVal = tAxis(s);
        set(hTime, 'String', sprintf('t = %.2f s', currentTimeVal)); hVline.Value = currentTimeVal;

        if currentTimeVal <= 3; xlim(ax2d, [0, 3]); else; xlim(ax2d, [currentTimeVal - 3, currentTimeVal]); end

        activeMarkerIdx = find((globalMasterTimestamp >= trialMarkerTimes) & (globalMasterTimestamp <= (trialMarkerTimes + (highlightWindowSamples / fs_lsl))), 1);
        if ~isempty(activeMarkerIdx)
            set(hEventLabel, 'String', trialMarkerTexts{activeMarkerIdx});
            for b = 1:nBones; set(hBones(b), 'LineWidth', 3.5); end
        else
            set(hEventLabel, 'String', '');
            for b = 1:nBones; set(hBones(b), 'LineWidth', 2.5); end
        end
        drawnow limitrate; writeVideo(vw_plot, getframe(fig));
    end
    close(vw_plot); close(fig);
end
fprintf('\n Batch execution finalized. Payloads saved to %s and multi-view diagnostics exported to %s.\n', OUTPUT_MOTION_DIR, OUTPUT_VIDEO_DIR);