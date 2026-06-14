%% ========================================================================
%  XSENS MVN CoM TRIAL-BY-TRIAL TRAJECTORY ANALYSIS & GRID VISUALIZATION
% ========================================================================
%  
%  PURPOSE:
%  This script segments continuous Center of Mass (CoM) data into discrete,
%  individual experimental trials using synchronized LSL marker timestamps. 
%  It extracts the trajectory from the baseline 'NPose' event to the corresponding 
%  'TrialOffset' for each trial, and renders them in a unified multi-panel grid.
%
%  KEY LAYOUT & ALGORITHMIC METRICS:
%  1. Structural Trial Interval Bracketing: Rather than assuming sequential linear 
%     indexing, the pipeline scans forward inside each localized 'TrialOnset' to 
%     'TrialOffset' window to accurately map the unique 'NPose' coordinate.
%  2. Nearest-Neighbor LSL Time Sync: Automatically resolves minor clock drift 
%     differences between the high-rate kinematics/marker timeline and the CoM stream.
%  3. Dual-Pass Coordinate Bounding: 
%     - Pass 1: Scans all available trials to calculate absolute global 3D space limits.
%     - Pass 2: Enforces these static [X, Y, Z] bounds uniformly across every panel.
%     This prevents local auto-scaling and allows honest, direct amplitude comparisons.
%  4. Tiled Graphics Layout: Dynamically maps data onto a 4-column layout matrix 
%     using compact padding rules to minimize dead space while keeping 3D axes equal.
%
%  
%  COLOR-CODING SCHEME:
%  - Gray Path Line: Continuous trajectory history of the CoM.
%  - Green Circle: The exact moment of the 'NPose' marker.
%  - Orange Circle: The exact moment of the 'Neutral' marker.
%  - Red Circle: The exact moment of the 'Fight' marker.
%  - Maroon Square: The final terminal boundary (TrialOffset coordinate).
%
%  ========================================================================

%% 1. Initialize Environment & Select XDF File
clear; clc; close all;
[file, path] = uigetfile('*.xdf', 'Select XDF file containing Xsens and Triggers');
if isequal(file,0); disp('User cancelled'); return; end
fullPath = fullfile(path, file);

%% 2. Load and Identify Streams
fprintf('Loading XDF file... This may take a moment.\n');
streams = load_xdf(fullPath);

% Find automated stream indices based on expected Xsens/MATLAB naming patterns
cIdx = find(cellfun(@(x) contains(x.info.name, 'CenterOfMass1'), streams), 1);
tIdx = find(cellfun(@(x) contains(x.info.name, 'MATLAB_Trigger', 'IgnoreCase', true), streams), 1);

if isempty(cIdx); error('Center of Mass stream (CenterOfMass1) not found.'); end
if isempty(tIdx); error('Trigger stream (MATLAB_Trigger) not found.'); end

%% 3. Extract and Clean Multi-Stream Matrix Data
cData = double(streams{cIdx}.time_series);
cTime = streams{cIdx}.time_stamps;

tText = streams{tIdx}.time_series;
tTime = streams{tIdx}.time_stamps;

% Dynamically establish calculation sample rate directly from the CoM stream clock
srate = streams{cIdx}.info.nominal_srate;
if ischar(srate); srate = str2double(srate); end
if isnan(srate) || srate == 0; srate = 1 / mean(diff(cTime)); end

%% 4. Build Foundation EEGLAB Structure & Sync Triggers to CoM Timeline
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
    
    % Clean up text definitions for standardization
    if contains(currType, 'Fgt', 'IgnoreCase', true), currType = 'Fight'; end
    if contains(currType, 'Neu', 'IgnoreCase', true), currType = 'Neutral'; end
    
    EEG.event(actualMarkers).type = currType;
    EEG.event(actualMarkers).latency = sampleIdx;
    EEG.event(actualMarkers).duration = 1;
end
EEG = eeg_checkset(EEG);

%% 5. Identify Trial Structure Boundaries
eventTypes = {EEG.event.type};
eventLatencies = [EEG.event.latency]; 

onsetIdxs = find(cellfun(@(x) contains(x, 'TrialOnset', 'IgnoreCase', true), eventTypes));
offsetIdxs = find(cellfun(@(x) contains(x, 'TrialOffset', 'IgnoreCase', true), eventTypes));

numTrials = min(length(onsetIdxs), length(offsetIdxs));
fprintf('Analyzing global coordinate bounds for %d trials...\n', numTrials);

%% 6. First Pass: Find Absolute Global Limits Across All Trials
allX = []; allY = []; allZ = [];

for k = 1:numTrials
    currentOnsetEvtIdx = onsetIdxs(k);
    currentOffsetEvtIdx = offsetIdxs(k);
    
    searchRange = currentOnsetEvtIdx : currentOffsetEvtIdx;
    nposeSubIdx = find(cellfun(@(x) strcmpi(x, 'NPose'), eventTypes(searchRange)), 1);
    
    if ~isempty(nposeSubIdx)
        globalNPoseIdx = searchRange(nposeSubIdx);
        startSample = eventLatencies(globalNPoseIdx);
        endSample = eventLatencies(currentOffsetEvtIdx);
        
        trialCoMPath = cData(:, startSample:endSample);
        
        if ~isempty(trialCoMPath)
            allX = [allX, trialCoMPath(1,:)];
            allY = [allY, trialCoMPath(2,:)];
            allZ = [allZ, trialCoMPath(3,:)];
        end
    end
end

% Define uniform boundaries with 5cm padding
padding = 0.05; 
xLimits = [min(allX) - padding, max(allX) + padding];
yLimits = [min(allY) - padding, max(allY) + padding];
zLimits = [min(allZ) - padding, max(allZ) + padding];

%% 7. Initialize Tiled Layout Grid (4 Columns)
figGrid = figure('Name', 'CoM_Marker_Panels', 'Color', 'w', ...
                 'Units', 'normalized', 'Position', [0.05 0.05 0.9 0.85]);

numCols = 4;
numRows = ceil(numTrials / numCols); 

t = tiledlayout(numRows, numCols, 'TileSpacing', 'compact', 'Padding', 'compact');

title(t, 'CoM Paths with Event Marker In Each Trial', 'FontSize', 16, 'FontWeight', 'bold');
xlabel(t, 'X Position (m)', 'FontSize', 12);
ylabel(t, 'Y Position (m)', 'FontSize', 12);

% Style configurations
gradientSteps = 256;
cMapBlue = [linspace(0.6, 0.0, gradientSteps)', ... % Red channel fades out
            linspace(0.8, 0.1, gradientSteps)', ... % Green channel fades down
            linspace(1.0, 0.4, gradientSteps)'];    % Blue channel stays dominant

colorNeutral = [0.9290 0.6940 0.1250];  % Orange dot for Neutral moment
colorFight   = [0.8500 0.3250 0.0980];  % Red dot for Fight moment

%% 8. Second Pass: Loop Through, Detect Marker Frames, and Plot
for k = 1:numTrials
    currentOnsetEvtIdx = onsetIdxs(k);
    currentOffsetEvtIdx = offsetIdxs(k);
    
    searchRange = currentOnsetEvtIdx : currentOffsetEvtIdx;
    
    % Locate the specific baseline markers inside this trial boundary
    nposeSubIdx   = find(cellfun(@(x) strcmpi(x, 'NPose'), eventTypes(searchRange)), 1);
    neutralSubIdx = find(cellfun(@(x) strcmpi(x, 'Neutral'), eventTypes(searchRange)), 1);
    fightSubIdx   = find(cellfun(@(x) strcmpi(x, 'Fight'), eventTypes(searchRange)), 1);
    
    if isempty(nposeSubIdx)
        nexttile;
        title(sprintf('Trial %d (No NPose)', k));
        axis off;
        continue;
    end
    
    % Map indices back to global timeline sample coordinates
    sampleNPose  = eventLatencies(searchRange(nposeSubIdx));
    sampleOffset = eventLatencies(currentOffsetEvtIdx);
    
    %% 9. Render Individual Panel Graphics
    nexttile; 
    hold on; grid on;
    
    % Draw the continuous full trial trajectory loop in clean grey
    fullPathSegment = cData(:, sampleNPose:sampleOffset);
    numPoints = size(fullPathSegment, 2);
    
    if numPoints > 1
        % --- NEW: PLOT AS A GRADIENT COLOR OVER TIME ---
        % We map an array of increasing values (1 to numPoints) to act as the color indexes
        timeIndices = 1:numPoints; 
        
        % Surface uses [X;X], [Y;Y], [Z;Z] syntax to fake a 3D line with an explicit color matrix
        surface([fullPathSegment(1,:); fullPathSegment(1,:)], ...
                [fullPathSegment(2,:); fullPathSegment(2,:)], ...
                [fullPathSegment(3,:); fullPathSegment(3,:)], ...
                [timeIndices; timeIndices], ...
                'FaceColor', 'none', ...
                'EdgeColor', 'interp', ... % Interpolates colors smoothly between points
                'LineWidth', 1.5);
            
        colormap(gca, cMapBlue); % Apply the dark blue time-gradient to this panel specifically
    end
    
    % --- PLOT DOTS AT THE EXACT MOMENT OF MARKERS ---
    
    % 1. Green Dot: Exact moment of 'NPose'
    scatter3(cData(1, sampleNPose), cData(2, sampleNPose), cData(3, sampleNPose), ...
        35, 'g', 'filled');
    
    % 2. Orange Dot: Exact moment of 'Neutral' (if marker exists)
    if ~isempty(neutralSubIdx)
        sampleNeutral = eventLatencies(searchRange(neutralSubIdx));
        scatter3(cData(1, sampleNeutral), cData(2, sampleNeutral), cData(3, sampleNeutral), ...
            35, colorNeutral, 'filled');
    end
    
    % 3. Red Dot: Exact moment of 'Fight' (if marker exists)
    if ~isempty(fightSubIdx)
        sampleFight = eventLatencies(searchRange(fightSubIdx));
        scatter3(cData(1, sampleFight), cData(2, sampleFight), cData(3, sampleFight), ...
            35, colorFight, 'filled');
    end
    
    % 4. Maroon Square: Exact termination frame ('TrialOffset')
    scatter3(cData(1, sampleOffset), cData(2, sampleOffset), cData(3, sampleOffset), ...
        20, [0.5 0 0], 's', 'filled');
    
    % Panel formatting
    title(sprintf('Trial %d', k), 'FontSize', 10, 'FontWeight', 'bold');
    view(3); 
    axis equal; 
    
    xlim(xLimits);
    ylim(yLimits);
    zlim(zLimits);
end

fprintf('Success! All %d trials generated.\n', numTrials);