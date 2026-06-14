%% Xsens-Loadsol Final Integration: Real-Time Sync & Video
clear; clc; close all;

%% 1. File Selection
[xFile, xPath] = uigetfile('*.xdf', 'Select Xsens XDF File');
[lFile, lPath] = uigetfile('*.txt', 'Select Loadsol TXT File');
if isequal(xFile,0) || isequal(lFile,0); return; end

%% 2. Load Xsens Data (Master)
fprintf('Loading XDF: %s...\n', xFile);
streams = load_xdf(fullfile(xPath, xFile));

xIdx = find(cellfun(@(x) contains(x.info.name, 'QuaternionDatagram1'), streams), 1);
tIdx = find(cellfun(@(x) contains(x.info.name, 'Trigger', 'IgnoreCase', true) || ...
                          contains(x.info.name, 'MATLAB_Trigger'), streams), 1);

xData = double(streams{xIdx}.time_series); 
xTime = streams{xIdx}.time_stamps;
tText = streams{tIdx}.time_series;
tTime = streams{tIdx}.time_stamps;

% Calculate Actual Sample Rate
srateX = 1 / mean(diff(xTime));
fprintf('Master Sample Rate: %.2f Hz\n', srateX);

%% 3. Load & Map Loadsol (Dynamic Column Mapping)
opts = detectImportOptions(fullfile(lPath, lFile), 'FileType', 'text');
opts.VariableNamingRule = 'preserve';
lsTable = readtable(fullfile(lPath, lFile), opts);

fid = fopen(fullfile(lPath, lFile), 'rt');
fgetl(fid); fgetl(fid); 
lineID = fgetl(fid); % Row 3 contains sensor IDs
fclose(fid);
idCells = strsplit(lineID, '\t');

idxL = find(contains(idCells, 'KGW305') & ~contains(idCells, '::'), 1);
idxR = find(contains(idCells, 'KGW304') & ~contains(idCells, '::'), 1);
idxT = find(contains(idCells, 'KYN058') & ~contains(idCells, '::'), 1, 'last');

lsTime    = lsTable{:, 1};
lsTrigger = lsTable{:, idxT};
lsForceL  = lsTable{:, idxL};
lsForceR  = lsTable{:, idxR};

%% 4. Precision Anchor Synchronization (Signature-Aware)
% Using a threshold of 10N to ignore baseline noise based on your plots
threshold = 0;
nzIdx = find(lsTrigger > threshold);
if isempty(nzIdx); error('KYN058 Trigger is empty above threshold.'); end

ls_tA = lsTime(nzIdx(1));   
ls_tB = lsTime(nzIdx(end)); 
x_tA  = xTime(1);                
x_tB  = xTime(end);              

% Fix clock drift
scaleFactor = (x_tB - x_tA) / (ls_tB - ls_tA);
lsTimeSynced = (lsTime - ls_tA) * scaleFactor + x_tA;

% Interpolate to Xsens clock
valid = ~isnan(lsTimeSynced) & ~isnan(lsForceL) & ~isnan(lsForceR);
[uTime, uI] = unique(lsTimeSynced(valid));
syncForceL = interp1(uTime, lsForceL(valid(uI)), xTime, 'linear', 0);
syncForceR = interp1(uTime, lsForceR(valid(uI)), xTime, 'linear', 0);

%% 5. Finalize EEG Structure
EEG = eeg_emptyset();
EEG.srate = srateX;
EEG.data  = [xData; syncForceL; syncForceR];
[nChan, nPnts] = size(EEG.data);
EEG.nbchan = nChan;
EEG.pnts   = nPnts;

% Initialize Channel Labels
EEG.chanlocs = struct('labels', cell(1, nChan));
for i = 1:(nChan-2); EEG.chanlocs(i).labels = sprintf('MoCap_%d', i); end
EEG.chanlocs(nChan-1).labels = 'Force_L';
EEG.chanlocs(nChan).labels   = 'Force_R';

% Map Events
for m = 1:length(tText)
    [~, sIdx] = min(abs(xTime - tTime(m)));
    EEG.event(m).type = tText{m};
    EEG.event(m).latency = sIdx;
    EEG.event(m).duration = 1;
end
EEG = eeg_checkset(EEG);

%% 6. Real-Time Video Reconstruction (First Minute from Sync Start)
[~, outName] = fileparts(xFile);
videoName = fullfile(xPath, [outName '_FirstMinute_Sync.mp4']);
v = VideoWriter(videoName, 'MPEG-4');
v.FrameRate = 30; 
open(v);

animFig = figure('Color', 'k', 'Position', [100 100 1300 700]);
actualSegments = floor(size(xData, 1) / 7);
posIndices = [];
for i = 0:(actualSegments-1); posIndices = [posIndices, (i*7 + 1):(i*7 + 3)]; end

% --- CALCULATE FIRST MINUTE RANGE FROM SYNC START ---
% We find the sample index in Xsens time that corresponds to the first Loadsol trigger
[~, syncStartIdx] = min(abs(xTime - ls_tA)); 

oneMinuteSamples = round(srateX * 60); % 60 seconds in samples
startT = syncStartIdx;
endT   = syncStartIdx + oneMinuteSamples;

% Safety check to ensure we don't exceed data length
endT = min(nPnts, endT);

stepSize = round(srateX / v.FrameRate);
fprintf('Rendering 60 seconds starting from the sync anchor...\n');

for t = startT:stepSize:endT
    if ~ishandle(animFig); break; end
    clf;
    
    % --- 3D Visualization (Left) ---
    subplot(1,2,1);
    currentPos = reshape(xData(posIndices, t), 3, [])'; 
    scatter3(currentPos(:,1), currentPos(:,2), currentPos(:,3), 40, [0.7 0.7 0.7], 'filled');
    hold on;
    
    % Feet markers (Visual confirmation of sync)
    if actualSegments >= 23
        scatter3(currentPos(23,1), currentPos(23,2), currentPos(23,3), 150, [1 0 0], 'filled', 'MarkerEdgeColor', 'w'); 
        scatter3(currentPos(19,1), currentPos(19,2), currentPos(19,3), 150, [0 0.5 1], 'filled', 'MarkerEdgeColor', 'w'); 
    end
    
    % Marker Text Overlay (Persistent for 1 second)
    recentEv = find([EEG.event.latency] <= t & [EEG.event.latency] > t - srateX, 1, 'last');
    if ~isempty(recentEv)
        text(mean(currentPos(:,1)), mean(currentPos(:,2)), 2.2, EEG.event(recentEv).type, ...
            'Color', 'y', 'FontSize', 18, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    end
    
    axis equal; grid on; view(3);
    set(gca, 'Color', 'k', 'XColor', 'w', 'YColor', 'w', 'ZColor', 'w');
    title(sprintf('Trial Time: %.2f s', xTime(t)-ls_tA), 'Color', 'w');
    
    % Camera following the subject
    xlim([mean(currentPos(:,1))-3, mean(currentPos(:,1))+3]);
    ylim([mean(currentPos(:,2))-3, mean(currentPos(:,2))+3]);
    zlim([0, 2.1]);
    
    % --- Force Graph (Right) ---
    subplot(1,2,2);
    window = round(srateX * 2.0); 
    pIdx = max(1, t-window):t;
    hL = plot(syncForceL(pIdx), 'Color', [0 0.5 1], 'LineWidth', 2.5); hold on;
    hR = plot(syncForceR(pIdx), 'Color', [1 0 0], 'LineWidth', 2.5);
    
    ylim([0, max([max(syncForceL(startT:endT)), max(syncForceR(startT:endT)), 200])]);
    title('Real-Time Force (N)', 'Color', 'w');
    set(gca, 'Color', 'k', 'XColor', 'w', 'YColor', 'w');
    
    % Use the legend fix from image_1f7b95.png analysis
    legend([hL, hR], {'Left Foot', 'Right Foot'}, 'TextColor', 'w', 'Color', 'none', 'EdgeColor', 'w', 'Location', 'northeast');
    
    drawnow limitrate;
    writeVideo(v, getframe(animFig));
    
    if mod(t-startT, stepSize*30) < stepSize
        fprintf('Progress: %.0f%%\n', ((t-startT)/(endT-startT))*100);
    end
end
close(v);
fprintf('First minute exported: %s\n', videoName);