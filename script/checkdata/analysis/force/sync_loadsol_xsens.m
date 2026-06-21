%% MAIN SYNCHRONIZATION AND ANIMATION SCRIPT (DYNAMIC TABLE-METADATA PARSED VERSION)
% All data, vectors, and tables remain persistent in your MATLAB workspace.
clear; clc; close all;

%% 0. INTERACTIVE BIDS CONFIGURATION & AUTOMATED PATTERNS via subject_info2
fprintf('============ BIDS DATA IMPORT INITIALIZATION ============\n');
% --- Set Up Source and Derivative Root Paths ---
BASE_LOC        = '\\mpib-berlin.mpg.de\Share\Projects\1223-xplo-judo\private\10_Data\sourcedata';
DERIVATIVES_LOC = '\\mpib-berlin.mpg.de\Share\Projects\1223-xplo-judo\private\10_Data\derivatives';
DEFAULT_TASK    = 'h'; 

% --- Call your custom subject_info2 dialog window function ---
[raw_sub, raw_ses, numeric_run, task_name] = subject_info2(BASE_LOC, DEFAULT_TASK);

% --- Reconstruct Standardized BIDS Compliant Labels ---
if exist(fullfile(BASE_LOC, raw_sub), 'dir')
    sub_id = raw_sub; 
else
    if startsWith(raw_sub, 'sub-', 'IgnoreCase', true)
        sub_id = raw_sub;
    else
        sub_id = ['sub-' raw_sub]; 
    end
end
SESSION_ID = ['ses-S' raw_ses]; 
run_num    = sprintf('%03d', numeric_run);

% --- Assemble Root Paths and Target Folders ---
PARTICIPANT_ROOT = fullfile(BASE_LOC, sub_id);
FORCE_DIR        = fullfile(PARTICIPANT_ROOT, SESSION_ID, 'force');
MOCAP_DIR        = fullfile(PARTICIPANT_ROOT, SESSION_ID, 'motion');

% Verify raw data folder accessibility right away
if ~exist(PARTICIPANT_ROOT, 'dir')
    error('BIDS PATH ERROR: Target participant directory does not exist:\n%s', PARTICIPANT_ROOT);
end

% --- Establish BIDS Derivatives Target Directory ---
PIPELINE_NAME = 'sync_loadsol_xsens';
OUTPUT_DIR    = fullfile(DERIVATIVES_LOC, PIPELINE_NAME, sub_id, SESSION_ID, 'motion');
if ~exist(OUTPUT_DIR, 'dir')
    mkdir(OUTPUT_DIR);
end

% --- Construct BIDS File Search Patterns ---
search_pattern = sprintf('%s_%s_task-%s_run-%s*', sub_id, SESSION_ID, task_name, run_num);

% --- Scan and Verify target files ---
txtFiles = dir(fullfile(FORCE_DIR, [search_pattern, '.txt']));
if isempty(txtFiles)
    error('BIDS SCAN ERROR: No .txt file matching pattern "%s" found in:\n%s', [search_pattern, '.txt'], FORCE_DIR);
end
LOADSOL_FILE = fullfile(FORCE_DIR, txtFiles(1).name);

mvnxFiles = dir(fullfile(MOCAP_DIR, [search_pattern, '.mvnx']));
if isempty(mvnxFiles)
    error('BIDS SCAN ERROR: No .mvnx file found in: %s', MOCAP_DIR);
end

file_names = {mvnxFiles.name};
matching_idx = find(startsWith(file_names, sprintf('%s_%s_task-%s_run-%s', sub_id, SESSION_ID, task_name, run_num)), 1);
if isempty(matching_idx)
    error('BIDS SCAN ERROR: No matching .mvnx trace found for run-%s', run_num);
end
MVNX_FILE = fullfile(MOCAP_DIR, mvnxFiles(matching_idx).name);

% --- Construct Standard BIDS Derivatives Compliant File Names ---
base_output_name = sprintf('%s_%s_task-%s_run-%s_desc-synchronized', sub_id, SESSION_ID, task_name, run_num);
OUTPUT_VIDEO = fullfile(OUTPUT_DIR, [base_output_name, '_motion.mp4']);
OUTPUT_MAT   = fullfile(OUTPUT_DIR, [base_output_name, '_motion.mat']);
OUTPUT_PDF   = fullfile(OUTPUT_DIR, [base_output_name, '_diagnostic.pdf']);

fprintf('\n================ BIDS FILE ROUTING STATUS ================\n');
fprintf('Participant ID   : %s\n', sub_id);
fprintf('Session ID       : %s\n', SESSION_ID);
fprintf('Task Name        : %s\n', task_name);
fprintf('Run Number       : %s\n', run_num);
fprintf('Target Loadsol   : %s\n', txtFiles(1).name);
fprintf('Target Xsens     : %s\n', mvnxFiles(matching_idx).name);
fprintf('BIDS Derivatives : %s\n', OUTPUT_DIR);
fprintf('===========================================================\n\n');

%% 1. PARSE LOADSOL DATA (COMBINED METRIC_SENSOR HEADER MAPPING)
fprintf('Parsing Loadsol data using [Unit/Metric]_[Sensor] header mapping...\n');

fid = fopen(LOADSOL_FILE, 'r', 'n', 'UTF-8');
if fid == -1, error('Cannot open Loadsol file: %s', LOADSOL_FILE); end
allLines = {};
while ~feof(fid), allLines{end+1} = fgetl(fid); end
fclose(fid);

% Find line index matching the row containing 'Time[secs]' (Row 4 in R)
unitRowIdx = find(cellfun(@(l) ischar(l) && contains(l,'Time[secs]'), allLines), 1);
if isempty(unitRowIdx), error('Could not resolve structural template lines from text headers.'); end
labelRowIdx = unitRowIdx - 1; % The row right before it (Row 3 in R)

% Split both metadata rows on tab markers
label_cells = strsplit(allLines{labelRowIdx}, '\t', 'CollapseDelimiters', false);
unit_cells  = strsplit(allLines{unitRowIdx}, '\t', 'CollapseDelimiters', false);

% Reconcile length mismatches if trailing tabs got dropped
max_cols = max(length(label_cells), length(unit_cells));
if length(label_cells) < max_cols, label_cells{max_cols} = ''; end
if length(unit_cells) < max_cols,  unit_cells{max_cols}  = ''; end

% Build combined clean name strings according to your R formatting pattern: "Unit_Label"
combined_headers = cell(1, max_cols);
for i = 1:max_cols
    lbl  = strtrim(label_cells{i});
    unit = strtrim(unit_cells{i});
    
    % Combine unit/metric row FIRST, then underscore, then label row
    combined_headers{i} = sprintf('%s%d%s',unit, i,  lbl);
    
    % Clean special characters to ensure valid MATLAB table property variable naming
    combined_headers{i} = regexprep(combined_headers{i}, '[\[\]\-:]', '_');
    if isempty(combined_headers{i}), combined_headers{i} = sprintf('Var%d', i); end
end

% Set up import options to load numerical data below the header lines
opts = detectImportOptions(LOADSOL_FILE, 'FileType', 'text', 'Delimiter', '\t');
opts.DataLines = [unitRowIdx + 1, Inf];

% CRITICAL FIX: Tell MATLAB to allow duplicate names temporarily by using modify rule during read, 
% then cleanly assign our explicit unique indices afterwards.
opts.VariableNamingRule = 'modify'; 
opts.VariableNames = opts.VariableNames(1:min(max_cols, length(opts.VariableNames)));
opts.SelectedVariableNames = opts.VariableNames;

allDataTab = readtable(LOADSOL_FILE, opts);

% Safe Overwrite: Re-assign exactly corresponding to our Unit_Label strings
allDataTab.Properties.VariableNames(1:width(allDataTab)) = combined_headers(1:width(allDataTab));
vars = allDataTab.Properties.VariableNames;

% --- DYNAMIC TARGET RESOLUTION VIA "UNIT_LABEL" VARIABLE NAMES ---
name_R_lat  = vars{contains(vars, 'KGW304_R') & contains(vars, 'lateral')};
name_R_med  = vars{contains(vars, 'KGW304_R') & contains(vars, 'medial')};
name_R_heel = vars{contains(vars, 'KGW304_R') & contains(vars, 'heel')};
name_R_tot  = vars{contains(vars, 'KGW304_R') & ~contains(vars, 'lateral') & ~contains(vars, 'medial') & ~contains(vars, 'heel') & contains(vars, 'Force_N')};

name_L_heel = vars{contains(vars, 'KGW305_L') & contains(vars, 'heel')};
name_L_med  = vars{contains(vars, 'KGW305_L') & contains(vars, 'medial')};
name_L_lat  = vars{contains(vars, 'KGW305_L') & contains(vars, 'lateral')};
name_L_tot  = vars{contains(vars, 'KGW305_L') & ~contains(vars, 'lateral') & ~contains(vars, 'medial') & ~contains(vars, 'heel') & contains(vars, 'Force_N')};

name_ttl_sig = vars{contains(vars, 'KYN058') & ~contains(vars, 'area') & contains(vars, 'Force_N')};

% Map column indices dynamically to find spatial neighboring timeline anchors
idx_R_tot   = find(strcmp(vars, name_R_tot), 1);
idx_L_tot   = find(strcmp(vars, name_L_tot), 1);
idx_ttl_sig = find(strcmp(vars, name_ttl_sig), 1);

% Identify the "Time_secs__" indices relative to each structural data block layout
all_time_indices = find(startsWith(vars, 'Time_secs'));
if length(all_time_indices) >= 3
    name_R_time   = vars{all_time_indices(find(all_time_indices < idx_R_tot, 1, 'last'))};
    name_L_time   = vars{all_time_indices(find(all_time_indices < idx_L_tot, 1, 'last'))};
    name_ttl_time = vars{all_time_indices(find(all_time_indices < idx_ttl_sig, 1, 'last'))};
else
    name_R_time   = vars{all_time_indices(1)};
    name_L_time   = vars{all_time_indices(1)};
    name_ttl_time = vars{all_time_indices(1)};
end

% Drop incomplete lines at the trailing boundary safely using table references
validRows = ~isnan(allDataTab.(name_R_time)) & ~isnan(allDataTab.(name_L_time)) & ~isnan(allDataTab.(name_ttl_time));
allDataTab = allDataTab(validRows, :);
actualRows = height(allDataTab);

% Populate the isolated target metric struct matrices seamlessly using table columns
loadsol.ttl.time      = allDataTab.(name_ttl_time);
loadsol.ttl.signal    = allDataTab.(name_ttl_sig);  

loadsol.right.time    = allDataTab.(name_R_time);
loadsol.right.lateral = allDataTab.(name_R_lat);
loadsol.right.medial  = allDataTab.(name_R_med);
loadsol.right.heel    = allDataTab.(name_R_heel);
loadsol.right.total   = allDataTab.(name_R_tot);

loadsol.left.time     = allDataTab.(name_L_time);
loadsol.left.heel     = allDataTab.(name_L_heel);
loadsol.left.medial   = allDataTab.(name_L_med);
loadsol.left.lateral  = allDataTab.(name_L_lat);
loadsol.left.total    = allDataTab.(name_L_tot);

loadsol.fs = 100;  % Hz
fprintf('Loadsol fully parsed: %d samples safely extracted.\n', actualRows);

%% 2. PARSE MVNX DATA (VIA OFFICIAL XSENS LOAD_MVNX)
fprintf('Parsing MVNX file using load_mvnx...\n');
tree = load_mvnx(MVNX_FILE);
if isfield(tree, 'subject') && isfield(tree.subject, 'frameRate')
    xsens.fs = double(tree.subject.frameRate);
elseif isfield(tree, 'metaData') && isfield(tree.metaData, 'frameRate')
    xsens.fs = double(tree.metaData.frameRate);
else
    xsens.fs = 240;
end

segmentArray = tree.subject.segments.segment;
nSegs        = numel(segmentArray);
segNames     = cell(nSegs, 1);
for s = 1:nSegs
    segNames{s} = segmentArray(s).label;
end
xsens.segmentNames = segNames;

framesData = tree.subject.frames.frame;
nFrames    = numel(framesData);

xsens.frameIdx    = (0:nFrames-1).';
xsens.time        = (0:nFrames-1).' / xsens.fs; 
xsens.position    = zeros(nFrames, nSegs, 3);
xsens.orientation = zeros(nFrames, nSegs, 4);

for k = 1:nFrames
    if isfield(framesData(k), 'position') && ~isempty(framesData(k).position)
        rawPos = double(framesData(k).position);
        if numel(rawPos) == nSegs * 3
            xsens.position(k, :, :) = reshape(rawPos, 3, nSegs).';
        end
    end
    if isfield(framesData(k), 'orientation') && ~isempty(framesData(k).orientation)
        rawOri = double(framesData(k).orientation);
        if numel(rawOri) == nSegs * 4
            xsens.orientation(k, :, :) = reshape(rawOri, 4, nSegs).';
        end
    end
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
    thresh   = sigMin + 0.4 * (sigMax - sigMin);
    above    = ttlSignal > thresh;
    rising   = ([0; diff(above(:))] == 1);
    pulseIdx = find(rising, 1, 'first');
    if isempty(pulseIdx)
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
fprintf('\n========== SYNC DIAGNOSTIC REPORT ==========\n');
fprintf('[1] Unit_Label Header Alignment Check:\n');
fprintf('    Right Foot Total Force Variable mapped : %s\n', name_R_tot);
fprintf('    Left Foot Total Force Variable mapped  : %s\n', name_L_tot);
fprintf('    Sync Signal Variable mapped            : %s\n', name_ttl_sig);
fprintf('[2] Synced Window Overlap: [%.4f, %.4f] s\n', max(lsSync.time_100Hz(1), xsSync.time(1)), min(lsSync.time_100Hz(end), xsSync.time(end)));
fprintf('============================================\n\n');

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
T_END        = min(15*20, lsSync.time_100Hz(end));          
PLAYBACK_FPS = 30;        
XS_SKIP      = round(xsens.fs / PLAYBACK_FPS);   
TRAIL_S      = 5;           

frameIdx30   = find(xsens.time <= T_END);
frameIdx30   = frameIdx30(1 : XS_SKIP : end);   
nVideoFrames = numel(frameIdx30);

pos30        = xsens.position(frameIdx30, :, :);   
xLim         = [min(pos30(:,:,1),[],'all')-0.3,  max(pos30(:,:,1),[],'all')+0.3];
yLim         = [min(pos30(:,:,2),[],'all')-0.3,  max(pos30(:,:,2),[],'all')+0.3];
zLim         = [0,  max(pos30(:,:,3),[],'all')+0.3];

tXs          = xsens.time(frameIdx30);         
tLs          = lsSync.time_100Hz;

[tLs_u, iLs_u] = unique(tLs);
fR           = interp1(tLs_u, lsSync.right.total(iLs_u), tXs, 'linear', NaN);
fL           = interp1(tLs_u, lsSync.left.total(iLs_u),  tXs, 'linear', NaN);

allForce     = [lsSync.right.total; lsSync.left.total];
fMax         = max(allForce(~isnan(allForce))) * 1.05;
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

boneColor = [0.20 0.60 1.00]; rightColor = [1.00 0.35 0.35]; leftColor = [0.35 1.00 0.55];   
hBones = gobjects(nBones, 1);
for b = 1:nBones
    bname = xsens.segmentNames{bones(b,2)};
    if contains(bname,'Right','IgnoreCase',true), col = rightColor;
    elseif contains(bname,'Left','IgnoreCase',true), col = leftColor;
    else, col = boneColor; end
    hBones(b) = plot3(ax3d, [0 0],[0 0],[0 0], '-o','Color',col,'LineWidth',2.0,'MarkerSize',4,'MarkerFaceColor',col);
end
hHead  = plot3(ax3d, 0,0,0, 'o', 'MarkerSize',12,'MarkerFaceColor',[1 0.85 0.6], 'MarkerEdgeColor','w','LineWidth',1.2);
hTime  = text(ax3d, xLim(1)+0.05, yLim(2)-0.05, zLim(2)-0.05, 't = 0.00 s','Color','w','FontSize',11,'FontWeight','bold');

ax2d   = subplot(1,2,2,'Parent',fig);
set(ax2d,'Color','k','XColor','w','YColor','w', 'GridColor',[0.3 0.3 0.3],'GridAlpha',0.4);
hold(ax2d,'on'); grid(ax2d,'on'); ylim(ax2d,[0 fMax]);

hFR    = plot(ax2d, NaN, NaN, '-', 'Color',rightColor, 'LineWidth',1.8,'DisplayName','Right foot');
hFL    = plot(ax2d, NaN, NaN, '-', 'Color',leftColor,  'LineWidth',1.8,'DisplayName','Left foot');
hVline = xline(ax2d, 0, '--','Color',[1 1 0.4],'LineWidth',1.2);

hFR_fill = fill(ax2d, NaN, NaN, rightColor, 'FaceAlpha',0.15, 'EdgeColor','none','HandleVisibility','off');
hFL_fill = fill(ax2d, NaN, NaN, leftColor,  'FaceAlpha',0.15, 'EdgeColor','none','HandleVisibility','off');
legend(ax2d,'show','TextColor','w','Color','k');

headIdx = find(contains(xsens.segmentNames,'Head','IgnoreCase',true),1);
if isempty(headIdx), headIdx = 7; end

fprintf('Exporting sync video frames... 0%%\n'); 
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
    
    if mod(vi, 10) == 0 || vi == nVideoFrames
        pct = (vi / nVideoFrames) * 100;
        fprintf('\b\b\b\b%3.0f%%', pct); 
    end
end
fprintf('\n'); 
close(vw); close(fig);
fprintf('Video rendering completed → %s\n', OUTPUT_VIDEO);

%% 7. VISUALIZE FIRST 30 SECONDS (PLOTS)
ls_m = lsSync.commonTime <= T_END & ~isnan(lsSync.right.total_240Hz);
xs_m = xsSync.time       <= T_END;
ttl_m = lsSync.ttl.time  <= T_END;

t_ls  = lsSync.commonTime(ls_m);
t_xs  = xsSync.time(xs_m);
t_ttl = lsSync.ttl.time(ttl_m);

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
title('Unit_Label Header Paired Table Force Logs (240Hz)');

ax2 = subplot(4,1,2);
plot(t_ls, lsSync.right.heel_240Hz(ls_m)); hold on;
plot(t_ls, lsSync.right.medial_240Hz(ls_m));
plot(t_ls, lsSync.right.lateral_240Hz(ls_m)); grid on; xlim([0 T_END]);
title('Right Foot Regional Pressure Decompositions');

ax3 = subplot(4,1,3);
plot(t_xs, euler_deg(:,1)); hold on;
plot(t_xs, euler_deg(:,2));
plot(t_xs, euler_deg(:,3)); grid on; xlim([0 T_END]);
title('Kinematic Orientation Trace');

ax4 = subplot(4,1,4);
plot(t_ttl, lsSync.ttl.signal(ttl_m), 'Color','#333333'); grid on; xlim([0 T_END]);
title('Raw Synchronization Anchor Channel Graph (KYN058)');
linkaxes([ax1 ax2 ax3 ax4], 'x');

%% 8. SAVE WORKSPACE MAT FILE
save(OUTPUT_MAT, 'lsSync', 'xsSync', 'loadsol', 'xsens');
fprintf('Success. All synchronized metrics saved → %s\n', OUTPUT_MAT);