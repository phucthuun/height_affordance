%% ========================================================================
%  XSENS MVN CoM TRIAL-BY-TRIAL TRAJECTORY ANALYSIS & CONDITION MATRIX
% ========================================================================
%  
%  PURPOSE:
%  This script ingests an XDF biomechanical file alongside its matching 
%  behavioral results log table. It extracts individual trial trajectories,
%  cleans out incomplete table padding, fixes block loop recycling, 
%  and sorts the 3D paths into a specific matrix: Posture x Stance Category.
%  
%  AXIS METRICS:
%  Axis limits are dynamically updated inline for every single tile to be
%  native to that specific trial's trajectory space.
%
%  LAYOUT ARCHITECTURE (Columns):
%  Column 1: Upright 186cm (Stance >= 180)
%  Column 2: Upright 173cm (Stance 170 - 179)
%  Column 3: Lowered 170cm (Stance 170 - 179)
%  Column 4: Lowered 155cm (Stance 150 - 159) [Capped at 16 Trials]
%
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

%% 3. Identify XDF Stream Timelines & Build Foundations
cIdx = find(cellfun(@(x) contains(x.info.name, 'CenterOfMass1'), streams), 1);
tIdx = find(cellfun(@(x) contains(x.info.name, 'MATLAB_Trigger', 'IgnoreCase', true), streams), 1);

if isempty(cIdx); error('Center of Mass stream (CenterOfMass1) not found.'); end
if isempty(tIdx); error('Trigger stream (MATLAB_Trigger) not found.'); end

cData = double(streams{cIdx}.time_series);
cTime = streams{cIdx}.time_stamps;
tText = streams{tIdx}.time_series;
tTime = streams{tIdx}.time_stamps;

srate = streams{cIdx}.info.nominal_srate;
if ischar(srate); srate = str2double(srate); end
if isnan(srate) || srate == 0; srate = 1 / mean(diff(cTime)); end

%% 4. Build Foundation Structure & Tracking Flags
EEG = eeg_emptyset();
EEG.data = cData; 
EEG.srate = srate;
EEG.pnts = size(cData, 2);

actualMarkers = 0;
for m = 1:length(tText)
    currType = tText{m};
    if iscell(currType); currType = currType{1}; end
    if isempty(currType); continue; end
    
    actualMarkers = actualMarkers + 1;
    [~, sampleIdx] = min(abs(cTime - tTime(m)));
    
    if contains(currType, 'Fgt', 'IgnoreCase', true), currType = 'Fight'; end
    if contains(currType, 'Neu', 'IgnoreCase', true), currType = 'Neutral'; end
    
    EEG.event(actualMarkers).type = currType;
    EEG.event(actualMarkers).latency = sampleIdx;
    EEG.event(actualMarkers).duration = 1;
end
EEG = eeg_checkset(EEG);

%% 5. Smart Marker Parsing (Tracks Block Switches and Trial IDs)
fprintf('Parsing block architecture and tracking tags...\n');
rawTypes = {EEG.event.type};
currentBlock = 1; 

for idx = 1:length(rawTypes)
    if contains(rawTypes{idx}, 'BlockStart', 'IgnoreCase', true)
        blockNumStr = regexp(rawTypes{idx}, '\d+', 'match');
        if ~isempty(blockNumStr)
            currentBlock = str2double(blockNumStr{1});
            fprintf('>> Stream timeline switched to Block %d\n', currentBlock);
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

%% 6. Pass 1: Isolate 3D Paths, Database Row Mapping, and Matrix Sorting
trialSegments = cell(numTrials, 5); 
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
    trialCoMPath = cData(:, startSample:endSample);
    
    tableRowIdx = find(results.block == thisBlock & results.trial_id == thisTrial, 1);
    if isempty(tableRowIdx); continue; end
    
    trialSegments{k, 1} = trialCoMPath;
    trialSegments{k, 2} = startSample;
    trialSegments{k, 3} = endSample;
    trialSegments{k, 4} = searchRange;
    trialSegments{k, 5} = tableRowIdx;
    
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

% Cap the fourth column analysis to the requested limit
if length(col_Lowered15) > 16
    col_Lowered15 = col_Lowered15(1:16);
end

maxRowsInGrid = max([length(col_Upright18), length(col_Upright17), length(col_Lowered17), length(col_Lowered15)]);
fprintf('Grid Dimensions Synchronized: %d rows x 4 condition columns.\n', maxRowsInGrid);

%% 7. Initialize Layout Windows and Colors
figGrid = figure('Name', 'CoM_Condition_Matrix_Grid', 'Color', 'w', ...
                 'Units', 'normalized', 'Position', [0.02 0.05 0.96 0.88]);
tLayout = tiledlayout(maxRowsInGrid, 4, 'TileSpacing', 'compact', 'Padding', 'compact');

title(tLayout, 'Explicitly Synchronized CoM Trajectories (Native Dynamic Trial Axis Scaling)', 'FontSize', 15, 'FontWeight', 'bold');
xlabel(tLayout, 'X Space Coordinate (m)', 'FontSize', 12);
ylabel(tLayout, 'Y Space Coordinate (m)', 'FontSize', 12);

gradientSteps = 256;
cMapBlue = [linspace(0.6, 0.0, gradientSteps)', ...
            linspace(0.8, 0.1, gradientSteps)', ...
            linspace(1.0, 0.4, gradientSteps)'];
colorNeutral = [0.9290 0.6940 0.1250];  
colorFight   = [0.8500 0.3250 0.0980];  

%% 8. Pass 2: Render Fully Linked Condition Matrix Layout
for r = 1:maxRowsInGrid
    for c = 1:4
        switch c
            case 1, targetColumnArray = col_Upright18; colLabel = 'Upright 186cm';
            case 2, targetColumnArray = col_Upright17; colLabel = 'Upright 173cm';
            case 3, targetColumnArray = col_Lowered17; colLabel = 'Lowered 170cm';
            case 4, targetColumnArray = col_Lowered15; colLabel = 'Lowered 155cm';
        end
        
        if r <= length(targetColumnArray)
            kIdx = targetColumnArray(r);
            
            fullPathSegment = trialSegments{kIdx, 1};
            sampleNPose     = trialSegments{kIdx, 2};
            sampleOffset    = trialSegments{kIdx, 3};
            searchRange     = trialSegments{kIdx, 4};
            tableRowIdx     = trialSegments{kIdx, 5};
            
            neutralSubIdx = find(cellfun(@(x) strcmpi(x, 'Neutral'), eventTypes(searchRange)), 1);
            fightSubIdx   = find(cellfun(@(x) strcmpi(x, 'Fight'), eventTypes(searchRange)), 1);
            
            nexttile((r-1)*4 + c);
            hold on; grid on;
            
            % A. Plot time-gradient blue trajectory line
            numPoints = size(fullPathSegment, 2);
            if numPoints > 1
                timeIndices = 1:numPoints; 
                surface([fullPathSegment(1,:); fullPathSegment(1,:)], ...
                        [fullPathSegment(2,:); fullPathSegment(2,:)], ...
                        [fullPathSegment(3,:); fullPathSegment(3,:)], ...
                        [timeIndices; timeIndices], ...
                        'FaceColor', 'none', 'EdgeColor', 'interp', 'LineWidth', 1.5);
                colormap(gca, cMapBlue);
            end
            
            % B. Plot event marker snapshot locations
            scatter3(cData(1, sampleNPose), cData(2, sampleNPose), cData(3, sampleNPose), 30, 'g', 'filled');
            
            if ~isempty(neutralSubIdx)
                sampleNeutral = eventLatencies(searchRange(neutralSubIdx));
                scatter3(cData(1, sampleNeutral), cData(2, sampleNeutral), cData(3, sampleNeutral), 30, colorNeutral, 'filled');
            end
            if ~isempty(fightSubIdx)
                sampleFight = eventLatencies(searchRange(fightSubIdx));
                scatter3(cData(1, sampleFight), cData(2, sampleFight), cData(3, sampleFight), 30, colorFight, 'filled');
            end
            
            scatter3(cData(1, sampleOffset), cData(2, sampleOffset), cData(3, sampleOffset), 18, [0.5 0 0], 's', 'filled');
            
            % --- CRITICAL UPDATE: NATIVE AXIS TRACKING DEFINITIONS ---
            % Extract spatial parameters strictly tied to this unique trial execution matrix segment
            paddingValue = 0.01; % 1cm buffer to secure clearance limits from marker boundaries
            
            trialXLim = [min(fullPathSegment(1,:)) - paddingValue, max(fullPathSegment(1,:)) + paddingValue];
            trialYLim = [min(fullPathSegment(2,:)) - paddingValue, max(fullPathSegment(2,:)) + paddingValue];
            trialZLim = [min(fullPathSegment(3,:)) - paddingValue, max(fullPathSegment(3,:)) + paddingValue];
            
            % Apply native axes
            xlim(trialXLim); 
            ylim(trialYLim); 
            zlim(trialZLim);
            
            title(sprintf('%s | B%d_T%d', colLabel, results.block(tableRowIdx), results.trial_id(tableRowIdx)), 'FontSize', 8, 'FontWeight', 'bold');
            view(3); axis equal;
        else
            nexttile((r-1)*4 + c);
            axis off;
        end
    end
end
fprintf('\nPipeline complete! All sub-panels scaled natively and sorted completely.\n');
