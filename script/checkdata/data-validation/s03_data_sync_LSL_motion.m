%% LSL-Video and Motion Synchronization

clear; clc; close all;

fprintf('============ LSL KINEMATICS & VIDEO SYNCHRONIZER ============ \n');
BASE_LOC        = 'C:\Data\Research\10_Data\sourcedata';
DERIVATIVES_LOC = 'C:\Data\Research\10_Data\derivatives';
PIPELINE_NAME   = 'syncdata';
PIPELINE_ROOT   = fullfile(DERIVATIVES_LOC, PIPELINE_NAME);

% --- Request Processing Target Metadata ---
prompt = {'Enter Subject ID:', 'Enter Session ID:', 'Enter Run ID:', 'Enter Task Name:', 'Trim buffer before TrialOffset (s):'};
dlgtitle = 'Data Pipeline Target Selection';
definput = {'MH9HXJ', 'S001', '001', 'heightaffordance', '3.0'};
userInput = inputdlg(prompt, dlgtitle, [1 50], definput);
if isempty(userInput); error('Execution cancelled by user.'); end

subID = ['sub-' regexprep(userInput{1}, '^sub-', '')];
sesID = ['ses-' regexprep(userInput{2}, '^ses-', '')];
runID = sprintf('%03d', str2double(userInput{3}));
taskName = userInput{4};
PRE_OFFSET_REDUCTION = str2double(userInput{5}); % Standard 3s before TrialOffset

LSL_GLOBAL_DIR = fullfile(BASE_LOC, subID, sesID, 'lslglobal');
OUTPUT_MOTION_DIR = fullfile(PIPELINE_ROOT, subID, sesID, 'motion');

if ~exist(OUTPUT_MOTION_DIR, 'dir'), mkdir(OUTPUT_MOTION_DIR); end

search_prefix = sprintf('%s_%s_task-%s_run-%s', subID, sesID, taskName, runID);
fullXdfPath   = fullfile(LSL_GLOBAL_DIR, [search_prefix '_lslglobal.xdf']);


%% 1. Ingest Master XDF & Extract Datagram Streams
fprintf('Loading master XDF file logs...\n');
streams = load_xdf(fullXdfPath);

% Helper to find valid stream (handles ending 1 or 2, skips empty)
get_stream = @(name) find(cellfun(@(x) contains(x.info.name, name, 'IgnoreCase', true) && ~isempty(x.time_series), streams), 1);

mIdx = get_stream('Trigger'); 
if isempty(mIdx), mIdx = get_stream('Markers'); end
mText = streams{mIdx}.time_series(:); 
mTime = streams{mIdx}.time_stamps(:);

idx_Euler   = get_stream('EulerDatagram');
idx_Quat    = get_stream('QuaternionDatagram');
idx_AngKin  = get_stream('AngularKinematics');
idx_LinKin  = get_stream('LinearSegmentKinematicsDatagram');
idx_CoM     = get_stream('CenterOfMass');

if isempty(mIdx) || isempty(idx_LinKin); error('Required LSL Marker or LinearKinematics stream missing.'); end

sideCamMarkerIdx   = get_stream('FrameMarker_1');
upperCamMarkerIdx  = get_stream('FrameMarker_0');
groundCamMarkerIdx = get_stream('FrameMarker_2');

%% 2. Reconstruct Timelines & Identify Trials
trials = struct('trial_id', {}, 'start_ts', {}, 'end_ts', {});
trialCount = 0; activeTrialStartTS = [];
for i = 1:numel(mText)
    if strcmp(mText{i}, sprintf('Neutral%d', trialCount+1)) % Matches "Neutral%d" marker logic
        activeTrialStartTS = mTime(i);
    elseif contains(mText{i}, 'TrialOffset') && ~isempty(activeTrialStartTS) % Matches "TrialOffset" event logic
        calculatedEndTS = mTime(i) - PRE_OFFSET_REDUCTION; % Applies reduction buffer
        if calculatedEndTS > activeTrialStartTS
            trialCount = trialCount + 1;
            trials(trialCount).trial_id = trialCount;
            trials(trialCount).start_ts = activeTrialStartTS;
            trials(trialCount).end_ts = calculatedEndTS;
        end
        activeTrialStartTS = [];
    end
end
fprintf('Extracted %d trial segments.\n', trialCount);

%% 3. Construct Unified Dataframes (Timetables)
% Standard 23 Segment Names
segNames = {'Pelvis','L5','L3','T12','T8','Neck','Head',...
            'RightShoulder','RightUpperArm','RightForeArm','RightHand',...
            'LeftShoulder','LeftUpperArm','LeftForeArm','LeftHand',...
            'RightUpperLeg','RightLowerLeg','RightFoot','RightToe',...
            'LeftUpperLeg','LeftLowerLeg','LeftFoot','LeftToe'};

% Helper to build timetable
function tt = build_tt(stream, varNames)
    tt = array2timetable(stream.time_series', 'RowTimes', seconds(stream.time_stamps'));
    tt.Properties.VariableNames = varNames;
end

% Build Column Names
eulerCols = {}; quatCols = {}; angCols = {}; linCols = {};
for s = 1:23
    base = segNames{s};
    eulerCols = [eulerCols, {[base '_pos_x'], [base '_pos_y'], [base '_pos_z'], [base '_euler_x'], [base '_euler_y'], [base '_euler_z']}];
    quatCols  = [quatCols,  {[base '_pos_x'], [base '_pos_y'], [base '_pos_z'], [base '_quat_q0'], [base '_quat_q1'], [base '_quat_q2'], [base '_quat_q3']}];
    angCols   = [angCols,   {[base '_quat_q0'], [base '_quat_q1'], [base '_quat_q2'], [base '_quat_q3'], [base '_angvel_x'], [base '_angvel_y'], [base '_angvel_z'], [base '_angacc_x'], [base '_angacc_y'], [base '_angacc_z']}];
    linCols   = [linCols,   {[base '_pos_x'], [base '_pos_y'], [base '_pos_z'], [base '_vel_x'], [base '_vel_y'], [base '_vel_z'], [base '_acc_x'], [base '_acc_y'], [base '_acc_z']}];
end

tt_Euler = build_tt(streams{idx_Euler}, eulerCols);
tt_Quat  = build_tt(streams{idx_Quat}, quatCols);
tt_Ang   = build_tt(streams{idx_AngKin}, angCols);
tt_Lin   = build_tt(streams{idx_LinKin}, linCols);

% Include CenterOfMass stream if present
if ~isempty(idx_CoM)
    tt_CoM = build_tt(streams{idx_CoM}, {'CoM_pos_x', 'CoM_pos_y', 'CoM_pos_z'});
    tt_unified = synchronize(tt_Euler, tt_Quat, tt_Ang, tt_Lin, tt_CoM, 'union');
else
    tt_unified = synchronize(tt_Euler, tt_Quat, tt_Ang, tt_Lin, 'union');
end

% Collapse redundant columns by finding identical base names created during synchronize
allVars = tt_unified.Properties.VariableNames;
uniqueBases = unique(regexprep(allVars, '_(tt_Euler|tt_Quat|tt_Ang|tt_Lin|tt_CoM)$', ''));
tt_final = timetable(tt_unified.Time);
for i = 1:length(uniqueBases)
    matchCols = allVars(startsWith(allVars, uniqueBases{i}));
    % Take the first non-NaN value across redundant columns for each row
    mergedData = tt_unified{:, matchCols};
    tt_final.(uniqueBases{i}) = mean(mergedData, 2, 'omitnan'); 
end

%% 4. Process Trials

for t = 1:trialCount
    t_start = trials(t).start_ts;
    t_end   = trials(t).end_ts;
    
    % Slice timetable for trial
    t_range = timerange(seconds(t_start), seconds(t_end));
    trial_data = tt_final(t_range, :);

    % --- Zero-Center Position Origin (Robust Windowed Median) ---
    % Calculate median Pelvis X & Y over the first 0.5s (up to 30 samples)
    baseline_samples = min(120, height(trial_data)); % below 0.5 seconds of body sway
    
    ref_x = median(trial_data.Pelvis_pos_x(1:baseline_samples), 'omitnan');
    ref_y = median(trial_data.Pelvis_pos_y(1:baseline_samples), 'omitnan');
    
    % Fallback protection if the entire baseline window contains NaNs
    if isnan(ref_x)
        valid_x = trial_data.Pelvis_pos_x(~isnan(trial_data.Pelvis_pos_x));
        if ~isempty(valid_x), ref_x = valid_x(1); else, ref_x = 0; end
    end
    if isnan(ref_y)
        valid_y = trial_data.Pelvis_pos_y(~isnan(trial_data.Pelvis_pos_y));
        if ~isempty(valid_y), ref_y = valid_y(1); else, ref_y = 0; end
    end

    for i = 1:length(segNames)
        posX_var = [segNames{i} '_pos_x'];
        posY_var = [segNames{i} '_pos_y'];
        if ismember(posX_var, trial_data.Properties.VariableNames)
            trial_data.(posX_var) = trial_data.(posX_var) - ref_x;
        end
        if ismember(posY_var, trial_data.Properties.VariableNames)
            trial_data.(posY_var) = trial_data.(posY_var) - ref_y;
        end
    end
    
    if ismember('CoM_pos_x', trial_data.Properties.VariableNames)
        trial_data.CoM_pos_x = trial_data.CoM_pos_x - ref_x;
    end
    if ismember('CoM_pos_y', trial_data.Properties.VariableNames)
        trial_data.CoM_pos_y = trial_data.CoM_pos_y - ref_y;
    end
    
    baseOutName = sprintf('%s_%s_task-%s_run-%s_trial-%03d', subID, sesID, taskName, runID, trials(t).trial_id);
    outMatPath  = fullfile(OUTPUT_MOTION_DIR, [baseOutName '_desc-synchronized_motion.mat']);
    
    % Save Trial Dataframe
    save(outMatPath, 'trial_data');
    fprintf(' -> Processing Trial %03d/%03d\n', t, trialCount);
    
    
    % --- Visualization (3D Kinematics with Body-Part Color Coding) ---
    plotOutPath = fullfile(OUTPUT_MOTION_DIR, [baseOutName '_desc-motion.mp4']);
    fig = figure('Color','k', 'Position',[50 50 1000 900], 'Visible','off');
    ax3d = axes('Parent',fig); set(ax3d,'Color','k','XColor','w','YColor','w','ZColor','w'); hold(ax3d,'on'); grid(ax3d,'on'); view(ax3d, 35, 20); ax3d.DataAspectRatio = [1 1 1];
    
    % Color Definitions
    cRed    = [1.0, 0.25, 0.25]; % Left side
    cBlue   = [0.2, 0.60, 1.00]; % Right side
    cYellow = [1.0, 0.85, 0.00]; % Mid-body
    
    % Draw Setup - Skeleton Bones
    boneDefs = {'Pelvis','L5'; 'L5','L3'; 'L3','T12'; 'T12','T8'; 'T8','Neck'; 'Neck','Head'; ...
                'T8','RightShoulder'; 'RightShoulder','RightUpperArm'; 'RightUpperArm','RightForeArm'; 'RightForeArm','RightHand'; ...
                'T8','LeftShoulder'; 'LeftShoulder','LeftUpperArm'; 'LeftUpperArm','LeftForeArm'; 'LeftForeArm','LeftHand'; ...
                'Pelvis','RightUpperLeg'; 'RightUpperLeg','RightLowerLeg'; 'RightLowerLeg','RightFoot'; 'RightFoot','RightToe'; ...
                'Pelvis','LeftUpperLeg'; 'LeftUpperLeg','LeftLowerLeg'; 'LeftLowerLeg','LeftFoot'; 'LeftFoot','LeftToe';};
            
    idx_match = @(name) find(strcmp(segNames, name), 1);
    nBones = size(boneDefs, 1);
    bones = zeros(nBones, 2); 
    boneColors = zeros(nBones, 3);
    
    for b = 1:nBones
        p1_name = boneDefs{b,1};
        p2_name = boneDefs{b,2};
        bones(b,1) = idx_match(p1_name); 
        bones(b,2) = idx_match(p2_name);
        
        % Assign colors based on segment side
        if contains(p2_name, 'Left') || contains(p1_name, 'Left')
            boneColors(b,:) = cRed;
        elseif contains(p2_name, 'Right') || contains(p1_name, 'Right')
            boneColors(b,:) = cBlue;
        else
            boneColors(b,:) = cYellow;
        end
    end
    
    % Initialize Bone & Joint Graphics Handles with Filled Dots ('MarkerFaceColor')
    hBones = gobjects(nBones, 1);
    for b = 1:nBones
        hBones(b) = plot3(ax3d, [0 0],[0 0],[0 0], '-o', ...
            'Color', boneColors(b,:), ...
            'MarkerFaceColor', boneColors(b,:), ...
            'MarkerSize', 5, ...
            'LineWidth', 2.5, ...
            'HandleVisibility', 'off');
    end
    
    % Legend entries for body side color legend
    plot3(ax3d, NaN, NaN, NaN, '-o', 'Color', cRed,    'MarkerFaceColor', cRed,    'LineWidth', 2, 'DisplayName', 'Left Side');
    plot3(ax3d, NaN, NaN, NaN, '-o', 'Color', cBlue,   'MarkerFaceColor', cBlue,   'LineWidth', 2, 'DisplayName', 'Right Side');
    plot3(ax3d, NaN, NaN, NaN, '-o', 'Color', cYellow, 'MarkerFaceColor', cYellow, 'LineWidth', 2, 'DisplayName', 'Mid-Body');
    
    % --- Center of Mass (CoM) Visualization Setup ---
    hasCoMData = ismember('CoM_pos_x', trial_data.Properties.VariableNames);
    if hasCoMData
        % 3D Center of Mass sphere
        hCoM = plot3(ax3d, NaN, NaN, NaN, 'o', 'MarkerSize', 10, ...
                     'MarkerFaceColor', [0.1 0.9 0.1], 'MarkerEdgeColor', 'w', ...
                     'LineWidth', 1.5, 'DisplayName', 'Center of Mass');
                 
        % Ground Projection (Shadow on Z=0 floor)
        hCoM_proj = plot3(ax3d, NaN, NaN, NaN, 'x', 'MarkerSize', 8, ...
                          'Color', [0.3 0.9 0.3], 'LineWidth', 1.5, 'DisplayName', 'CoM Projection (Ground)');
                      
        % Trajectory trail for CoM path
        hCoM_trail = plot3(ax3d, NaN, NaN, NaN, ':', 'Color', [0.3 0.9 0.3 0.6], ...
                           'LineWidth', 1.5, 'DisplayName', 'CoM Trail');
    end
    
    legend(ax3d, 'TextColor', 'w', 'Color', 'none', 'EdgeColor', [0.3 0.3 0.3], 'Location', 'northeast');
    
    vw_plot = VideoWriter(plotOutPath, 'MPEG-4'); vw_plot.FrameRate = 30; open(vw_plot);
    
    % Render LSL Linear Kinematics subset for visualization
    time_vec = seconds(trial_data.Time);
    frameStep = max(1, round(length(time_vec) / (vw_plot.FrameRate * (time_vec(end)-time_vec(1)))));
    
    % Pre-allocate arrays for CoM trail history
    if hasCoMData
        com_trail_x = []; com_trail_y = []; com_trail_z = [];
    end
    
    for s = 1:frameStep:height(trial_data)
        currentFramePos = zeros(23, 3);
        for i = 1:23
            currentFramePos(i,1) = trial_data.([segNames{i} '_pos_x'])(s);
            currentFramePos(i,2) = trial_data.([segNames{i} '_pos_y'])(s);
            currentFramePos(i,3) = trial_data.([segNames{i} '_pos_z'])(s);
        end
        
        if s == 1 % Auto-scale bounds on first frame
            xlim(ax3d, [-2, 4]);
            ylim(ax3d, [-3, 3]);
            zlim(ax3d, [-0, 2]);
        end
        
        % Update Skeleton
        for b = 1:nBones
            p1 = bones(b,1); p2 = bones(b,2);
            set(hBones(b), 'XData', [currentFramePos(p1,1) currentFramePos(p2,1)], ...
                           'YData', [currentFramePos(p1,2) currentFramePos(p2,2)], ...
                           'ZData', [currentFramePos(p1,3) currentFramePos(p2,3)]);
        end
        
        % Update Center of Mass
        if hasCoMData
            cx = trial_data.CoM_pos_x(s);
            cy = trial_data.CoM_pos_y(s);
            cz = trial_data.CoM_pos_z(s);
            
            if ~isnan(cx) && ~isnan(cy) && ~isnan(cz)
                set(hCoM, 'XData', cx, 'YData', cy, 'ZData', cz);
                set(hCoM_proj, 'XData', cx, 'YData', cy, 'ZData', 0); % projected on floor
                
                % Append to trail
                com_trail_x(end+1) = cx; %#ok<AGROW>
                com_trail_y(end+1) = cy; %#ok<AGROW>
                com_trail_z(end+1) = cz; %#ok<AGROW>
                set(hCoM_trail, 'XData', com_trail_x, 'YData', com_trail_y, 'ZData', com_trail_z);
            end
        end
        
        drawnow limitrate;
        frame = getframe(fig);
        
        % Resize the image array to [Height, Width] 
        frame.cdata = imresize(frame.cdata, [1350, 1500]); 
        
        writeVideo(vw_plot, frame);
    end
    close(vw_plot); close(fig);
end

fprintf('\nPipeline complete. Dataframes and multi-view diagnostics exported.\n');