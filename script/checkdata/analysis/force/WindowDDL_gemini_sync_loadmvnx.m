%% MAIN SYNCHRONIZATION AND ANIMATION SCRIPT (FLAT SCRIPT VERSION)
% All data, vectors, and tables remain persistent in your MATLAB workspace.

clear; clc; close all;

%% 0. INTERACTIVE BIDS CONFIGURATION & AUTOMATED PATTERNS via subject_info2
fprintf('============ BIDS DATA IMPORT INITIALIZATION ============\n');

% Define your pipeline defaults for the dialog function inputs
BASE_LOC     = '\\mpib-berlin.mpg.de\Share\Projects\1223-xplo-judo\private\10_Data';
DEFAULT_TASK = 't'; % Default to training

% --- Call your custom subject_info2 dialog window function ---
% Make sure subject_info2.m is in your current path or folder
[raw_sub, raw_ses, numeric_run, task_name] = subject_info2(BASE_LOC, DEFAULT_TASK);

% --- Reconstruct Standardized BIDS Compliant Labels ---
% 1. Handle Subject ID prefixing
if exist(fullfile(BASE_LOC, raw_sub), 'dir')
    sub_id = raw_sub; % Use exactly what was typed (e.g., 'K2DJJ8')
else
    % If not, check if it exists with the 'sub-' prefix added
    if startsWith(raw_sub, 'sub-', 'IgnoreCase', true)
        sub_id = raw_sub;
    else
        sub_id = ['sub-' raw_sub]; % Try fallback prefixing (e.g., 'sub-phucloadsol')
    end
end

% 2. Reconstruct Session ID to 'ses-S001' format from function output
SESSION_ID = ['ses-S' raw_ses]; 

% 3. Convert numeric run index to a 3-digit padded string (e.g., 1 -> '001')
run_num = sprintf('%03d', numeric_run);

% --- Assemble Root Path and Target Folders ---
PARTICIPANT_ROOT = fullfile(BASE_LOC, sub_id);
FORCE_DIR        = fullfile(PARTICIPANT_ROOT, SESSION_ID, 'force');
MOCAP_DIR        = fullfile(PARTICIPANT_ROOT, SESSION_ID, 'mocap');
OUTPUT_DIR       = fullfile(PARTICIPANT_ROOT, SESSION_ID, 'output');

% Verify root folder accessibility right away
if ~exist(PARTICIPANT_ROOT, 'dir')
    error('BIDS PATH ERROR: Target participant directory does not exist:\n%s', PARTICIPANT_ROOT);
end

% Automatically build the output destination folder if missing
if ~exist(OUTPUT_DIR, 'dir')
    mkdir(OUTPUT_DIR);
end

% --- Construct BIDS File Search Patterns ---
search_pattern = sprintf('%s_%s_task-%s_run-%s*', sub_id, SESSION_ID, task_name, run_num);

% --- Scan and Verify target files ---
% Search for the Loadsol force text file
txtFiles = dir(fullfile(FORCE_DIR, [search_pattern, '.txt']));
if isempty(txtFiles)
    error('BIDS SCAN ERROR: No .txt file matching pattern "%s" found in:\n%s', [search_pattern, '.txt'], FORCE_DIR);
end
LOADSOL_FILE = fullfile(FORCE_DIR, txtFiles(1).name);

% Search for the Xsens MVNX motion capture file
mvnxFiles = dir(fullfile(MOCAP_DIR, [search_pattern, '.mvnx']));
if isempty(mvnxFiles)
    error('BIDS SCAN ERROR: No .mvnx file matching pattern "%s" found in:\n%s', [search_pattern, '.mvnx'], MOCAP_DIR);
end
MVNX_FILE = fullfile(MOCAP_DIR, mvnxFiles(1).name);

% --- Construct BIDS Compliant Output File Names ---
base_output_name = sprintf('%s_%s_task-%s_run-%s_loadsol_xsens', sub_id, SESSION_ID, task_name, run_num);

OUTPUT_VIDEO = fullfile(OUTPUT_DIR, [base_output_name, '.mp4']);
OUTPUT_MAT   = fullfile(OUTPUT_DIR, [base_output_name, '.mat']);
OUTPUT_PDF   = fullfile(OUTPUT_DIR, [base_output_name, '_diagnostic.pdf']);

% Print file routing status report to console
fprintf('\n================ BIDS FILE ROUTING STATUS ================\n');
fprintf('Participant ID   : %s\n', sub_id);
fprintf('Session ID       : %s\n', SESSION_ID);
fprintf('Task Name        : %s\n', task_name);
fprintf('Run Number       : %s\n', run_num);
fprintf('Target Loadsol   : %s\n', txtFiles(1).name);
fprintf('Target Xsens     : %s\n', mvnxFiles(1).name);
fprintf('Target Output Dir: %s\n', OUTPUT_DIR);
fprintf('===========================================================\n\n');

%% 1. PARSE LOADSOL DATA
fprintf('Parsing Loadsol data...\n');

% Open file with standard reading permissions
fid = fopen(LOADSOL_FILE, 'r');
if fid == -1
    error('File open error. Verify the path name exists: %s', LOADSOL_FILE);
end

% Skip headers dynamically to reach numerical rows (Data starts on line 5)
for i = 1:4
    fgets(fid); 
end

% Read the remaining tab-delimited or space-delimited text data matrix
data = fscanf(fid, '%f', [13, Inf]).'; 
fclose(fid);

if isempty(data)
    error('LOADSOL IMPORT FAILURE: No data vectors extracted. Check column formats.');
end

nRows = size(data, 1);
fprintf('Loadsol loaded: %d samples @ 100 Hz\n', nRows);

% --- MAP COLUMNS BASED ON THE SPECIFIC FILE HEADERS ---
loadsol.time  = data(:, 1);  % First timestamp track acts as the global timeline

% Left Foot Data Matrix (Columns 1-4)
loadsol.left.heel    = data(:, 2);
loadsol.left.medial  = data(:, 3);
loadsol.left.lateral = data(:, 4);
loadsol.left.total   = data(:, 5); % Total sum column for Left foot

% Right Foot Data Matrix (Columns 5-8)
loadsol.right.lateral = data(:, 7);
loadsol.right.medial  = data(:, 8);
loadsol.right.heel    = data(:, 9);
loadsol.right.total   = data(:, 10); % Total sum column for Right foot

% TTL Sync Signal Column (Column 11 in your layout)
loadsol.sync = data(:, 11); 

% --- Sanity Check Verification Plots ---
fprintf('Loadsol Data Check: Left Max = %.1f N | Right Max = %.1f N\n', ...
    max(loadsol.left.total), max(loadsol.right.total));

%% 2. PARSE MVNX DATA (VIA OFFICIAL XSENS LOAD_MVNX)
fprintf('Parsing MVNX file using load_mvnx...\n');

% Call the official Xsens parser function
tree = load_mvnx(MVNX_FILE);

% --- Frame rate extraction ---
if isfield(tree, 'subject') && isfield(tree.subject, 'frameRate')
    xsens.fs = double(tree.subject.frameRate);
elseif isfield(tree, 'metaData') && isfield(tree.metaData, 'frameRate')
    xsens.fs = double(tree.metaData.frameRate);
else
    warning('Frame rate field missing in tree structure — assuming 240 Hz.');
    xsens.fs = 240;
end

% --- Segment labels extraction ---
% Xsens structure tracks segments nested under subject.segments.segment
segmentArray = tree.subject.segments.segment;
nSegs        = numel(segmentArray);
segNames     = cell(nSegs, 1);
for s = 1:nSegs
    segNames{s} = segmentArray(s).label;
end
xsens.segmentNames = segNames;
fprintf('Segments found: %d\n', nSegs);

% --- Extract frames, tracking arrays, and data matrices ---
% Xsens frames array maps under subject.frames.frame
framesData = tree.subject.frames.frame;
nFrames    = numel(framesData);
fprintf('Extracting raw numerical tracking matrices for %d frames...\n', nFrames);

% Allocate workspace matrices matching the original array sizes
xsens.frameIdx    = zeros(nFrames, 1);
xsens.time        = zeros(nFrames, 1);
xsens.position    = zeros(nFrames, nSegs, 3);
xsens.orientation = zeros(nFrames, nSegs, 4);

fprintf('Extracting raw numerical tracking matrices for %d frames...\n', nFrames);

for k = 1:nFrames
    % 1. Indices and timestamps tracking extraction
    if isfield(framesData(k), 'index') && ~isempty(framesData(k).index)
        xsens.frameIdx(k) = double(framesData(k).index);
    else
        xsens.frameIdx(k) = k - 1; 
    end
    
    if isfield(framesData(k), 'time') && ~isempty(framesData(k).time)
        xsens.time(k) = double(framesData(k).time);
    elseif isfield(framesData(k), 'ms') && ~isempty(framesData(k).ms)
        xsens.time(k) = double(framesData(k).ms); % Alternative Xsens label
    else
        xsens.time(k) = xsens.frameIdx(k) * (1000 / xsens.fs);
    end
    
    % 2. Fast Reshaping of Flat Global Frame Data Vectors
    % Position: Reshape flat 1x69 vector to 23x3 matrix slice
    if isfield(framesData(k), 'position') && ~isempty(framesData(k).position)
        rawPos = double(framesData(k).position);
        if numel(rawPos) == nSegs * 3
            xsens.position(k, :, :) = reshape(rawPos, 3, nSegs).';
        end
    end
    
    % Orientation: Reshape flat 1x92 vector to 23x4 matrix slice
    if isfield(framesData(k), 'orientation') && ~isempty(framesData(k).orientation)
        rawOri = double(framesData(k).orientation);
        if numel(rawOri) == nSegs * 4
            xsens.orientation(k, :, :) = reshape(rawOri, 4, nSegs).';
        end
    end
end

% --- Pristine Timeline Construction & Safety Checks ---
rawTime       = xsens.time;
dt_raw        = diff(rawTime);                  
dt_median     = median(dt_raw);
dt_expect     = 1000 / xsens.fs;               
cleanFrameIdx = (0:nFrames-1).'; 

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

% Final defensive block against missing timelines
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
T_END      = 30;          
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



fprintf('Exporting video... 0%%\n'); % Initial message

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
save(OUTPUT_MAT, 'lsSync', 'xsSync', 'loadsol', 'xsens');
fprintf('All done. Variables saved to BIDS file → %s\n', OUTPUT_MAT);