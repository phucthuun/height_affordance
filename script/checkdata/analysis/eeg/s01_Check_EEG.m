%% 1. Initialize Environment
clear; clc;
[file, path] = uigetfile('*.xdf', 'Select your mBraintrain XDF file');
if isequal(file,0); disp('User selected Cancel'); return; end
fullPath = fullfile(path, file);

%% 2. Load the XDF File
% load_xdf returns a cell array of structs
streams = load_xdf(fullPath);
eeglab; 

% --- Stream Identification ---
% Dynamically find indices instead of hardcoding 1 and 2
eegIdx = find(cellfun(@(x) strcmpi(x.info.type, 'EEG'), streams), 1);
markerIdx = find(cellfun(@(x) contains(x.info.name, 'Trigger', 'IgnoreCase', true), streams), 1);

if isempty(eegIdx) || isempty(markerIdx)
    error('Could not find EEG or Marker stream. Please check your stream names in the XDF file.');
end

fprintf('Extracting Data from Stream %d (%s) and Markers from Stream %d (%s)...\n', ...
    eegIdx, streams{eegIdx}.info.name, markerIdx, streams{markerIdx}.info.name);

%% 3. Create the EEGLAB Structure
EEG = eeg_emptyset();

% Fix: Handle EEG data if it was imported as a cell array of strings
raw_data = streams{eegIdx}.time_series;
if iscell(raw_data)
    EEG.data = cellfun(@str2double, raw_data);
else
    EEG.data = double(raw_data);
end

% Set Sample Rate (Handle nominal vs string)
srate_val = streams{eegIdx}.info.nominal_srate;
if ischar(srate_val) || isstring(srate_val)
    EEG.srate = str2double(srate_val);
else
    EEG.srate = srate_val;
end

[EEG.nbchan, EEG.pnts] = size(EEG.data);

% Extract and Assign Channel Labels from XDF Metadata
try
    % Navigate the XDF nested structure to find the channel info list
    channels_meta = streams{eegIdx}.info.desc.channels.channel;
    
    % Initialize the chanlocs structure array
    EEG.chanlocs = struct('labels', cell(1, EEG.nbchan));
    
    for c = 1:EEG.nbchan
        if iscell(channels_meta)
            EEG.chanlocs(c).labels = channels_meta{c}.label;
        else
            % If there's only 1 channel, XDF doesn't store it as a cell array
            EEG.chanlocs(c).labels = channels_meta(c).label;
        end
    end
    fprintf('Successfully imported %d channel labels from XDF.\n', EEG.nbchan);
catch
    warning('Could not automatically parse channel labels from XDF metadata. Using default numbers.');
    % Fallback: Create generic labels (E1, E2, E3...) so EEGLAB doesn't crash
    for c = 1:EEG.nbchan
        EEG.chanlocs(c).labels = sprintf('Ch%d', c);
    end
end

EEG.xmin = 0;

% Setup Time Vectors for Synchronization
eegTime = streams{eegIdx}.time_stamps;
mText = streams{markerIdx}.time_series;
mTime = streams{markerIdx}.time_stamps;

%% 4. Sync and Import Markers
EEG.event = []; 
for m = 1:length(mText)
    % Fix: Handle Marker indexing (Cell vs String Array vs Char)
    if iscell(mText)
        currMark = mText{m};
    else
        currMark = mText(m);
    end
    
    % Ensure the marker type is a simple character string for EEGLAB
    if isstring(currMark) || iscell(currMark)
        currMark = char(currMark);
    end
    
    EEG.event(m).type = currMark;
    
    % Synchronization Logic:
    % Match LSL timestamp to nearest EEG sample
    [~, sampleIdx] = min(abs(eegTime - mTime(m)));
    
    EEG.event(m).latency = sampleIdx;
    EEG.event(m).duration = 1;
end

% Standard EEGLAB check to validate structure
EEG = eeg_checkset(EEG);

%% 5. Pre-processing
% Re-reference to average
EEG = pop_reref(EEG, []);

% High-pass filter at 0.5Hz to remove DC offset/drift
% Note: Requires the 'firfilt' plugin
EEG = pop_eegfiltnew(EEG, 'locutoff', 0.5);

%% 6. Grouping for Analysis (Neutral vs Fight)
% Simplify complex trigger names for easier epoching
for i = 1:length(EEG.event)
    if contains(EEG.event(i).type, 'Fgt', 'IgnoreCase', true)
        EEG.event(i).type = 'Fight';
    elseif contains(EEG.event(i).type, 'Neu', 'IgnoreCase', true)
        EEG.event(i).type = 'Neutral';
    end
end

fprintf('\nSuccess! Found %d markers. Ready for analysis.\n', length(EEG.event));

%% 7. Final Check: Visualize
pop_eegplot(EEG, 1, 1, 1);