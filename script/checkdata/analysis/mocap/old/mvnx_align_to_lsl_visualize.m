%% ========================================================================
%  XSENS MVN KINEMATICS & CENTER OF MASS (CoM) MULTI-STREAM VISUALIZATION
%  *** MVNX SOURCE VERSION — TEXT STREAMING PARSER (NO JAVA HEAP) ***
% ========================================================================
%
%  PURPOSE:
%  This script replicates the XDF-based biomechanical visualization pipeline
%  using a reprocessed .mvnx file exported from MVN Analyzer Pro. It parses
%  segment positions and CoM from the MVNX XML structure via text streaming
%  (avoiding Java heap exhaustion on large files), maps behavioral triggers
%  from a companion .xdf file onto the MVNX time axis via nearest-neighbor
%  synchronization, builds an EEGLAB structure, and renders + exports the
%  same layered 3D animation as the XDF version.
%
%  ARCHITECTURE vs. XDF VERSION:
%  - Data source    : MVNX XML (reprocessed) parsed via text streaming
%  - Time axis      : Built from recDateMSecs/recDate + frame index / srate
%  - Triggers       : Read from companion .xdf (LSL clock), synced via UTC
%  - CoM source     : <centerOfMass> XML element (reprocessed, higher quality)
%  - Segment layout : 23 Xsens segments in MVNX canonical order
%
%  DEPENDENCIES:
%  - MATLAB R2019b or later
%  - EEGLAB Toolbox  (eeg_emptyset)
%  - load_xdf.m      (for trigger stream only)
%
%  INPUT:
%    1. User-selected .mvnx file  (reprocessed kinematics + CoM)
%    2. User-selected .xdf  file  (trigger stream + LSL UTC reference)
%
%  OUTPUT:
%    1. Live 3D MATLAB Interactive Animation Window
%    2. MP4 Video: [mvnxFilename]_Xsens_CoM.mp4
%
%% ========================================================================

%% 1. Initialize Environment
clear; clc; close all;

% --- Select MVNX file ---
[mvnxFile, mvnxPath] = uigetfile('*.mvnx', 'Select reprocessed MVNX file');
if isequal(mvnxFile, 0); disp('User cancelled.'); return; end
mvnxFull = fullfile(mvnxPath, mvnxFile);

% --- Select companion XDF file (for triggers) ---
[xdfFile, xdfPath] = uigetfile('*.xdf', 'Select companion XDF file (for triggers)');
if isequal(xdfFile, 0); disp('User cancelled.'); return; end
xdfFull = fullfile(xdfPath, xdfFile);

%% 2. Parse MVNX File Header (text-based, no Java heap)
fprintf('Parsing MVNX header...\n');

fid = fopen(mvnxFull, 'r');
if fid == -1; error('Cannot open MVNX file: %s', mvnxFull); end

srate        = NaN;
mvnStartTime = NaN;
headerDone   = false;
lineCount    = 0;

while ~feof(fid) && ~headerDone
    line = fgetl(fid);
    lineCount = lineCount + 1;
    if ~ischar(line); break; end

    % --- Sample rate ---
    if isnan(srate)
        tok = regexp(line, 'frameRate\s*=\s*"([^"]+)"', 'tokens', 'once');
        if isempty(tok)
            tok = regexp(line, 'frame_rate\s*=\s*"([^"]+)"', 'tokens', 'once');
        end
        if ~isempty(tok)
            srate = str2double(tok{1});
            fprintf('  frameRate found: %g Hz\n', srate);
        end
    end

    % --- Timestamp variant 1: recDateMSecs (integer milliseconds since Unix epoch) ---
    if isnan(mvnStartTime)
        tok = regexp(line, 'recDateMSecs\s*=\s*"([^"]+)"', 'tokens', 'once');
        if ~isempty(tok)
            mvnStartTime = str2double(tok{1}) / 1000;
            fprintf('  recDateMSecs found: %.3f s (Unix)\n', mvnStartTime);
        end
    end
    % --- Timestamp variant 2: recDate — handles multiple format styles ---
    if isnan(mvnStartTime)
        tok = regexp(line, 'recDate\s*=\s*"([^"]+)"', 'tokens', 'once');
        if ~isempty(tok)
            rawDate = tok{1};
            parsed  = false;

            % Style A: ISO with ms  → "2024-03-15T10:32:00.123Z"
            try
                dt = datetime(rawDate, ...
                    'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss.SSS''Z''', ...
                    'TimeZone', 'UTC');
                mvnStartTime = posixtime(dt);
                fprintf('  recDate (ISO+ms): %.3f s (Unix)\n', mvnStartTime);
                parsed = true;
            catch; end

            % Style B: ISO no ms   → "2024-03-15T10:32:00Z"
            if ~parsed
                try
                    dt = datetime(rawDate, ...
                        'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss''Z''', ...
                        'TimeZone', 'UTC');
                    mvnStartTime = posixtime(dt);
                    fprintf('  recDate (ISO): %.3f s (Unix)\n', mvnStartTime);
                    parsed = true;
                catch; end
            end

            % Style C: C-style → "Thu May 21 12:06:16.674 2026"
            if ~parsed
                try
                    dt = datetime(rawDate, ...
                        'InputFormat', 'eee MMM dd HH:mm:ss.SSS yyyy', ...
                        'TimeZone', 'UTC');
                    mvnStartTime = posixtime(dt);
                    fprintf('  recDate (C-style): %.3f s (Unix)\n', mvnStartTime);
                    parsed = true;
                catch; end
            end

            % Style D: C-style no ms → "Thu May 21 12:06:16 2026"
            if ~parsed
                try
                    dt = datetime(rawDate, ...
                        'InputFormat', 'eee MMM dd HH:mm:ss yyyy', ...
                        'TimeZone', 'UTC');
                    mvnStartTime = posixtime(dt);
                    fprintf('  recDate (C-style no ms): %.3f s (Unix)\n', mvnStartTime);
                    parsed = true;
                catch; end
            end

            if ~parsed
                fprintf('  recDate found but format unrecognised: %s\n', rawDate);
            end
        end
    end

    % --- Timestamp variant 3: plain "date" attribute on root <mvnx> tag ---
    if isnan(mvnStartTime)
        tok = regexp(line, '\bdate\s*=\s*"([^"]+)"', 'tokens', 'once');
        if ~isempty(tok)
            try
                dt = datetime(tok{1}, ...
                    'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss.SSS''Z''', ...
                    'TimeZone', 'UTC');
                mvnStartTime = posixtime(dt);
                fprintf('  date attribute found: %.3f s (Unix)\n', mvnStartTime);
            catch
                % Not a parseable date — ignore
            end
        end
    end

    % Stop once we hit the first data frame (header is done)
    if contains(line, '<frame ') || contains(line, '<frames ')
        headerDone = true;
    end

    % Hard safety: don't scan beyond first 500 lines for header info
    if lineCount > 500
        headerDone = true;
    end
end
fclose(fid);

% --- Fallback defaults with warnings ---
if isnan(srate)
    warning('frameRate not found in header. Defaulting to 60 Hz.');
    srate = 60;
end
if isnan(mvnStartTime)
    error(['Recording timestamp not found in MVNX header (first 500 lines).\n' ...
           'Run this snippet to inspect your header attributes:\n\n' ...
           '  fid = fopen(''yourfile.mvnx'',''r'');\n' ...
           '  for i=1:50; disp(fgetl(fid)); end; fclose(fid);\n\n' ...
           'Then update the regexp pattern in Section 2 to match your attribute name.']);
end

%% 3. Parse Segment Labels (text scan)
fprintf('Parsing segment labels...\n');

fid          = fopen(mvnxFull, 'r');
segmentNames = {};

while ~feof(fid)
    line = fgetl(fid);
    if ~ischar(line); break; end

    % Match: <segment id="1" label="Pelvis"> or <segment label="Pelvis" id="1">
    tok = regexp(line, '<segment[^>]+label\s*=\s*"([^"]+)"', 'tokens', 'once');
    if ~isempty(tok)
        segmentNames{end+1} = tok{1}; %#ok<AGROW>
    end

    % Segment definitions always appear before <frames> block
    if contains(line, '<frames'); break; end
end
fclose(fid);

numSegments = length(segmentNames);
if numSegments == 0
    warning('No <segment> labels found. Defaulting to 23 (standard Xsens MVN).');
    numSegments = 23;
    segmentNames = arrayfun(@(i) sprintf('Segment%02d', i), 1:23, 'UniformOutput', false);
end
fprintf('  %d segments: %s ...\n', numSegments, strjoin(segmentNames(1:min(5,end)), ', '));

%% 4. Count Data Frames (first streaming pass)
fprintf('Counting data frames (pass 1 of 2)...\n');

fid       = fopen(mvnxFull, 'r');
numFrames = 0;

while ~feof(fid)
    line = fgetl(fid);
    if ~ischar(line); break; end
    % Match <frame index="N"> — these are the actual data frames
    % Excludes <frame type="identity">, <frame type="tpose">, etc.
    if ~isempty(regexp(line, '<frame\s+index\s*=\s*"\d+"', 'once'))
        numFrames = numFrames + 1;
    end
end
fclose(fid);
fprintf('  Data frames to parse: %d\n', numFrames);

if numFrames == 0
    error('No data frames found. Check that the MVNX file contains <frame index="N"> elements.');
end

%% 5. Extract Positions and CoM (second streaming pass)
fprintf('Streaming frame data (pass 2 of 2)...\n');

% Pre-allocate output matrices
allPos  = zeros(numSegments * 3, numFrames);   % [3*nSeg x nFrames]
comData = zeros(3, numFrames);                  % [3 x nFrames]

fid         = fopen(mvnxFull, 'r');
fi          = 0;          % frame counter
inDataFrame = false;
inPos       = false;
inCoM       = false;
posBuffer   = '';
comBuffer   = '';

while ~feof(fid)
    line = strtrim(fgetl(fid));
    if ~ischar(line); break; end

    % ---- Start of a normal data frame ----
    if ~isempty(regexp(line, '<frame\s+index\s*=\s*"\d+"', 'once'))
        inDataFrame = true;
        fi          = fi + 1;
        inPos       = false;
        inCoM       = false;
        posBuffer   = '';
        comBuffer   = '';
        if mod(fi, 500) == 0
            fprintf('  Parsed %d / %d frames...\n', fi, numFrames);
        end
        continue;
    end

    if ~inDataFrame; continue; end

    % ---- Position block (may span multiple lines) ----
    if contains(line, '<position>')
        inPos     = true;
        posBuffer = regexprep(line, '</?position>', '');
    end
    if inPos && contains(line, '</position>') && ~contains(line, '<position>')
        % Closing tag on a different line
        posBuffer = [posBuffer, ' ', regexprep(line, '</position>', '')]; %#ok<AGROW>
    end
    if inPos && contains(line, '</position>')
        vals = sscanf(posBuffer, '%f');
        if length(vals) >= numSegments * 3
            allPos(:, fi) = vals(1 : numSegments * 3);
        end
        inPos     = false;
        posBuffer = '';
    elseif inPos && ~contains(line, '<position>')
        posBuffer = [posBuffer, ' ', line]; %#ok<AGROW>
    end

    % ---- CoM block (may span multiple lines) ----
    if contains(line, '<centerOfMass>')
        inCoM     = true;
        comBuffer = regexprep(line, '</?centerOfMass>', '');
    end
    if inCoM && contains(line, '</centerOfMass>') && ~contains(line, '<centerOfMass>')
        comBuffer = [comBuffer, ' ', regexprep(line, '</centerOfMass>', '')]; %#ok<AGROW>
    end
    if inCoM && contains(line, '</centerOfMass>')
        vals = sscanf(comBuffer, '%f');
        if length(vals) >= 3
            comData(:, fi) = vals(1:3);
        end
        inCoM     = false;
        comBuffer = '';
    elseif inCoM && ~contains(line, '<centerOfMass>')
        comBuffer = [comBuffer, ' ', line]; %#ok<AGROW>
    end

    % ---- End of frame ----
    if contains(line, '</frame>')
        inDataFrame = false;
    end
end
fclose(fid);

% Trim in case pre-allocation slightly over-counted
allPos  = allPos(:,  1:fi);
comData = comData(:, 1:fi);
numFrames = fi;
fprintf('Frame extraction complete: %d frames parsed.\n', numFrames);

% Build MVNX absolute time axis (seconds, Unix epoch)
mvnTime = mvnStartTime + (0 : numFrames-1) / srate;

%% 6. Load Trigger Stream from Companion XDF
fprintf('Loading XDF trigger stream...\n');
streams = load_xdf(xdfFull);

tIdx = find(cellfun(@(x) contains(x.info.name, 'MATLAB_Trigger', 'IgnoreCase', true), streams), 1);

if isempty(tIdx)
    warning('MATLAB_Trigger stream not found in XDF. Continuing without triggers.');
    tText = {};
    tTime = [];
else
    tText = streams{tIdx}.time_series;
    tTime = streams{tIdx}.time_stamps;  % LSL time (Unix epoch after load_xdf correction)
    fprintf('  Trigger stream loaded: %d events.\n', length(tTime));
end

%% 7. Build EEGLAB Structure & Sync Triggers to MVNX Clock
EEG       = eeg_emptyset();
EEG.data  = allPos;
EEG.srate = srate;
EEG.pnts  = numFrames;
EEG.times = (0 : numFrames-1) / srate * 1000;  % ms, relative to recording start

actualMarkers = 0;
for m = 1:length(tText)
    currType = tText{m};
    if iscell(currType);  currType = currType{1};  end
    if isempty(currType); continue;                end

    % Map LSL trigger timestamp → nearest MVNX frame index
    [~, sampleIdx] = min(abs(mvnTime - tTime(m)));

    % Normalise trigger labels (mirrors XDF script)
    if contains(currType, 'Fgt', 'IgnoreCase', true); currType = 'Fight';   end
    if contains(currType, 'Neu', 'IgnoreCase', true); currType = 'Neutral'; end

    actualMarkers = actualMarkers + 1;
    EEG.event(actualMarkers).type     = currType;
    EEG.event(actualMarkers).latency  = sampleIdx;
    EEG.event(actualMarkers).duration = 1;
end
fprintf('Triggers synced: %d markers mapped to MVNX frames.\n', actualMarkers);

%% 8. Setup Animation Figure
figAnim = figure('Name', 'MVNX_3D', 'Color', 'w', 'Position', [100 100 800 600]);
hold on;

% Semi-transparent body segment dots (mirrors XDF script)
hBody = scatter3(0, 0, 0, 60, 'b', 'filled', ...
    'MarkerFaceAlpha', 0.45, ...
    'MarkerEdgeAlpha', 0.60);

% Solid opaque CoM diamond with white border
hCoM = scatter3(0, 0, 0, 150, 'k', 'd', 'filled', ...
    'MarkerEdgeColor', 'w', 'LineWidth', 1.8, ...
    'MarkerFaceAlpha', 1.0);

grid on; axis equal;
xlabel('X (m)'); ylabel('Y (m)'); zlabel('Z (m)');
title(sprintf('MVNX Kinematics — %s', mvnxFile), 'Interpreter', 'none');

minVal = min(allPos(:));
maxVal = max(allPos(:));
xlim([minVal maxVal]);
ylim([minVal maxVal]);
zlim([minVal maxVal]);

legend([hBody, hCoM], {'Body Segments', 'Center of Mass'}, 'Location', 'northeast');
view(3);

txtLabel = text(minVal + 0.1, maxVal - 0.1, maxVal - 0.1, '', ...
    'FontSize', 24, 'FontWeight', 'bold', 'Color', 'r', ...
    'HorizontalAlignment', 'left');

%% 9. Video Setup
[~, outName] = fileparts(mvnxFile);
videoPath    = fullfile(mvnxPath, [outName, '_Xsens_CoM.mp4']);
v            = VideoWriter(videoPath, 'MPEG-4');
v.FrameRate  = 30;
open(v);

highlightSamples = round(0.5 * EEG.srate);

if actualMarkers > 0
    triggerLatencies = [EEG.event.latency];
    triggerTypes     = {EEG.event.type};
else
    triggerLatencies = [];
    triggerTypes     = {};
end

frameStep = max(1, round(EEG.srate / v.FrameRate));
fprintf('Rendering video frames (%d total at %d Hz → %d FPS target)...\n', ...
    numFrames, srate, v.FrameRate);

%% 10. Animation Loop
for t = 1:frameStep:numFrames

    % --- Body segment positions: reshape [3*nSeg x 1] → [nSeg x 3] ---
    currentFrameBody = reshape(allPos(:, t), 3, numSegments)';

    % --- CoM with 1 mm Z-offset (rendering priority, same as XDF script) ---
    rOffsetZ         = 0.001;
    currentCoMLayered = [comData(1,t); comData(2,t); comData(3,t) + rOffsetZ];

    % --- Active trigger check ---
    if ~isempty(triggerLatencies)
        activeTrigIdx = find(t >= triggerLatencies & ...
                             t <= (triggerLatencies + highlightSamples), 1);
    else
        activeTrigIdx = [];
    end

    if ~isempty(activeTrigIdx)
        bodyColor    = [1 0 0];
        currentLabel = triggerTypes{activeTrigIdx};
    else
        bodyColor    = [0 0 1];
        currentLabel = '';
    end

    % --- Update graphics safely ---
    if ishandle(hBody) && ishandle(hCoM) && ishandle(txtLabel)
        set(hBody, ...
            'XData', currentFrameBody(:,1), ...
            'YData', currentFrameBody(:,2), ...
            'ZData', currentFrameBody(:,3), ...
            'CData', repmat(bodyColor, numSegments, 1));

        set(hCoM, ...
            'XData', currentCoMLayered(1), ...
            'YData', currentCoMLayered(2), ...
            'ZData', currentCoMLayered(3));

        set(txtLabel, 'String', currentLabel);
        drawnow;
        writeVideo(v, getframe(figAnim));
    else
        break;
    end
end

close(v);
fprintf('Video complete: %s\n', videoPath);
