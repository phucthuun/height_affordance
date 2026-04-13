%% 1. Initialize Environment
clear; clc; close all;
[file, path] = uigetfile('*.xdf', 'Select XDF file containing Xsens and Triggers');
if isequal(file,0); disp('User cancelled'); return; end
fullPath = fullfile(path, file);

%% 2. Load and Identify Streams
streams = load_xdf(fullPath);
xIdx = find(cellfun(@(x) contains(x.info.name, 'QuaternionDatagram1'), streams), 1);
tIdx = find(cellfun(@(x) contains(x.info.name, 'Trigger', 'IgnoreCase', true), streams), 1);

if isempty(xIdx) || isempty(tIdx)
    error('Required streams not found.');
end

%% 3. Extract and Clean Data
xData = double(streams{xIdx}.time_series); 
xTime = streams{xIdx}.time_stamps;
tText = streams{tIdx}.time_series;
tTime = streams{tIdx}.time_stamps;

srate = streams{xIdx}.info.nominal_srate;
if ischar(srate); srate = str2double(srate); end
if isnan(srate) || srate == 0; srate = 1 / mean(diff(xTime)); end

%% 4. Build EEGLAB Structure
EEG = eeg_emptyset();
EEG.data = xData;
EEG.srate = srate;
EEG.pnts = size(xData, 2);

for m = 1:length(tText)
    [~, sampleIdx] = min(abs(xTime - tTime(m)));
    currType = tText{m};
    if iscell(currType); currType = currType{1}; end
    if contains(currType, 'Fgt', 'IgnoreCase', true), currType = 'Fight'; end
    if contains(currType, 'Neu', 'IgnoreCase', true), currType = 'Neutral'; end
    
    EEG.event(m).type = currType;
    EEG.event(m).latency = sampleIdx;
    EEG.event(m).duration = 1;
end

%% 5. Coordinate Extraction
numSegments = 23;
posIndices = [];
for i = 1:numSegments
    startIdx = (i-1)*7 + 1;
    posIndices = [posIndices, startIdx:startIdx+2];
end
allPos = EEG.data(posIndices, :);

%% 6. Figure 1: 3D Animation & Video Recording with Text Labels
figAnim = figure('Name', 'Xsens_3D_Animation', 'Color', 'w', 'Position', [100 100 800 600]);
h = scatter3(0,0,0, 60, 'b', 'filled'); 
grid on; axis equal;
xlabel('X (m)'); ylabel('Y (m)'); zlabel('Z (m)');

% --- Create a Text Object for Trigger Names ---
% Position it at the top-left of the plot space
txtLabel = text(min(allPos(:)), max(allPos(:)), max(allPos(:)), '', ...
    'FontSize', 24, 'FontWeight', 'bold', 'Color', 'r', 'HorizontalAlignment', 'left');

% Video Setup
videoPath = fullfile(path, 'Xsens_Labeled_Movement.mp4');
v = VideoWriter(videoPath, 'MPEG-4');
v.FrameRate = 30; 
open(v);

highlightSamples = round(0.5 * EEG.srate);
triggerLatencies = [EEG.event.latency];
triggerTypes = {EEG.event.type};

view(3);
xlim([min(allPos(:)) max(allPos(:))]);
ylim([min(allPos(:)) max(allPos(:))]);
zlim([min(allPos(:)) max(allPos(:))]);

fprintf('Recording video with trigger labels...\n');
for t = 1:10:size(allPos, 2)
    currentFrame = reshape(allPos(:, t), 3, numSegments)'; 
    
    % Check for active triggers
    activeTrigIdx = find(t >= triggerLatencies & t <= (triggerLatencies + highlightSamples), 1);
    
    if ~isempty(activeTrigIdx)
        bodyColor = [1 0 0]; % Red
        currentLabel = triggerTypes{activeTrigIdx}; % Get trigger name
    else
        bodyColor = [0 0 1]; % Blue
        currentLabel = '';    % No text
    end
    
    % Update plot and text label
    set(h, 'XData', currentFrame(:,1), 'YData', currentFrame(:,2), ...
           'ZData', currentFrame(:,3), 'CData', bodyColor);
    set(txtLabel, 'String', currentLabel);
    
    drawnow;
    writeVideo(v, getframe(figAnim));
end
close(v); 
fprintf('Video saved: %s\n', videoPath);

%% 7. Finalize
pop_eegplot(EEG, 1, 1, 1);
fprintf('\nDONE. Files saved in: %s\n', path);