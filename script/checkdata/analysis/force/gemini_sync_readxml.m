%% MAIN SYNCHRONIZATION AND ANIMATION SCRIPT (FLAT SCRIPT VERSION)
% All data, vectors, and tables remain persistent in your MATLAB workspace.

clear; clc; close all;

%% 0. CONFIGURATION & PATHS
LOADSOL_FILE = '\\mpib-berlin.mpg.de\Share\Projects\1223-xplo-judo\private\10_Data\sub-phucloadsol\ses-S001\force\sub-phucloadsol_ses-S001_task-training_run-001_force.txt';
MVNX_FILE    = '\\mpib-berlin.mpg.de\Share\Projects\1223-xplo-judo\private\10_Data\sub-phucloadsol\ses-S001\mocap\sub-phucloadsol_ses-S001_task-training_run-001_mocap-001_MVN System 1.mvnx';
LOADSOL_FILE = '\\mpib-berlin.mpg.de\Share\Projects\1223-xplo-judo\private\10_Data\sub-K2DJJ8\ses-S001\force\sub-K2DJJ8_ses-S001_task-heightaffordance_run-003_force.txt';
MVNX_FILE    = '\\mpib-berlin.mpg.de\Share\Projects\1223-xplo-judo\private\10_Data\sub-K2DJJ8\ses-S001\mocap\sub-K2DJJ8_ses-S001_task-heightaffordance_run-003_mocap-001.mvnx';
OUTPUT_VIDEO = 'wholebody_grf_30s.mp4';

%% 1. PARSE LOADSOL DATA
fprintf('Parsing Loadsol data...\n');
fid = fopen(LOADSOL_FILE, 'r', 'n', 'UTF-8');
if fid == -1
    error('Cannot open Loadsol file: %s', LOADSOL_FILE);
end
allLines = {};
while ~feof(fid)
    allLines{end+1} = fgetl(fid); %#ok<AGROW>
end
fclose(fid);

% Locate the column label row
labelRowIdx = find(cellfun(@(l) ischar(l) && contains(l,'Time[secs]'), allLines), 1);
if isempty(labelRowIdx)
    error('Could not find column label row containing "Time[secs]".');
end
dataStartRow = labelRowIdx + 1;
fprintf('Data starts at line %d\n', dataStartRow);

% Read all data rows
nDataLines = numel(allLines) - dataStartRow + 1;
numericData = nan(nDataLines, 14);
actualRows  = 0;
for i = dataStartRow : numel(allLines)
    line = allLines{i};
    if ~ischar(line) || isempty(strtrim(line))
        continue;
    end
    parts = strsplit(line, '\t');
    if numel(parts) < 13
        continue;
    end
    row = nan(1, 14);
    for c = 1:min(14, numel(parts))
        val = str2double(parts{c});
        if ~isnan(val)
            row(c) = val;
        end
    end
    if isnan(row(1))
        continue;
    end
    actualRows = actualRows + 1;
    numericData(actualRows, :) = row;
end
numericData = numericData(1:actualRows, :);

% Extract structures directly to workspace
loadsol.right.time    = numericData(:, 1);
loadsol.right.lateral = numericData(:, 2);
loadsol.right.medial  = numericData(:, 3);
loadsol.right.heel    = numericData(:, 4);
loadsol.right.total   = numericData(:, 5);

loadsol.left.time     = numericData(:, 6);
loadsol.left.heel     = numericData(:, 7);
loadsol.left.medial   = numericData(:, 8);
loadsol.left.lateral  = numericData(:, 9);
loadsol.left.total    = numericData(:, 10);

loadsol.ttl.time      = numericData(:, 11);
loadsol.ttl.signal    = numericData(:, 12);  
loadsol.ttl.signal2   = numericData(:, 13);  
loadsol.fs = 100;  % Hz

fprintf('Loadsol loaded: %d samples @ %d Hz\n', actualRows, loadsol.fs);

%% 2. PARSE MVNX DATA
fprintf('Parsing MVNX (may take a moment for large files)...\n');
xDoc  = xmlread(MVNX_FILE);
xRoot = xDoc.getDocumentElement();

subjectNode  = xRoot.getElementsByTagName('subject').item(0);
frameRateStr = char(subjectNode.getAttribute('frameRate'));
if isempty(frameRateStr)
    warning('Frame rate not in MVNX header — assuming 240 Hz.');
    xsens.fs = 240;
else
    xsens.fs = str2double(frameRateStr);
end

segmentNodes = xRoot.getElementsByTagName('segment');
nSegs    = segmentNodes.getLength();
segNames = cell(nSegs, 1);
for s = 0:nSegs-1
    segNames{s+1} = char(segmentNodes.item(s).getAttribute('label'));
end
xsens.segmentNames = segNames;
fprintf('Segments found: %d\n', nSegs);

frameNodes = xRoot.getElementsByTagName('frame');
nFrames    = frameNodes.getLength();
xsens.time        = zeros(nFrames, 1);
xsens.frameIdx    = zeros(nFrames, 1);
xsens.position    = zeros(nFrames, nSegs, 3);
xsens.orientation = zeros(nFrames, nSegs, 4);

fprintf('Reading %d frames...\n', nFrames);
for k = 0:nFrames-1
    frame = frameNodes.item(k);
    
    idxStr = char(frame.getAttribute('index'));
    if ~isempty(idxStr)
        xsens.frameIdx(k+1) = str2double(idxStr);
    else
        xsens.frameIdx(k+1) = k;
    end
    
    msStr = char(frame.getAttribute('time'));
    if ~isempty(msStr)
        xsens.time(k+1) = str2double(msStr);   
    else
        xsens.time(k+1) = xsens.frameIdx(k+1) * (1000 / xsens.fs);
    end
    
    posNode = frame.getElementsByTagName('position').item(0);
    if ~isempty(posNode)
        vals = str2num(char(posNode.getTextContent())); %#ok<ST2NM>
        if numel(vals) == nSegs * 3
            xsens.position(k+1, :, :) = reshape(vals, 3, nSegs).';
        end
    end
    
    oriNode = frame.getElementsByTagName('orientation').item(0);
    if ~isempty(oriNode)
        vals = str2num(char(oriNode.getTextContent())); %#ok<ST2NM>
        if numel(vals) == nSegs * 4
            xsens.orientation(k+1, :, :) = reshape(vals, 4, nSegs).';
        end
    end
end

% Robust Time Conversion Fix Logic
rawTime   = xsens.time;
dt_raw    = diff(rawTime);                  
dt_median = median(dt_raw);
dt_expect = 1000 / xsens.fs;               
cleanFrameIdx = (0:nFrames-1).'; % Clean chronological alternative vector

fprintf('Raw time attribute: first=%.0f, median dt=%.4f ms (expected %.4f ms)\n', ...
    rawTime(1), dt_median, dt_expect);

if abs(dt_median - dt_expect) < 1.0
    xsens.time = (rawTime - rawTime(1)) / 1000;
    fprintf('Time interpretation: milliseconds (elapsed or epoch) → converted to seconds.\n');
elseif abs(dt_median - dt_expect/1000) < 0.001
    xsens.time = rawTime - rawTime(1);
    fprintf('Time interpretation: already in seconds.\n');
else
    warning('Cannot determine time unit from MVNX. Reconstructing via pristine frame tracking indices.');
    xsens.time = cleanFrameIdx / xsens.fs;
end

% Ultimate protection logic if time array gets contaminated or broken
if any(isnan(xsens.time)) || xsens.time(end) <= 0 || xsens.time(end) > 86400
    warning('Xsens calculated duration calculation failed. Forcing index-based safety grid creation.');
    xsens.time = cleanFrameIdx / xsens.fs;
end
fprintf('Xsens Complete: %d frames parsed. Clean Duration: %.2f s\n', nFrames, xsens.time(end));

%% 3. SYNCHRONIZE DATA
ttlSignal = loadsol.ttl.signal;
ttlTime   = loadsol.ttl.time;
sigMin = min(ttlSignal);
sigMax = max(ttlSignal);

if (sigMax - sigMin) < 1e-6
    warning('TTL signal is flat. Using t0 = 0.');
    t0 = 0;
else
    thresh   = sigMin + 0.5*(sigMax - sigMin);
    above    = ttlSignal > thresh;
    rising   = ([0; diff(above(:))] == 1);
    pulseIdx = find(rising, 1, 'first');
    if isempty(pulseIdx)
        warning('No rising edge found. Using t0 = 0.');
        t0 = 0;
    else
        t0 = ttlTime(pulseIdx);
    end
end
fprintf('t0 detected at = %.4f s (Loadsol clock)\n', t0);

[tR, iR] = unique(loadsol.right.time, 'stable');
[tL, iL] = unique(loadsol.left.time,  'stable');

rFields = {'total','lateral','medial','heel'};
lFields = {'total','lateral','medial','heel'};
rData = struct();
for f = 1:numel(rFields)
    rData.(rFields{f}) = loadsol.right.(rFields{f})(iR);
end
lData = struct();
for f = 1:numel(lFields)
    lData.(lFields{f}) = loadsol.left.(lFields{f})(iL);
end

maskR = tR >= t0;
maskL = tL >= t0;
lsSync.time_100Hz = tR(maskR) - t0;   
lsSync.fs         = loadsol.fs;
lsSync.t0_loadsol = t0;

for f = 1:numel(rFields)
    lsSync.right.(rFields{f}) = rData.(rFields{f})(maskR);
end
for f = 1:numel(lFields)
    lsSync.left.(lFields{f})  = lData.(lFields{f})(maskL);
end
ttl_mask          = ttlTime >= t0;
lsSync.ttl.time   = ttlTime(ttl_mask) - t0;
lsSync.ttl.signal = ttlSignal(ttl_mask);

xsSync.time        = xsens.time;
xsSync.orientation = xsens.orientation;
xsSync.fs          = xsens.fs;

tCommon = xsSync.time;
tR_trim = tR(maskR) - t0;
tL_trim = tL(maskL) - t0;

validR = tCommon >= tR_trim(1)   & tCommon <= tR_trim(end);
validL = tCommon >= tL_trim(1)   & tCommon <= tL_trim(end);

if sum(validR) < 2 || sum(validL) < 2
    error('Zero overlap calculation error remaining between device matrices.');
end

for f = 1:numel(rFields)
    fd  = rFields{f};
    out = nan(size(tCommon));
    out(validR) = interp1(tR_trim, rData.(rFields{f})(maskR), tCommon(validR), 'linear');
    lsSync.right.([fd '_240Hz']) = out;
end
for f = 1:numel(lFields)
    fd  = lFields{f};
    out = nan(size(tCommon));
    out(validL) = interp1(tL_trim, lData.(lFields{f})(maskL), tCommon(validL), 'linear');
    lsSync.left.([fd '_240Hz']) = out;
end
lsSync.commonTime = tCommon;

%% 4. RUN SYNC DIAGNOSTIC REPORT
fprintf('\n========== SYNC DIAGNOSTIC ==========\n');
fprintf('\n[1] Loadsol raw right.time\n');
fprintf('    Length       : %d samples\n', numel(loadsol.right.time));
fprintf('    Range        : [%.4f, %.4f] s\n', loadsol.right.time(1), loadsol.right.time(end));
diffs = diff(loadsol.right.time);
fprintf('    Non-monotonic steps : %d\n', sum(diffs <= 0));

fprintf('\n[2] TTL sync signal (KYN058)\n');
fprintf('    Rising edges : %d\n', sum(rising));
fprintf('    t0 (first pulse) : %.4f s\n', t0);

fprintf('\n[3] lsSync.time_100Hz (after trim)\n');
fprintf('    Length       : %d samples\n', numel(lsSync.time_100Hz));
fprintf('    Range        : [%.4f, %.4f] s\n', lsSync.time_100Hz(1), lsSync.time_100Hz(end));

fprintf('\n[4] xsSync.time (Xsens grid)\n');
fprintf('    Length       : %d samples\n', numel(xsSync.time));
fprintf('    Range        : [%.4f, %.4f] s\n', xsSync.time(1), xsSync.time(end));

fprintf('\n[5] Overlap window coordinates\n');
overlapStart = max(lsSync.time_100Hz(1), xsSync.time(1));
overlapEnd   = min(lsSync.time_100Hz(end), xsSync.time(end));
fprintf('    Overlap window: [%.4f, %.4f] s\n', overlapStart, overlapEnd);

fprintf('\n[6] lsSync.right.total_240Hz validation\n');
fprintf('    NaN count: %d / %d\n', sum(isnan(lsSync.right.total_240Hz)), numel(lsSync.right.total_240Hz));
fprintf('\n======================================\n');

%% 5. GET SKELETON BONE INDEX COUPLINGS
idx_match = @(name) find(contains(xsens.segmentNames, name, 'IgnoreCase', true), 1);
boneDefs = {
    'Pelvis','L5'; 'L5','L3'; 'L3','T12'; 'T12','T8'; 'T8','Neck'; 'Neck','Head';
    'T8','RightShoulder'; 'RightShoulder','RightUpperArm'; 'RightUpperArm','RightForeArm'; 'RightForeArm','RightHand';
    'T8','LeftShoulder'; 'LeftShoulder','LeftUpperArm'; 'LeftUpperArm','LeftForeArm'; 'LeftForeArm','LeftHand';
    'Pelvis','RightUpperLeg'; 'RightUpperLeg','RightLowerLeg'; 'RightLowerLeg','RightFoot'; 'RightFoot','RightToe';
    'Pelvis','LeftUpperLeg'; 'LeftUpperLeg','LeftLowerLeg'; 'LeftLowerLeg','LeftFoot'; 'LeftFoot','LeftToe';
};
bones = zeros(size(boneDefs,1), 2);
for b = 1:size(boneDefs,1)
    bones(b,1) = idx_match(boneDefs{b,1});
    bones(b,2) = idx_match(boneDefs{b,2});
end
nBones = size(bones, 1);

%% 6. ANIMATE AND SAVE MP4 VIDEO
T_END      = 80;          
PLAYBACK_FPS = 30;        
XS_SKIP    = round(xsens.fs / PLAYBACK_FPS);   
TRAIL_S    = 5;           

frameIdx30 = find(xsens.time <= T_END);
frameIdx30 = frameIdx30(1 : XS_SKIP : end);   
nVideoFrames = numel(frameIdx30);

pos30 = xsens.position(frameIdx30, :, :);   
xLim  = [min(pos30(:,:,1),[],'all')-0.3,  max(pos30(:,:,1),[],'all')+0.3];
yLim  = [min(pos30(:,:,2),[],'all')-0.3,  max(pos30(:,:,2),[],'all')+0.3];
zLim  = [0,  max(pos30(:,:,3),[],'all')+0.3];

tXs   = xsens.time(frameIdx30);         
tLs   = lsSync.time_100Hz;
fR = interp1(tLs, lsSync.right.total, tXs, 'linear', NaN);
fL = interp1(tLs, lsSync.left.total,  tXs, 'linear', NaN);

allForce = [lsSync.right.total; lsSync.left.total];
fMax = max(allForce(~isnan(allForce))) * 1.05;
if isempty(fMax) || ~isfinite(fMax), fMax = 1000; end

vw = VideoWriter(OUTPUT_VIDEO, 'MPEG-4');
vw.FrameRate = PLAYBACK_FPS;
vw.Quality   = 92;
open(vw);

fig = figure('Color','k', 'Position',[50 50 1920 1080], 'Visible','off');          
ax3d = subplot(1,2,1,'Parent',fig);
set(ax3d,'Color','k','XColor','w','YColor','w','ZColor','w','GridColor',[0.3 0.3 0.3],'GridAlpha',0.4);
hold(ax3d,'on'); grid(ax3d,'on');
xlim(ax3d, xLim); ylim(ax3d, yLim); zlim(ax3d, zLim);
view(ax3d, 35, 20); ax3d.DataAspectRatio = [1 1 1];

boneColor  = [0.20 0.60 1.00];   rightColor = [1.00 0.35 0.35];   leftColor = [0.35 1.00 0.55];   
hBones = gobjects(nBones, 1);
for b = 1:nBones
    bname = xsens.segmentNames{bones(b,2)};
    if contains(bname,'Right','IgnoreCase',true), col = rightColor;
    elseif contains(bname,'Left','IgnoreCase',true), col = leftColor;
    else, col = boneColor; end
    hBones(b) = plot3(ax3d, [0 0],[0 0],[0 0], '-o','Color',col,'LineWidth',2.0,'MarkerSize',4,'MarkerFaceColor',col);
end

hHead = plot3(ax3d, 0,0,0, 'o', 'MarkerSize',12,'MarkerFaceColor',[1 0.85 0.6], 'MarkerEdgeColor','w','LineWidth',1.2);
hTime = text(ax3d, xLim(1)+0.05, yLim(2)-0.05, zLim(2)-0.05, 't = 0.00 s','Color','w','FontSize',11,'FontWeight','bold');

ax2d = subplot(1,2,2,'Parent',fig);
set(ax2d,'Color','k','XColor','w','YColor','w', 'GridColor',[0.3 0.3 0.3],'GridAlpha',0.4);
hold(ax2d,'on'); grid(ax2d,'on'); ylim(ax2d,[0 fMax]);
hFR = plot(ax2d, NaN, NaN, '-', 'Color',rightColor, 'LineWidth',1.8,'DisplayName','Right foot');
hFL = plot(ax2d, NaN, NaN, '-', 'Color',leftColor,  'LineWidth',1.8,'DisplayName','Left foot');
hVline = xline(ax2d, 0, '--','Color',[1 1 0.4],'LineWidth',1.2);
hFR_fill = fill(ax2d, NaN, NaN, rightColor, 'FaceAlpha',0.15, 'EdgeColor','none','HandleVisibility','off');
hFL_fill = fill(ax2d, NaN, NaN, leftColor,  'FaceAlpha',0.15, 'EdgeColor','none','HandleVisibility','off');
legend(ax2d,'show','TextColor','w','Color','k');

headIdx = find(contains(xsens.segmentNames,'Head','IgnoreCase',true),1);
if isempty(headIdx), headIdx = 7; end



fprintf('Exporting video... 0%%'); % Initial message

for vi = 1:nVideoFrames
    fi  = frameIdx30(vi);
    t   = xsens.time(fi);
    pos = squeeze(xsens.position(fi, :, :));   
    
    for b = 1:nBones
        p1 = bones(b,1);  p2 = bones(b,2);
        set(hBones(b), 'XData', [pos(p1,1) pos(p2,1)], 'YData', [pos(p1,2) pos(p2,2)], 'ZData', [pos(p1,3) pos(p2,3)]);
    end
    set(hHead, 'XData', pos(headIdx,1), 'YData', pos(headIdx,2), 'ZData', pos(headIdx,3));
    set(hTime, 'String', sprintf('t = %.2f s', t));
    
    winStart = max(0, t - TRAIL_S);
    win = tXs >= winStart & tXs <= t;
    tWin  = tXs(win); fRWin = fR(win); fLWin = fL(win);
    set(hFR, 'XData', tWin, 'YData', fRWin);
    set(hFL, 'XData', tWin, 'YData', fLWin);
    xlim(ax2d, [winStart, winStart + TRAIL_S]);
    hVline.Value = t;
    if numel(tWin) >= 2
        set(hFR_fill,'XData',[tWin; flipud(tWin)], 'YData',[fRWin; zeros(size(fRWin))]);
        set(hFL_fill,'XData',[tWin; flipud(tWin)], 'YData',[fLWin; zeros(size(fLWin))]);
    end
    
    drawnow limitrate;
    writeVideo(vw, getframe(fig));
    
    % ─── ADD PROGRESS TRACKING HERE ─────────────────────────────────
    % Print the progress percentage dynamically on a single line
    if mod(vi, 10) == 0 || vi == nVideoFrames
        pct = (vi / nVideoFrames) * 100;
        fprintf('\b\b\b\b%3.0f%%', pct); 
    end
    % ────────────────────────────────────────────────────────────────
end
fprintf('\n'); % Move to a clean line after export finishes
close(vw); close(fig);
fprintf('Video saved → %s\n', OUTPUT_VIDEO);

%% 7. VISUALIZE FIRST 30 SECONDS (PLOTS)
ls_m = lsSync.commonTime <= T_END & ~isnan(lsSync.right.total_240Hz);
xs_m = xsSync.time       <= T_END;
ttl_m = lsSync.ttl.time  <= T_END;
t_ls  = lsSync.commonTime(ls_m);
t_xs  = xsSync.time(xs_m);
t_ttl = lsSync.ttl.time(ttl_m);

% Inline manual quaternion computation logic
q = xsSync.orientation(xs_m, :);
w = q(:,1); x = q(:,2); y = q(:,3); z = q(:,4);
yaw   = atan2d(2.*(w.*z + x.*y), 1 - 2.*(y.^2 + z.^2));
pitch = asind( 2.*(w.*y - z.*x));
roll  = atan2d(2.*(w.*x + y.*z), 1 - 2.*(x.^2 + y.^2));
euler_deg   = [yaw, pitch, roll];

fig2 = figure('Name','Xsens LINK + Loadsol Data Check','Color','w','Position',[60 60 1300 860]);
ax1 = subplot(4,1,1);
plot(t_ls, lsSync.right.total_240Hz(ls_m), 'Color','#D62728','LineWidth',1.3); hold on;
plot(t_ls, lsSync.left.total_240Hz(ls_m),  'Color','#1F77B4','LineWidth',1.3); grid on; xlim([0 T_END]);

ax2 = subplot(4,1,2);
plot(t_ls, lsSync.right.heel_240Hz(ls_m)); hold on;
plot(t_ls, lsSync.right.medial_240Hz(ls_m));
plot(t_ls, lsSync.right.lateral_240Hz(ls_m)); grid on; xlim([0 T_END]);

ax3 = subplot(4,1,3);
plot(t_xs, euler_deg(:,1)); hold on;
plot(t_xs, euler_deg(:,2));
plot(t_xs, euler_deg(:,3)); grid on; xlim([0 T_END]);

ax4 = subplot(4,1,4);
plot(t_ttl, lsSync.ttl.signal(ttl_m), 'Color','#333333'); grid on; xlim([0 T_END]);
linkaxes([ax1 ax2 ax3 ax4], 'x');

%% 8. SAVE WORKSPACE MAT FILE
save('synchronized_data.mat','lsSync','xsSync','loadsol','xsens');
fprintf('All done. Variables are live and ready for inspection in your Workspace panel.\n');