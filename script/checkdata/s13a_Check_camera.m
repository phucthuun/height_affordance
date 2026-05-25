%% LSL Video-Marker Synchronization Validator
% Purpose: Matches MATLAB experiment markers to specific video frame indices
% based on a shared LSL clock.

clear; clc;
[file, path] = uigetfile('*.xdf', 'Select your Video-Marker XDF file');
if isequal(file,0); return; end
fullPath = fullfile(path, file);

% Load the XDF data
fprintf('Loading XDF file: %s...\n', file);
streams = load_xdf(fullPath);

%% 1. Locate Streams
% Find MATLAB Trigger Stream
mIdx = find(cellfun(@(x) contains(x.info.name, 'Trigger', 'IgnoreCase', true), streams), 1);

% Find Camera Streams (Searching for your "FrameMarker_" names)
cam0Idx = find(cellfun(@(x) strcmp(x.info.name, 'FrameMarker_0'), streams), 1);
cam1Idx = find(cellfun(@(x) strcmp(x.info.name, 'FrameMarker_1'), streams), 1);

if isempty(mIdx) || isempty(cam0Idx)
    error('Required streams not found. Check that both MATLAB and Python LSL outlets were active.');
end

%% 2. Extract Timing Information
% MATLAB Markers
mText = streams{mIdx}.time_series;
mTime = streams{mIdx}.time_stamps;

% Video 0 (Upper-Cam)
v0Frames = streams{cam0Idx}.time_series; % The frame_counter from Python
v0Time   = streams{cam0Idx}.time_stamps;   % The LSL clock time for each frame

% Video 1 (Side-Cam)
hasCam1 = ~isempty(cam1Idx);
if hasCam1
    v1Frames = streams{cam1Idx}.time_series;
    v1Time   = streams{cam1Idx}.time_stamps;
end

%% 3. Synchronization Logic
% Pre-allocate the results table
numMarkers = length(mText);
Results = table('Size', [numMarkers 6], ...
    'VariableTypes', {'string', 'double', 'double', 'double', 'double', 'string'}, ...
    'VariableNames', {'Event', 'LSL_Timestamp', 'Cam0_Frame', 'Cam1_Frame', 'Sync_Error_ms', 'Integrity'});

fprintf('Syncing %d markers...\n', numMarkers);

for i = 1:numMarkers
    tMarker = mTime(i);
    Results.Event(i) = string(mText{i});
    Results.LSL_Timestamp(i) = tMarker;
    
    % Find nearest frame in Camera 0
    [val0, idx0] = min(abs(v0Time - tMarker));
    Results.Cam0_Frame(i) = v0Frames(idx0);
    Results.Sync_Error_ms(i) = val0 * 1000; % Time diff in milliseconds
    
    % Find nearest frame in Camera 1
    if hasCam1
        [~, idx1] = min(abs(v1Time - tMarker));
        Results.Cam1_Frame(i) = v1Frames(idx1);
    else
        Results.Cam1_Frame(i) = NaN;
    end
    
    % Quality Check: Is the error larger than half a frame duration? (Assuming 30fps)
    if Results.Sync_Error_ms(i) > 16.6
        Results.Integrity(i) = "⚠️ High Jitter";
    else
        Results.Integrity(i) = "✅ Precise";
    end
end

%% 4. Frame Rate Diagnostics
% Calculate actual recorded frame rate (FPS)
actualIntervals = diff(v0Time);
actualFPS = 1 / mean(actualIntervals);
droppedFrames = sum(diff(v0Frames) > 1);

fprintf('\n--- Diagnostic Report ---\n');
fprintf('Calculated Average FPS: %.2f\n', actualFPS);
fprintf('Total Potential Dropped Frames: %d\n', droppedFrames);
fprintf('Max Sync Error in this Session: %.2f ms\n', max(Results.Sync_Error_ms));

%% 5. Display & Save
disp(Results);

% Save report to the same folder as the XDF
[~, fileName] = fileparts(file);
savePath = fullfile(path, [fileName '_SyncReport.csv']);
writetable(Results, savePath);
fprintf('\nSync Report saved to: %s\n', savePath);