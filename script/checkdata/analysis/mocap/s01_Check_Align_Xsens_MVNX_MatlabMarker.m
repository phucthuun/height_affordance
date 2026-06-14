% ========================================================================
%  XSENS MVNX-XDF AUTOMATED SYNC, MAP & 3D MULTI-STREAM VISUALIZATION
% ========================================================================
%  
%  PURPOSE:
%  This script automates cross-correlation synchronization between an un-triggered
%  Xsens .MVNX file (HD Reprocessed) and an LSL .XDF file. It integrates the aligned
%  high-fidelity tracking markers directly onto the XDF master clock timeline,
%  maps behavioral task triggers using an EEGLAB standard convention structure,
%  and generates a real-time 3D animation track exported as an MP4 video.
%
%  ========================================================================

%% 1. Initialize Environment & Load Files
clear; clc; close all;

% --- Ingest MVNX File ---
[fileMvnx, pathMvnx] = uigetfile('*.mvnx', 'Select Xsens MVNX File');
if isequal(fileMvnx,0); disp('User cancelled'); return; end
fprintf('Loading MVNX file (parsing XML structural tree)... \n');
tree = load_mvnx(fullfile(pathMvnx, fileMvnx));

% --- Ingest XDF File ---
[fileXdf, pathXdf] = uigetfile('*.xdf', 'Select LSL XDF File containing Triggers');
if isequal(fileXdf,0); disp('User cancelled'); return; end
fprintf('Loading XDF file... \n');
streams = load_xdf(fullfile(pathXdf, fileXdf));

%% 2. Identify and Clean XDF Streams
xIdx = find(cellfun(@(x) contains(x.info.name, 'LinearSegmentKinematicsDatagram1'), streams), 1);
tIdx = find(cellfun(@(x) contains(x.info.name, 'MATLAB_Trigger', 'IgnoreCase', true), streams), 1);

if isempty(xIdx); error('Kinematics stream not found in XDF.'); end
if isempty(tIdx); error('MATLAB_Trigger stream not found in XDF.'); end

% Extract LSL Kinematics reference for alignment
xData_lsl = double(streams{xIdx}.time_series); 
xTime_lsl = streams{xIdx}.time_stamps;
fs_lsl = streams{xIdx}.info.nominal_srate;
if ischar(fs_lsl); fs_lsl = str2double(fs_lsl); end
if isnan(fs_lsl) || fs_lsl == 0; fs_lsl = 1 / mean(diff(xTime_lsl)); end

% Extract LSL triggers
tText = streams{tIdx}.time_series;
tTime = streams{tIdx}.time_stamps;

%% 3. Parse and Unpack Native MVNX Kinematics
frameRate_mvnx = tree.subject.frameRate;
numSegments = double(tree.subject.segmentCount);
nSamples_mvnx = length(tree.subject.frames.frame);

mvnx_allPos = zeros(numSegments * 3, nSamples_mvnx);
mvnx_comPos = zeros(3, nSamples_mvnx);

fprintf('Extracting raw coordinates from MVNX structural frames...\n');
for i = 1:nSamples_mvnx
    currentFrame = tree.subject.frames.frame(i);
    
    % Extract all segment positions (Safeguard empty identity/calibration frames)
    if isfield(currentFrame, 'position') && ~isempty(currentFrame.position)
        mvnx_allPos(:, i) = currentFrame.position(:);
    end
    
    % Extract Center of Mass with empty-check fallback protection
    if isfield(currentFrame, 'centerOfMass') && ~isempty(currentFrame.centerOfMass)
        mvnx_comPos(:, i) = currentFrame.centerOfMass(1:3);
    elseif isfield(currentFrame, 'com') && ~isempty(currentFrame.com)
        mvnx_comPos(:, i) = currentFrame.com(1:3);
    else
        if ~isempty(mvnx_allPos(:, i))
            rawCoords = reshape(mvnx_allPos(:, i), 3, numSegments)';
            mvnx_comPos(:, i) = mean(rawCoords, 1)';
        end
    end
end

%% 4. Automated Cross-Correlation Kinematic Synchronization
fprintf('Calculating velocity envelopes to establish cross-correlation alignment...\n');

% Calculate Pelvis (Segment 1) Velocity magnitude profile for LSL
lsl_pelvis = xData_lsl(1:3, :); 
lsl_vel = sqrt(sum(diff(lsl_pelvis, 1, 2).^2, 1));

% Calculate Pelvis Velocity magnitude profile for MVNX
mvnx_pelvis = mvnx_allPos(1:3, :); 
mvnx_vel = sqrt(sum(diff(mvnx_pelvis, 1, 2).^2, 1));
mvnx_time = (0:length(mvnx_vel)-1) / frameRate_mvnx;

% Match sampling rates if they differ
if frameRate_mvnx ~= fs_lsl
    mvnx_vel_resampled = resample(mvnx_vel, mvnx_time, fs_lsl);
else
    mvnx_vel_resampled = mvnx_vel;
end

% Compute cross-correlation lag
[correlation, lags] = xcorr(lsl_vel - mean(lsl_vel), mvnx_vel_resampled - mean(mvnx_vel_resampled));
[~, maxIdx] = max(correlation);
sample_lag = lags(maxIdx); 
time_lag_seconds = sample_lag / fs_lsl; 

fprintf('>>> Optimization Sync Match: MVNX started %.3f seconds after LSL. <<<\n', time_lag_seconds);

%% 5. Reconstruct Aligned Time Series & Update EEGLAB Structure
% Generate master synced timeline for MVNX frames matching LSL space
mvnx_sync_time = (0:nSamples_mvnx-1)/frameRate_mvnx + (xTime_lsl(1) + time_lag_seconds);

fprintf('Mapping aligned MVNX streams onto the master XDF timeline structure...\n');
totalMasterSamples = length(xTime_lsl);
aligned_PosData = zeros(numSegments * 3, totalMasterSamples);
aligned_ComData = zeros(3, totalMasterSamples);

% Populate master array using Nearest-Neighbor interpolation based on time logs
for t = 1:totalMasterSamples
    [timeDiff, closestMvnxIdx] = min(abs(mvnx_sync_time - xTime_lsl(t)));
    
    % Drop data to zero if XDF contains time regions outside the MVNX window bounds
    if timeDiff > (1 / frameRate_mvnx) * 2
        aligned_PosData(:, t) = NaN;
        aligned_ComData(:, t) = NaN;
    else
        aligned_PosData(:, t) = mvnx_allPos(:, closestMvnxIdx);
        aligned_ComData(:, t) = mvnx_comPos(:, closestMvnxIdx);
    end
end

% Build EEGLAB data model incorporating the high-fidelity reprocessed channels
EEG = eeg_emptyset();
EEG.data = [aligned_PosData; aligned_ComData]; % Combined payload array
EEG.srate = fs_lsl;
EEG.pnts = size(EEG.data, 2);

% Append Behavioral Markers onto the unified time sequence
actualMarkers = 0;
for m = 1:length(tText)
    currType = tText{m};
    if iscell(currType); currType = currType{1}; end
    if isempty(currType); continue; end
    
    actualMarkers = actualMarkers + 1;
    [~, sampleIdx] = min(abs(xTime_lsl - tTime(m)));
    
    if contains(currType, 'Fgt', 'IgnoreCase', true), currType = 'Fight'; end
    if contains(currType, 'Neu', 'IgnoreCase', true), currType = 'Neutral'; end
    
    EEG.event(actualMarkers).type = currType;
    EEG.event(actualMarkers).latency = sampleIdx;
    EEG.event(actualMarkers).duration = 1;
end

%% 6. Setup Animation Figure & 3D Layer Rendering Engine
figAnim = figure('Name', 'Aligned_MVNX_XDF_Visualization', 'Color', 'w', 'Position', [100 100 800 600]);
hold on;

% Create semi-transparent marker elements for body tracking points
hBody = scatter3(0,0,0, 60, 'b', 'filled', ...
                 'MarkerFaceAlpha', 0.45, ...  
                 'MarkerEdgeAlpha', 0.60);     

% Create prioritize opaque diamond marker representation for the CoM
hCoM = scatter3(0,0,0, 150, 'k', 'd', 'filled', ...
                'MarkerEdgeColor', 'w', 'LineWidth', 1.8, ...
                'MarkerFaceAlpha', 1.0); 

grid on; axis equal;
xlabel('X (m)'); ylabel('Y (m)'); zlabel('Z (m)');

% Establish display bounding margins dynamically
validIdx = ~isnan(aligned_PosData(1,:));
minVal = min(min(aligned_PosData(:, validIdx))); 
maxVal = max(max(aligned_PosData(:, validIdx)));
xlim([minVal maxVal]); ylim([minVal maxVal]); zlim([minVal maxVal]);

legend([hBody, hCoM], {'Aligned MVNX Body Segments', 'Center of Mass'}, 'Location', 'northeast');

txtLabel = text(minVal + 0.1, maxVal - 0.1, maxVal - 0.1, '', ...
    'FontSize', 24, 'FontWeight', 'bold', 'Color', 'r', 'HorizontalAlignment', 'left');

% Video Export configuration Setup
[~, outName] = fileparts(fileXdf);
videoPath = fullfile(pathXdf, [outName,'_Aligned_MVNX.mp4']);
v = VideoWriter(videoPath, 'MPEG-4');
v.FrameRate = 30; 
open(v);

highlightSamples = round(0.5 * EEG.srate); 
triggerLatencies = [EEG.event.latency];
triggerTypes = {EEG.event.type};
view(3);

frameStep = max(1, round(EEG.srate / v.FrameRate));

%% 7. Animation Loop Bounded Between Marker 1 and Marker 20
fprintf('Locating marker bounds for video cutting...\n');

% Check if there are enough markers in the recording
if length(EEG.event) < 20
    error('The data only contains %d markers. Cannot export up to the 20th marker.', length(EEG.event));
end

% Extract the master sample indices (latencies) for the 1st and 20th markers
startSample = EEG.event(1).latency;
endSample   = EEG.event(20).latency;

fprintf('Exporting video from sample %d (Marker 1) to sample %d (Marker 20)...\n', startSample, endSample);

% Loop directly within the calculated marker window bounds
for t = startSample:frameStep:endSample

    % Handle potential edge cases where data inside the window might contain NaNs
    if isnan(EEG.data(1, t))
        continue; 
    end

    % Unpack Body segments configuration payload [NumSegments x 3]
    currentFrameBody = reshape(EEG.data(1:(numSegments*3), t), 3, numSegments)'; 

    % Unpack Synced Center of Mass coordinates
    currentCoM = EEG.data((numSegments*3)+1 : end, t); 

    % Apply structural vertical Z-offset layering safety padding factor (1mm)
    rOffsetZ = 0.001; 
    currentCoMLayered = [currentCoM(1); currentCoM(2); currentCoM(3) + rOffsetZ];

    % Intercept active behavioral MATLAB task triggers
    activeTrigIdx = find(t >= triggerLatencies & t <= (triggerLatencies + highlightSamples), 1);
    if ~isempty(activeTrigIdx)
        bodyColor = [1 0 0]; % Turn the avatar red when inside a trigger event frame
        currentLabel = triggerTypes{activeTrigIdx}; 
    else
        bodyColor = [0 0 1]; % Default state tracking color (Blue)
        currentLabel = '';    
    end

    % Update graphic pipeline elements safely
    if ishandle(hBody) && ishandle(hCoM) && ishandle(txtLabel)
        set(hBody, 'XData', currentFrameBody(:,1), 'YData', currentFrameBody(:,2), ...
                   'ZData', currentFrameBody(:,3), 'CData', repmat(bodyColor, numSegments, 1));

        set(hCoM, 'XData', currentCoMLayered(1), 'YData', currentCoMLayered(2), 'ZData', currentCoMLayered(3));

        set(txtLabel, 'String', currentLabel);
        drawnow;
        writeVideo(v, getframe(figAnim));
    else
        break;
    end
end

close(v); 
fprintf('Segment video processing complete! Saved to: %s\n', videoPath);