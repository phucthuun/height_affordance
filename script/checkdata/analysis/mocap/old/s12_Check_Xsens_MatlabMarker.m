%% ========================================================================
%  XSENS MVN KINEMATICS & CENTER OF MASS (CoM) MULTI-STREAM VISUALIZATION
% ========================================================================
%  
%  PURPOSE:
%  This script processes, synchronizes, and animates multi-stream biomechanical 
%  data recorded via LabStreamingLayer (LSL) from an Xsens MVN Awinda system. 
%  It renders a real-time 3D reconstruction of the human body segments alongside 
%  the calculated Center of Mass (CoM), overlays behavioral task triggers, 
%  and exports the complete visualization as a high-fidelity MP4 video.
%
%  KEY FUNCTIONS & ARCHITECTURE:
%  1. Multi-Stream Ingestion: Automated extraction of asynchronous streams 
%     (Linear Kinematics, Center of Mass, and MATLAB Triggers) from a single .XDF file.
%  2. Nearest-Neighbor Time Synchronization: Aligning independent LSL timelines 
%     by mapping behavioral triggers and CoM timestamps to the high-rate kinematics clock.
%  3. EEGLAB Integration: Structuring tracking data and behavioral events into a standard 
%     EEG structure for unified behavioral segmentation downstream.
%  4. Advanced 3D Graphics Engine: Features a layered rendering pipeline using 
%     semi-transparent body marker elements and prioritized Z-offset overlays to ensure 
%     the Center of Mass (CoM) diamond marker remains perfectly visible inside the body shell.
%  5. Automated Video Production: Frames are captured downsampled to a 30 FPS target 
%     and encoded into an MPEG-4 container saved directly to the source directory.
%
%  DEPENDENCIES & REQUIREMENT:
%  - MATLAB (R2019b or later recommended)
%  - EEGLAB Toolbox (for eeg_emptyset, eeg_checkset, and pop_eegplot functions)
%  - xdf-plugin / load_xdf.m (for importing native Extensible Data Format files)
%
%  INPUT:  User-selected .xdf file containing 'LinearSegmentKinematicsDatagram1', 
%          'CenterOfMass1', and 'MATLAB_Trigger' streams.
%  OUTPUT: 1. Live 3D MATLAB Interactive Animation Window.
%          2. Compiled MP4 Video File ([Filename]_Xsens_CoM.mp4).
%
%  ========================================================================

%% 1. Initialize Environment
clear; clc; close all;
[file, path] = uigetfile('*.xdf', 'Select XDF file containing Xsens and Triggers');
if isequal(file,0); disp('User cancelled'); return; end
fullPath = fullfile(path, file);

%% 2. Load and Identify Streams
fprintf('Loading XDF file... This may take a moment.\n');
streams = load_xdf(fullPath);

xIdx = find(cellfun(@(x) contains(x.info.name, 'LinearSegmentKinematicsDatagram1'), streams), 1);
cIdx = find(cellfun(@(x) contains(x.info.name, 'CenterOfMass1'), streams), 1);
tIdx = find(cellfun(@(x) contains(x.info.name, 'MATLAB_Trigger', 'IgnoreCase', true), streams), 1);

if isempty(xIdx); error('Kinematics stream not found.'); end
if isempty(cIdx); error('CenterOfMass1 stream not found.'); end
if isempty(tIdx); error('MATLAB_Trigger stream not found.'); end

%% 3. Extract and Clean Data
xData = double(streams{xIdx}.time_series); 
xTime = streams{xIdx}.time_stamps;
cData = double(streams{cIdx}.time_series);
cTime = streams{cIdx}.time_stamps;
tText = streams{tIdx}.time_series;
tTime = streams{tIdx}.time_stamps;

srate = streams{xIdx}.info.nominal_srate;
if ischar(srate); srate = str2double(srate); end
if isnan(srate) || srate == 0; srate = 1 / mean(diff(xTime)); end

%% 4. Build EEGLAB Structure & Sync Triggers
EEG = eeg_emptyset();
EEG.data = xData;
EEG.srate = srate;
EEG.pnts = size(xData, 2);

actualMarkers = 0;
for m = 1:length(tText)
    currType = tText{m};
    if iscell(currType); currType = currType{1}; end
    if isempty(currType); continue; end
    
    actualMarkers = actualMarkers + 1;
    [~, sampleIdx] = min(abs(xTime - tTime(m)));
    
    if contains(currType, 'Fgt', 'IgnoreCase', true), currType = 'Fight'; end
    if contains(currType, 'Neu', 'IgnoreCase', true), currType = 'Neutral'; end
    
    EEG.event(actualMarkers).type = currType;
    EEG.event(actualMarkers).latency = sampleIdx;
    EEG.event(actualMarkers).duration = 1;
end

%% 5. Coordinate Extraction
numSegments = 23; 
posIndices = [];
for i = 1:numSegments
    startIdx = (i-1)*9 + 1; 
    posIndices = [posIndices, startIdx:startIdx+2];
end
allPos = EEG.data(posIndices, :);

%% 6. Setup Animation Figure & Multiple Plots with Transparency
figAnim = figure('Name', 'Xsens_3D', 'Color', 'w', 'Position', [100 100 800 600]);
hold on;

% --- FIX: APPLY SEMI-TRANSPARENCY TO BODY SEGMENTS ---
% Use 'MarkerFaceAlpha' to set transparency (0.0 = fully clear, 1.0 = solid).
hBody = scatter3(0,0,0, 60, 'b', 'filled', ...
                 'MarkerFaceAlpha', 0.45, ...  % Body is 55% transparent
                 'MarkerEdgeAlpha', 0.60);     % Edges are slightly visible

% Plot CoM as a large solid black diamond (solid white border, priority linewidth)
hCoM = scatter3(0,0,0, 150, 'k', 'd', 'filled', ...
                'MarkerEdgeColor', 'w', 'LineWidth', 1.8, ...
                'MarkerFaceAlpha', 1.0); % Guarantee CoM is opaque

grid on; axis equal;
xlabel('X (m)'); ylabel('Y (m)'); zlabel('Z (m)');

minVal = min(allPos(:)); maxVal = max(allPos(:));
xlim([minVal maxVal]); ylim([minVal maxVal]); zlim([minVal maxVal]);
legend([hBody, hCoM], {'Body Segments', 'Center of Mass'}, 'Location', 'northeast');

txtLabel = text(minVal + 0.1, maxVal - 0.1, maxVal - 0.1, '', ...
    'FontSize', 24, 'FontWeight', 'bold', 'Color', 'r', 'HorizontalAlignment', 'left');

% Video Setup
[~, outName] = fileparts(file);
videoPath = fullfile(path, [outName,'_Xsens_CoM.mp4']);
v = VideoWriter(videoPath, 'MPEG-4');
v.FrameRate = 30; 
open(v);

highlightSamples = round(0.5 * EEG.srate); 
triggerLatencies = [EEG.event.latency];
triggerTypes = {EEG.event.type};
view(3);

fprintf('Processing video frames (Layered Body + CoM Sync)...\n');
frameStep = max(1, round(EEG.srate / v.FrameRate));

%% 7. Animation Loop with Dynamic Layering Offsets
for t = 1:frameStep:size(allPos, 2)
    
    % 1. Body positions (raw spatial data)
    currentFrameBody = reshape(allPos(:, t), 3, numSegments)'; 
    
    % 2. Sync CoM Time
    [~, closestCoMIdx] = min(abs(cTime - xTime(t)));
    currentCoM = cData(:, closestCoMIdx); % [X; Y; Z]
    
    % --- FIX: APPLY EXPLICIT Z-OFFSET TO COM DATA ---
    % Add a microscopic vertical offset (1 millimeter) to the CoM data Z-coordinate.
    % This mathematically forces the CoM diamond on top of any body dots it overlaps.
    rOffsetZ = 0.001; % 1 millimeter vertical boost
    currentCoMLayered = [currentCoM(1); currentCoM(2); currentCoM(3) + rOffsetZ];
    
    % 3. Check Triggers
    activeTrigIdx = find(t >= triggerLatencies & t <= (triggerLatencies + highlightSamples), 1);
    if ~isempty(activeTrigIdx)
        bodyColor = [1 0 0];
        currentLabel = triggerTypes{activeTrigIdx}; 
    else
        bodyColor = [0 0 1];
        currentLabel = '';    
    end
    
    % 4. Update Graphics Safely
    if ishandle(hBody) && ishandle(hCoM) && ishandle(txtLabel)
        set(hBody, 'XData', currentFrameBody(:,1), 'YData', currentFrameBody(:,2), ...
                   'ZData', currentFrameBody(:,3), 'CData', repmat(bodyColor, numSegments, 1));
        
        % --- Update CoM with the offset data (now prioritized) ---
        set(hCoM, 'XData', currentCoMLayered(1), 'YData', currentCoMLayered(2), 'ZData', currentCoMLayered(3));
        
        set(txtLabel, 'String', currentLabel);
        drawnow;
        writeVideo(v, getframe(figAnim));
    else
        break;
    end
end
close(v); 
fprintf('Video complete: %s\n', videoPath);
