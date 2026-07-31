%% Unified BIDS Multi-Camera Video Synchronization & Slicing Pipeline
% Description: Parses LSL master XDF files, extracts trial markers, synchronizes 
%              frame markers with hardware lag compensation, and exports trimmed 
%              video clips (.mp4), BIDS JSON sidecars, and frame LUT TSVs for all 3 views.
clear; clc; close all;

%% 0. BIDS Paths & Setup
fprintf('============ BIDS TRI-CAMERA VIDEO SYNCHRONIZER & SLICER ============ \n');
BASE_LOC        = '\\mpib-berlin.mpg.de\Share\Projects\1223-xplo-judo\private\10_Data\sourcedata';
DERIVATIVES_LOC = 'C:\Data\Research\10_Data\derivatives';
PIPELINE_NAME   = 'syncdata';
PIPELINE_ROOT   = fullfile(DERIVATIVES_LOC, PIPELINE_NAME);

% Request Processing Metadata
prompt = {'Enter Subject ID (e.g., MH9HXJ):', 'Enter Session ID (e.g., S001):', ...
          'Enter Run ID (e.g., 001):', 'Enter Task Name:', 'Trim buffer before TrialOffset (s):'};
dlgtitle = 'Video Pipeline Selection';
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

% Directory Structure
VIDEO_DIR      = fullfile(BASE_LOC, subID, sesID, 'video');
LSL_GLOBAL_DIR = fullfile(BASE_LOC, subID, sesID, 'lslglobal');
OUTPUT_VIDEO_DIR = fullfile(PIPELINE_ROOT, subID, sesID, 'video');

if ~exist(OUTPUT_VIDEO_DIR, 'dir'), mkdir(OUTPUT_VIDEO_DIR); end

% Locate Primary Master XDF File
search_prefix = sprintf('%s_%s_task-%s_run-%s', subID, sesID, taskName, runID);
fullXdfPath   = fullfile(LSL_GLOBAL_DIR, [search_prefix '_lslglobal.xdf']);

if ~exist(fullXdfPath, 'file'), error('Missing master timeline trace XDF: %s', fullXdfPath); end

% Automatically Locate Available Video Views (Side, Upper, Ground)
viewStructs = struct();
viewStructs.SideView   = dir(fullfile(VIDEO_DIR, [search_prefix '*acq-SideView_beh.avi']));
viewStructs.UpperView  = dir(fullfile(VIDEO_DIR, [search_prefix '*acq-UpperView_beh.avi']));
viewStructs.GroundView = dir(fullfile(VIDEO_DIR, [search_prefix '*acq-GroundView_beh.avi']));

%% 1. Ingest Master XDF Timeline
fprintf('Loading master XDF file logs...\n');
streams = load_xdf(fullXdfPath);

% Locate Marker Event Stream
mIdx = find(cellfun(@(x) contains(x.info.name, 'Trigger', 'IgnoreCase', true) || ...
                        contains(x.info.name, 'Markers', 'IgnoreCase', true), streams), 1);
if isempty(mIdx); error('Required LSL Marker stream missing inside XDF.'); end

mText = streams{mIdx}.time_series(:); 
mTime = streams{mIdx}.time_stamps(:);

% Map Video FrameMarker Indices
markerMap = containers.Map();
markerMap('SideView')   = find(cellfun(@(x) strcmp(x.info.name, 'FrameMarker_1'), streams), 1);
markerMap('UpperView')  = find(cellfun(@(x) strcmp(x.info.name, 'FrameMarker_0'), streams), 1);
markerMap('GroundView') = find(cellfun(@(x) strcmp(x.info.name, 'FrameMarker_2'), streams), 1);

%% 2. Reconstruct Trial Timelines
trials = struct('trial_id', {}, 'start_ts', {}, 'end_ts', {});
trialCount = 0; activeTrialStartTS = [];

for i = 1:numel(mText)
    if strcmp(mText{i}, sprintf('Neutral%d', trialCount + 1))
        activeTrialStartTS = mTime(i);
    elseif contains(mText{i}, 'TrialOffset') && ~isempty(activeTrialStartTS)
        calculatedEndTS = mTime(i) - PRE_OFFSET_REDUCTION;
        if calculatedEndTS > activeTrialStartTS
            trialCount = trialCount + 1;
            trials(trialCount).trial_id = trialCount;
            trials(trialCount).start_ts = activeTrialStartTS;
            trials(trialCount).end_ts   = calculatedEndTS;
        else
            warning('Skipping trial %d: Window reduction made duration invalid.', trialCount + 1);
        end
        activeTrialStartTS = [];
    end
end

if trialCount == 0; error('Zero trials extracted from marker data.'); end
fprintf('Extracted %d valid trial segments.\n', trialCount);

%% 3. Loop and Crop Tri-Camera Video Streams
contrastVal = 1.3; brightnessVal = 0.2; gammaExponent = 1 / 1.3;
HARDWARE_FRAME_LAG = 10; % Compensates for camera driver acquisition latency
eventDisplayWindow = 0.5;

cameraLabels = {'SideView', 'UpperView', 'GroundView'};

for t = 1:trialCount
    trialStartTS  = trials(t).start_ts;
    trialEndTS    = trials(t).end_ts;
    trialDuration = trialEndTS - trialStartTS;
    baseOutName   = sprintf('%s_%s_task-%s_run-%s_trial-%03d', subID, sesID, taskName, runID, trials(t).trial_id);
    
    fprintf(' -> Processing Trial %03d/%03d (Duration: %.2f s)\n', t, trialCount, trialDuration);

    % Get trial event markers
    trialMarkerMask  = (mTime >= trialStartTS) & (mTime <= trialEndTS);
    trialMarkerTexts = mText(trialMarkerMask);
    trialMarkerTimes = mTime(trialMarkerMask);

    for camIdx = 1:numel(cameraLabels)
        acqLabel   = cameraLabels{camIdx};
        camStruct  = viewStructs.(acqLabel);
        streamIdx  = markerMap(acqLabel);

        if isempty(camStruct)
            fprintf('    ! Skipping %s (File not found)\n', acqLabel);
            continue;
        end

        try
            videoPath = fullfile(VIDEO_DIR, camStruct(1).name);
            reader    = VideoReader(videoPath);

            outVideoPath   = fullfile(OUTPUT_VIDEO_DIR, [baseOutName '_acq-' acqLabel '_beh']);
            outSidecarPath = fullfile(OUTPUT_VIDEO_DIR, [baseOutName '_acq-' acqLabel '_beh.json']);
            outLutPath     = fullfile(OUTPUT_VIDEO_DIR, [baseOutName '_acq-' acqLabel '_desc-frameLUT_beh.tsv']);

            % Resolve Frame Indexes with LSL
            if ~isempty(streamIdx)
                vFrames = streams{streamIdx}.time_series(:);
                vTime   = streams{streamIdx}.time_stamps(:);

                [~, neutralLutIdx]  = min(abs(vTime - trialStartTS));
                [~, endFrameLutIdx] = min(abs(vTime - trialEndTS));

                trialStartLSLTimestamp = vTime(neutralLutIdx);
                startFrame = double(vFrames(neutralLutIdx)) + HARDWARE_FRAME_LAG;
                endFrame   = double(vFrames(endFrameLutIdx)) + HARDWARE_FRAME_LAG;
            else
                fps = reader.FrameRate;
                trialStartLSLTimestamp = trialStartTS;
                startFrame = max(1, round((trialStartTS - mTime(1)) * fps) + HARDWARE_FRAME_LAG);
                endFrame   = min(reader.NumFrames, round((trialEndTS - mTime(1)) * fps) + HARDWARE_FRAME_LAG);
                vFrames    = (1:reader.NumFrames)';
                vTime      = (0:reader.NumFrames-1)'./fps + trialStartTS;
            end

            % Boundary checks
            startFrame = max(1, min(startFrame, reader.NumFrames));
            endFrame   = max(startFrame, min(endFrame, reader.NumFrames));

            writer = VideoWriter(outVideoPath, 'MPEG-4'); 
            writer.FrameRate = reader.FrameRate; 
            writer.Quality = 95; 
            open(writer);

            reader.CurrentTime = (startFrame - 1) / reader.FrameRate;

            currentFrameNum    = startFrame;
            totalFramesInTrial = (endFrame - startFrame) + 1;
            frameLUTData       = zeros(totalFramesInTrial, 3);
            lutRowIdx          = 1;

            % Slice & Process Video Frame Loop
            while hasFrame(reader) && (currentFrameNum <= endFrame)
                imgRaw = readFrame(reader);

                physicalFrameNum = currentFrameNum - HARDWARE_FRAME_LAG;
                lslEntryIdx = find(vFrames == physicalFrameNum, 1);
                if isempty(lslEntryIdx); [~, lslEntryIdx] = min(abs(vFrames - physicalFrameNum)); end

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

                % Overlays (Time & Events)
                activeIdx = find((globalLslTimestamp >= trialMarkerTimes) & ...
                                 (globalLslTimestamp <= (trialMarkerTimes + eventDisplayWindow)), 1);

                lblText = sprintf('Trial: %03d | Frame: %d | Time: %.2fs', ...
                                  trials(t).trial_id, pythonFrameIdx, elapsedTrialTime);
                img = insertText(img, [15, 15], lblText, 'FontSize', 18, ...
                                 'TextColor', 'white', 'BoxColor', 'black', 'BoxOpacity', 0.5);

                if ~isempty(activeIdx)
                    eventStr = sprintf('EVENT: %s', trialMarkerTexts{activeIdx});
                    img = insertText(img, [round(reader.Width/2 - 150), 50], eventStr, ...
                                     'FontSize', 28, 'TextColor', 'red');
                end

                writeVideo(writer, img);
                currentFrameNum = currentFrameNum + 1;
                lutRowIdx       = lutRowIdx + 1;
            end
            close(writer);

            if lutRowIdx <= totalFramesInTrial
                frameLUTData(lutRowIdx:end, :) = [];
            end

            % Export Frame LUT TSV
            lutTable = array2table(frameLUTData, 'VariableNames', {'video_frame', 'raw_lsl_timestamp', 'elapsed_trial_time'});
            writetable(lutTable, outLutPath, 'FileType', 'text', 'Delimiter', '\t');

            % Export Sidecar JSON
            sidecar = struct('SpatialReference', sprintf('Native camera frame space pixel matrix (%dx%d)', reader.Width, reader.Height), ...
                             'RawSourceFile', camStruct(1).name, 'TrialID', trials(t).trial_id, ...
                             'FrameRate', reader.FrameRate, 'TargetAnalysisEngine', 'DeepLabCut Pose Estimation', ...
                             'TemporalAlignment', struct('TimeSynchronizedVia', sprintf('LSL FrameMarker mapping (%s)', acqLabel), ...
                             'LookupTableFile', [baseOutName '_acq-' acqLabel '_desc-frameLUT_beh.tsv'], ...
                             'StartMarker', 'NPose', 'EndMarker', 'TrialOffset Reduction Buffer window'));
            fid = fopen(outSidecarPath, 'w'); 
            fprintf(fid, '%s', jsonencode(sidecar, 'PrettyPrint', true)); 
            fclose(fid);

        catch ME
            fprintf('    ! Error processing %s: %s\n', acqLabel, ME.message);
        end
    end
end

fprintf('\nVideo slicing completed successfully. All trial videos exported to:\n%s\n', OUTPUT_VIDEO_DIR);