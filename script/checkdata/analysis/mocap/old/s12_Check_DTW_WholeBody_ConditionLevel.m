%% ========================================================================
%  XSENS LINEAR SEGMENT KINEMATICS DATAGRAM 1 — CROSS-CONDITION DTW ANALYSIS
% ========================================================================
%  
%  PURPOSE:
%  Extracts full-body profiles from the LinearSegmentKinematicsDatagram1 
%  stream and computes cross-conditional structural dissimilarity using 
%  Multidimensional Dynamic Time Warping (MD-DTW).
%
%  MATRIX STRUCTURING:
%  Data paths are fed into DTW natively as [Channels x Frames] to ensure 
%  varying trial lengths are seamlessly handled across matching variables.
%  ========================================================================

%% 1. Initialize Environment & Select Multi-Stream Files
clear; clc; close all;

% A. Select and load biometrics stream data
[xdfFile, xdfPath] = uigetfile('*.xdf', 'Select 1. XDF Data File (Xsens streams)');
if isequal(xdfFile,0); disp('User cancelled'); return; end
fprintf('Loading XDF biometric streams... This may take a moment.\n');
streams = load_xdf(fullfile(xdfPath, xdfFile));

% B. Select and load matching behavioral table matrix
[matFile, matPath] = uigetfile('*.mat', 'Select 2. Paired Behavioral LOG File (*_beh.mat)');
if isequal(matFile,0); disp('User cancelled'); return; end
behData = load(fullfile(matPath, matFile), 'results');
results = behData.results;

%% 2. Prune Pre-Allocation Table Padding
results(results.block == 0, :) = []; 
totalExecutedRows = height(results);
fprintf('Successfully loaded behavioral log. Found %d executed trials.\n', totalExecutedRows);

%% 3. Identify Kinematics & Trigger Stream Timelines 
% Target the specific LinearSegmentKinematicsDatagram1 stream
kIdxStream = find(cellfun(@(x) contains(x.info.name, 'LinearSegmentKinematicsDatagram1'), streams), 1);
tIdx = find(cellfun(@(x) contains(x.info.name, 'MATLAB_Trigger', 'IgnoreCase', true), streams), 1);

if isempty(kIdxStream); error('Target stream "LinearSegmentKinematicsDatagram1" not found.'); end
if isempty(tIdx); error('Trigger stream (MATLAB_Trigger) not found.'); end

kData = double(streams{kIdxStream}.time_series);
kTime = streams{kIdxStream}.time_stamps;
tText = streams{tIdx}.time_series;
tTime = streams{tIdx}.time_stamps;

srate = streams{kIdxStream}.info.nominal_srate;
if ischar(srate); srate = str2double(srate); end
if isnan(srate) || srate == 0; srate = 1 / mean(diff(kTime)); end

%% 4. Build Foundation Structure & Event Mapping
EEG = eeg_emptyset();
EEG.data = kData; 
EEG.srate = srate;
EEG.pnts = size(kData, 2);

actualMarkers = 0;
for m = 1:length(tText)
    currType = tText{m};
    if iscell(currType); currType = currType{1}; end
    if isempty(currType); continue; end
    
    actualMarkers = actualMarkers + 1;
    [~, sampleIdx] = min(abs(kTime - tTime(m)));
    
    if contains(currType, 'Fgt', 'IgnoreCase', true), currType = 'Fight'; end
    if contains(currType, 'Neu', 'IgnoreCase', true), currType = 'Neutral'; end
    
    EEG.event(actualMarkers).type = currType;
    EEG.event(actualMarkers).latency = sampleIdx;
    EEG.event(actualMarkers).duration = 1;
end
EEG = eeg_checkset(EEG);

%% 5. Marker Parsing (Tracks Block Switches and Trial IDs)
fprintf('Parsing block architecture and tracking tags...\n');
rawTypes = {EEG.event.type};
currentBlock = 1; 

for idx = 1:length(rawTypes)
    if contains(rawTypes{idx}, 'BlockStart', 'IgnoreCase', true)
        blockNumStr = regexp(rawTypes{idx}, '\d+', 'match');
        if ~isempty(blockNumStr)
            currentBlock = str2double(blockNumStr{1});
        end
    end
    
    if contains(rawTypes{idx}, 'TrialOnset', 'IgnoreCase', true)
        trialNumStr = regexp(rawTypes{idx}, '\d+', 'match');
        if ~isempty(trialNumStr)
            localTrialNum = str2double(trialNumStr{1});
            EEG.event(idx).type = sprintf('B%d_T%d_Onset', currentBlock, localTrialNum);
        end
    elseif contains(rawTypes{idx}, 'TrialOffset', 'IgnoreCase', true)
        trialNumStr = regexp(rawTypes{idx}, '\d+', 'match');
        if ~isempty(trialNumStr)
            localTrialNum = str2double(trialNumStr{1});
            EEG.event(idx).type = sprintf('B%d_T%d_Offset', currentBlock, localTrialNum);
        end
    end
end

eventTypes = {EEG.event.type};
eventLatencies = [EEG.event.latency]; 
onsetIdxs = find(cellfun(@(x) contains(x, '_Onset'), eventTypes));
numTrials = length(onsetIdxs);

%% 6. Isolate Datagram Paths & Condition Matrix Sorting
trialSegments = cell(numTrials, 2); 
col_Upright18 = [];
col_Upright17 = [];
col_Lowered17 = [];
col_Lowered15 = [];

for k = 1:numTrials
    currentOnsetEvtIdx = onsetIdxs(k);
    onsetName = eventTypes{currentOnsetEvtIdx};
    
    parsedTokens = regexp(onsetName, 'B(\d+)_T(\d+)_Onset', 'tokens');
    if isempty(parsedTokens); continue; end
    
    thisBlock = str2double(parsedTokens{1}{1});
    thisTrial = str2double(parsedTokens{1}{2});
    
    targetOffsetName = sprintf('B%d_T%d_Offset', thisBlock, thisTrial);
    currentOffsetEvtIdx = find(strcmp(eventTypes, targetOffsetName), 1);
    
    if isempty(currentOffsetEvtIdx); continue; end
    searchRange = currentOnsetEvtIdx : currentOffsetEvtIdx;
    
    nposeSubIdx = find(cellfun(@(x) strcmpi(x, 'NPose'), eventTypes(searchRange)), 1);
    if isempty(nposeSubIdx); continue; end
    
    globalNPoseIdx = searchRange(nposeSubIdx);
    startSample = eventLatencies(globalNPoseIdx);
    endSample = eventLatencies(currentOffsetEvtIdx);
    
    % Slice all available kinematic channels for this trial duration
    trialDatagramPath = kData(:, startSample:endSample);
    
    tableRowIdx = find(results.block == thisBlock & results.trial_id == thisTrial, 1);
    if isempty(tableRowIdx); continue; end
    
    trialSegments{k, 1} = trialDatagramPath;
    trialSegments{k, 2} = tableRowIdx;
    
    currentPosture = lower(string(results.posture(tableRowIdx)));
    currentStance  = results.stance(tableRowIdx);
    
    if contains(currentPosture, 'upright') && (currentStance >= 180)
        col_Upright18 = [col_Upright18; k];
    elseif contains(currentPosture, 'upright') && (currentStance >= 170 && currentStance < 180)
        col_Upright17 = [col_Upright17; k];
    elseif contains(currentPosture, 'lowered') && (currentStance >= 170 && currentStance < 180)
        col_Lowered17 = [col_Lowered17; k];
    elseif contains(currentPosture, 'lowered') && (currentStance >= 150 && currentStance < 170)
        col_Lowered15 = [col_Lowered15; k]; 
    end
end

if length(col_Lowered15) > 16
    col_Lowered15 = col_Lowered15(1:16);
end

%% 7. Linear Datagram Dynamic Time Warping (MD-DTW) Calculation
fprintf('\nRunning Kinematics Datagram Multidimensional DTW Analysis...\n');
fprintf('Data Dimensions: %d tracking channels detected.\n', size(kData, 1));

conditionGroups = {col_Upright18, col_Upright17, col_Lowered17, col_Lowered15};
conditionLabels = {'Upright 186cm', 'Upright 173cm', 'Lowered 170cm', 'Lowered 155cm'};
numConditions = length(conditionGroups);
dtwMatrix = zeros(numConditions, numConditions);

tic;
for groupA = 1:numConditions
    trialsA = conditionGroups{groupA};
    numTrialsA = length(trialsA);
    
    for groupB = 1:numConditions
        trialsB = conditionGroups{groupB};
        numTrialsB = length(trialsB);
        
        runningDistanceSum = 0;
        validComparisons = 0;
        
        for i = 1:numTrialsA
            kIdxA = trialsA(i);
            pathA = trialSegments{kIdxA, 1}; 
            if isempty(pathA) || size(pathA, 2) < 2; continue; end
            
            for j = 1:numTrialsB
                if (groupA == groupB) && (i == j); continue; end
                
                kIdxB = trialsB(j);
                pathB = trialSegments{kIdxB, 1};
                if isempty(pathB) || size(pathB, 2) < 2; continue; end
                
                % Call multidimensional alignment directly on [Channels x Frames]
                [rawDist, ix, iy] = dtw(pathA, pathB);
                
                % Normalize by warping path footprint length
                normalizedDist = rawDist / (length(ix) + length(iy));
                
                runningDistanceSum = runningDistanceSum + normalizedDist;
                validComparisons = validComparisons + 1;
            end
        end
        
        if validComparisons > 0
            dtwMatrix(groupA, groupB) = runningDistanceSum / validComparisons;
        else
            dtwMatrix(groupA, groupB) = 0;
        end
    end
end
toc;

%% 8. Visualize the Kinematics Dissimilarity Heatmap
figure('Name', 'Linear_Kinematics_DTW_Heatmap', 'Color', 'w', ...
       'Units', 'normalized', 'Position', [0.2 0.2 0.5 0.5]);

imagesc(dtwMatrix);
colormap(flipud(parula)); 
colorbar;

set(gca, 'XTick', 1:numConditions, 'XTickLabel', conditionLabels, ...
         'YTick', 1:numConditions, 'YTickLabel', conditionLabels, ...
         'FontSize', 11, 'FontWeight', 'bold');
xtickangle(25);

title('Linear Kinematics Datagram Structural Dissimilarity Matrix (MD-DTW)', 'FontSize', 12, 'FontWeight', 'bold');
xlabel('Target Condition Group', 'FontSize', 12);
ylabel('Source Condition Group', 'FontSize', 12);

% Overlay weights inside tiles
for row = 1:numConditions
    for col = 1:numConditions
        text(col, row, sprintf('%.4f', dtwMatrix(row, col)), ...
            'HorizontalAlignment', 'center', ...
            'FontSize', 12, 'FontWeight', 'bold', ...
            'Color', 'k');
    end
end

fprintf('Analysis Complete! Summary Heatmap successfully rendered.\n');