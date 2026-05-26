%% 1. Initialize Environment
clear; clc; close all;
[file, path] = uigetfile('*.xdf', 'Select your mBraintrain + Xsens XDF file');
if isequal(file,0); disp('User selected Cancel'); return; end
fullPath = fullfile(path, file);

%% 2. Load and Identify Streams
fprintf('Loading XDF file... This might take a minute.\n');
streams = load_xdf(fullPath);
eeglab; 

% Dynamically find indices for all three streams
eegIdx    = find(cellfun(@(x) strcmpi(x.info.type, 'EEG'), streams), 1);
xsensIdx  = find(cellfun(@(x) contains(x.info.name, 'QuaternionDatagram1'), streams), 1);
markerIdx = find(cellfun(@(x) contains(x.info.name, 'Trigger', 'IgnoreCase', true), streams), 1);

if isempty(eegIdx) || isempty(xsensIdx) || isempty(markerIdx)
    error('Could not find all required streams (EEG, Xsens, and Markers). Check stream names.');
end

%% 3. Extract Raw Data and Clocks
eegRaw   = double(streams{eegIdx}.time_series);
eegTime  = streams{eegIdx}.time_stamps;
eegSrate = str2double(streams{eegIdx}.info.nominal_srate);

xsensRaw  = double(streams{xsensIdx}.time_series);
xsensTime = streams{xsensIdx}.time_stamps;

mText = streams{markerIdx}.time_series;
mTime = streams{markerIdx}.time_stamps;

%% 4. Process Kinematics (Isolate 3D Positions)
% The segment positions are located at indices 1:3, 8:10, 15:17, etc.
numSegments = 23;
posIndices = [];
for i = 1:numSegments
    startIdx = (i-1)*7 + 1;
    posIndices = [posIndices, startIdx:startIdx+2]; %#ok<AGROW>
end
xsensPosRaw = xsensRaw(posIndices, :);

%% 5. Temporal Alignment via Resampling
% We interpolate the lower-frequency Xsens data to match the precise timestamps of the EEG data.
fprintf('Synchronizing and resampling Xsens kinematics to match EEG clock...\n');
xsensPosResampled = zeros(size(xsensPosRaw, 1), length(eegTime));
for ch = 1:size(xsensPosRaw, 1)
    % Using linear interpolation; extrap handles any slight padding mismatches at boundaries
    xsensPosResampled(ch, :) = interp1(xsensTime, xsensPosRaw(ch, :), eegTime, 'linear', 'extrap');
end

%% 6. Isolate Targeted Channels
% Extract Channels 5 (C3) and 6 (C4) from your EEG stream
if size(eegRaw, 1) < 6
    error('The EEG stream contains fewer than 6 channels. Cannot extract C3/C4.');
end
eegTargetData = eegRaw([5, 6], :); 

% Combine into a single matrix: [C3; C4; 69 Kinematic Position Tracks]
combinedData = [eegTargetData; xsensPosResampled];

%% 7. Build Unified EEGLAB Structure
EEG = eeg_emptyset();
EEG.data = combinedData;
EEG.srate = eegSrate;
EEG.xmin = 0;
[EEG.nbchan, EEG.pnts] = size(EEG.data);

% Populate Channel Labels for Easy Navigation in pop_eegplot
EEG.chanlocs = struct('labels', cell(1, EEG.nbchan));
EEG.chanlocs(1).labels = 'C3 (Ch 5)';
EEG.chanlocs(2).labels = 'C4 (Ch 6)';

% Dynamic labels for the resampled position nodes
compLabels = {'X','Y','Z'};
trackCount = 3;
for seg = 1:numSegments
    for coord = 1:3
        EEG.chanlocs(trackCount).labels = sprintf('Seg%d_%s', seg, compLabels{coord});
        trackCount = trackCount + 1;
    end
end

%% 8. Import and Sync Triggers
EEG.event = [];
for m = 1:length(mText)
    currMark = mText{m};
    if iscell(currMark); currMark = currMark{1}; end
    currMark = char(currMark);
    
    % Simplify labels for grouping/cleaner look
    if contains(currMark, 'Fgt', 'IgnoreCase', true)
        currMark = 'Fight';
    elseif contains(currMark, 'Neu', 'IgnoreCase', true)
        currMark = 'Neutral';
    end
    
    EEG.event(m).type = currMark;
    
    % Match LSL marker timestamp to the unified EEG time matrix
    [~, sampleIdx] = min(abs(eegTime - mTime(m)));
    EEG.event(m).latency = sampleIdx;
    EEG.event(m).duration = 1;
end

EEG = eeg_checkset(EEG);

%% 9. Signal Pre-processing (Applied to EEG channels only)
fprintf('Applying filtering and re-referencing to brain channels...\n');
% Re-reference only the first two channels (C3 and C4) to their common average
EEG.data(1:2, :) = pop_reref(EEG, [], 'exclude', 3:EEG.nbchan) ...
                   .data(1:2, :); 

% High-pass filter the EEG channels at 0.5Hz to eliminate slow DC drift
% (Requires the firfilt plugin installed in EEGLAB)
EEG = pop_eegfiltnew(EEG, 'locutoff', 0.5, 'plotfreqz', 0, 'channels', 1:2);

%% 10. Multi-Modal Visualization
fprintf('\nLaunching viewer. Channels 1-2 are Brainwaves, Channels 3-71 are Body Kinematics.\n');
pop_eegplot(EEG, 1, 1, 1);