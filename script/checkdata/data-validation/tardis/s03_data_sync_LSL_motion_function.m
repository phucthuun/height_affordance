function s03_data_sync_LSL_motion_function(subLabel, sesLabel, runID_in, taskName, preOffsetRed_in, baseLoc, derivativesLoc)
% S03_DATA_SYNC_FUNCTION Headless HPC Multi-Modal Synchronization & Slicing Pipeline
%
% Usage:
%   % Process ALL runs automatically:
%   s03_data_sync_LSL_motion_function('MH9HXJ', 'S001', 'all', 'heightaffordance', '3.0')
%
%   % Process a single specific run:
%   s03_data_sync_LSL_motion_function('MH9HXJ', 'S001', '001', 'heightaffordance', '3.0')

%% 0. Default Arguments & Path Initialization
if nargin < 1 || isempty(subLabel),        subLabel = 'MH9HXJ'; end
if nargin < 2 || isempty(sesLabel),        sesLabel = 'S001'; end
if nargin < 3 || isempty(runID_in),        runID_in = 'all'; end
if nargin < 4 || isempty(taskName),        taskName = 'heightaffordance'; end
if nargin < 5 || isempty(preOffsetRed_in), preOffsetRed_in = '3.0'; end
if nargin < 6 || isempty(baseLoc),         baseLoc = '/mnt/beegfs/home/nguyen/1223-xplo-judo/10_Data/sourcedata'; end
if nargin < 7 || isempty(derivativesLoc),  derivativesLoc = '/mnt/beegfs/home/nguyen/1223-xplo-judo/10_Data/derivatives'; end

% Ensure XDF import plugin is present in search path
xdfPluginPath = '/mnt/beegfs/home/nguyen/matlab/toolbox/EEGLAB/eeglab2026.0.0/plugins/xdfimport1.2';
if exist(xdfPluginPath, 'dir')
    addpath(genpath(xdfPluginPath));
end

if ischar(preOffsetRed_in) || isstring(preOffsetRed_in)
    PRE_OFFSET_REDUCTION = str2double(preOffsetRed_in);
else
    PRE_OFFSET_REDUCTION = preOffsetRed_in;
end

subLabel = regexprep(char(subLabel), '^sub-', '');
sesLabel = regexprep(char(sesLabel), '^ses-', '');
subID = ['sub-' subLabel]; 
sesID = ['ses-' sesLabel];

PIPELINE_NAME = 'syncdata';
PIPELINE_ROOT = fullfile(derivativesLoc, PIPELINE_NAME);

LSL_GLOBAL_DIR    = fullfile(baseLoc, subID, sesID, 'lslglobal');
OUTPUT_MOTION_DIR = fullfile(PIPELINE_ROOT, subID, sesID, 'motion');

if ~exist(OUTPUT_MOTION_DIR, 'dir')
    mkdir(OUTPUT_MOTION_DIR);
end

%% --- Parse and Resolve Run List ('all' vs specific run) ---
if (ischar(runID_in) || isstring(runID_in)) && strcmpi(char(runID_in), 'all')
    search_pattern = sprintf('%s_%s_task-%s_run-*_lslglobal.xdf', subID, sesID, taskName);
    matchingFiles = dir(fullfile(LSL_GLOBAL_DIR, search_pattern));
    
    if isempty(matchingFiles)
        error('No XDF files matching pattern "%s" found in: %s', search_pattern, LSL_GLOBAL_DIR);
    end
    
    runList = {};
    for f = 1:length(matchingFiles)
        tokens = regexp(matchingFiles(f).name, 'run-(\d+)', 'tokens');
        if ~isempty(tokens)
            runList{end+1} = tokens{1}{1}; %#ok<AGROW>
        end
    end
    runList = unique(runList);
    fprintf('Found %d runs to process: %s\n', length(runList), strjoin(runList, ', '));
elseif isnumeric(runID_in)
    runList = {sprintf('%03d', runID_in)};
else
    runList = {sprintf('%03d', str2double(runID_in))};
end

fprintf('============ LSL MOTION STREAM SYNCHRONIZER (HEADLESS HPC) ============ \n');
fprintf('Subject: %s | Session: %s | Task: %s | Total Runs: %d\n', subID, sesID, taskName, length(runList));

%% Outer Loop: Iterate Over Resolved Runs
for r = 1:length(runList)
    runID = runList{r};
    
    search_prefix = sprintf('%s_%s_task-%s_run-%s', subID, sesID, taskName, runID);
    fullXdfPath   = fullfile(LSL_GLOBAL_DIR, [search_prefix '_lslglobal.xdf']);
    
    fprintf('\n----------------------------------------------------------------------\n');
    fprintf('Processing Run [%02d/%02d]: %s\n', r, length(runList), runID);
    fprintf('Input XDF: %s\n', fullXdfPath);

    try
        if ~exist(fullXdfPath, 'file')
            warning('Master XDF file not found for run %s at path: %s. Skipping.', runID, fullXdfPath);
            continue;
        end

        %% 1. Ingest Master XDF & Extract Datagram Streams
        fprintf('Loading master XDF file logs...\n');
        streams = load_xdf(fullXdfPath);

        mIdx = get_stream(streams, 'Trigger'); 
        if isempty(mIdx), mIdx = get_stream(streams, 'Markers'); end
        if isempty(mIdx)
            warning('Required LSL Marker/Trigger stream missing in run %s. Skipping.', runID);
            continue;
        end

        mText = streams{mIdx}.time_series(:); 
        mTime = streams{mIdx}.time_stamps(:);

        idx_Euler   = get_stream(streams, 'EulerDatagram');
        idx_Quat    = get_stream(streams, 'QuaternionDatagram');
        idx_AngKin  = get_stream(streams, 'AngularKinematics');
        idx_LinKin  = get_stream(streams, 'LinearSegmentKinematicsDatagram');
        idx_CoM     = get_stream(streams, 'CenterOfMass');

        if isempty(idx_LinKin)
            warning('Required LinearKinematics stream missing in run %s. Skipping.', runID);
            continue;
        end

        %% 2. Reconstruct Timelines & Identify Trials
        trials = struct('trial_id', {}, 'start_ts', {}, 'end_ts', {});
        trialCount = 0; activeTrialStartTS = [];
        for i = 1:numel(mText)
            if strcmp(mText{i}, sprintf('Neutral%d', trialCount+1))
                activeTrialStartTS = mTime(i);
            elseif contains(mText{i}, 'TrialOffset') && ~isempty(activeTrialStartTS)
                calculatedEndTS = mTime(i) - PRE_OFFSET_REDUCTION;
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
        segNames = {'Pelvis','L5','L3','T12','T8','Neck','Head',...
                    'RightShoulder','RightUpperArm','RightForeArm','RightHand',...
                    'LeftShoulder','LeftUpperArm','LeftForeArm','LeftHand',...
                    'RightUpperLeg','RightLowerLeg','RightFoot','RightToe',...
                    'LeftUpperLeg','LeftLowerLeg','LeftFoot','LeftToe'};

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

        if ~isempty(idx_CoM)
            tt_CoM = build_tt(streams{idx_CoM}, {'CoM_pos_x', 'CoM_pos_y', 'CoM_pos_z'});
            tt_unified = synchronize(tt_Euler, tt_Quat, tt_Ang, tt_Lin, tt_CoM, tt_Euler.Time, 'linear');
        else
            tt_unified = synchronize(tt_Euler, tt_Quat, tt_Ang, tt_Lin, tt_Euler.Time, 'linear');
        end

        allVars = tt_unified.Properties.VariableNames;
        uniqueBases = unique(regexprep(allVars, '_(tt_Euler|tt_Quat|tt_Ang|tt_Lin|tt_CoM)$', ''));
        tt_final = timetable(tt_unified.Time);
        for i = 1:length(uniqueBases)
            matchCols = allVars(startsWith(allVars, uniqueBases{i}));
            mergedData = tt_unified{:, matchCols};
            tt_final.(uniqueBases{i}) = mean(mergedData, 2, 'omitnan'); 
        end

        %% 4. Process Trials & Render Diagnostics
        for t = 1:trialCount
            t_start = trials(t).start_ts;
            t_end   = trials(t).end_ts;
            
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
            
            save(outMatPath, 'trial_data');
            fprintf(' -> Run %s | Trial %03d/%03d | Saved: %s\n', runID, t, trialCount, outMatPath);
            
            % Render Diagnostics Video (Set high quality & native resolution)
            plotOutPath = fullfile(OUTPUT_MOTION_DIR, [baseOutName '_desc-motion.avi']);
            fig = figure('Color','k', 'Position',[50 50 1500 1350], 'Visible','off');
            ax3d = axes('Parent',fig); 
            set(ax3d, 'Color','k', 'XColor','w', 'YColor','w', 'ZColor','w'); 
            hold(ax3d, 'on'); grid(ax3d, 'on'); view(ax3d, 35, 20); 
            ax3d.DataAspectRatio = [1 1 1];
            
            cRed    = [1.0, 0.25, 0.25];
            cBlue   = [0.2, 0.60, 1.00];
            cYellow = [1.0, 0.85, 0.00];
            
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
                
                if contains(p2_name, 'Left') || contains(p1_name, 'Left')
                    boneColors(b,:) = cRed;
                elseif contains(p2_name, 'Right') || contains(p1_name, 'Right')
                    boneColors(b,:) = cBlue;
                else
                    boneColors(b,:) = cYellow;
                end
            end
            
            hBones = gobjects(nBones, 1);
            for b = 1:nBones
                hBones(b) = plot3(ax3d, [0 0],[0 0],[0 0], '-o', ...
                    'Color', boneColors(b,:), 'MarkerFaceColor', boneColors(b,:), ...
                    'MarkerSize', 5, 'LineWidth', 2.5, 'HandleVisibility', 'off');
            end
            
            plot3(ax3d, NaN, NaN, NaN, '-o', 'Color', cRed,    'MarkerFaceColor', cRed,    'LineWidth', 2, 'DisplayName', 'Left Side');
            plot3(ax3d, NaN, NaN, NaN, '-o', 'Color', cBlue,   'MarkerFaceColor', cBlue,   'LineWidth', 2, 'DisplayName', 'Right Side');
            plot3(ax3d, NaN, NaN, NaN, '-o', 'Color', cYellow, 'MarkerFaceColor', cYellow, 'LineWidth', 2, 'DisplayName', 'Mid-Body');
            
            hasCoMData = ismember('CoM_pos_x', trial_data.Properties.VariableNames);
            if hasCoMData
                hCoM = plot3(ax3d, NaN, NaN, NaN, 'o', 'MarkerSize', 10, ...
                             'MarkerFaceColor', [0.1 0.9 0.1], 'MarkerEdgeColor', 'w', ...
                             'LineWidth', 1.5, 'DisplayName', 'Center of Mass');
                         
                hCoM_proj = plot3(ax3d, NaN, NaN, NaN, 'x', 'MarkerSize', 8, ...
                                  'Color', [0.3 0.9 0.3], 'LineWidth', 1.5, 'DisplayName', 'CoM Projection (Ground)');
                              
                hCoM_trail = plot3(ax3d, NaN, NaN, NaN, ':', 'Color', [0.3 0.9 0.3 0.6], ...
                                   'LineWidth', 1.5, 'DisplayName', 'CoM Trail');
            end
            
            legend(ax3d, 'TextColor', 'w', 'Color', 'none', 'EdgeColor', [0.3 0.3 0.3], 'Location', 'northeast');
            
            vw_plot = VideoWriter(plotOutPath, 'Motion JPEG AVI'); 
            vw_plot.FrameRate = 30; 
            vw_plot.Quality = 100; % Set JPEG Quality to 100% to maximize sharpness
            open(vw_plot);
            
            time_vec = seconds(trial_data.Time);
            frameStep = max(1, round(length(time_vec) / (vw_plot.FrameRate * (time_vec(end)-time_vec(1)))));
            
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
                
                if s == 1
                    xlim(ax3d, [-2, 3]);
                    ylim(ax3d, [-2, 2]);
                    zlim(ax3d, [-0, 2]);
                end
                
                for b = 1:nBones
                    p1 = bones(b,1); p2 = bones(b,2);
                    set(hBones(b), 'XData', [currentFramePos(p1,1) currentFramePos(p2,1)], ...
                                   'YData', [currentFramePos(p1,2) currentFramePos(p2,2)], ...
                                   'ZData', [currentFramePos(p1,3) currentFramePos(p2,3)]);
                end
                
                if hasCoMData
                    cx = trial_data.CoM_pos_x(s);
                    cy = trial_data.CoM_pos_y(s);
                    cz = trial_data.CoM_pos_z(s);
                    
                    if ~isnan(cx) && ~isnan(cy) && ~isnan(cz)
                        set(hCoM, 'XData', cx, 'YData', cy, 'ZData', cz);
                        set(hCoM_proj, 'XData', cx, 'YData', cy, 'ZData', 0);
                        
                        com_trail_x(end+1) = cx; %#ok<AGROW>
                        com_trail_y(end+1) = cy; %#ok<AGROW>
                        com_trail_z(end+1) = cz; %#ok<AGROW>
                        set(hCoM_trail, 'XData', com_trail_x, 'YData', com_trail_y, 'ZData', com_trail_z);
                    end
                end
                
                drawnow limitrate;
                frame = getframe(fig);
                writeVideo(vw_plot, frame);
            end
            
            close(vw_plot);
            clf(fig);
            close(fig);
            clear vw_plot fig ax3d hBones hCoM hCoM_proj hCoM_trail;
        end

        % Clean up loop variables at end of successful run
        clear streams tt_Euler tt_Quat tt_Ang tt_Lin tt_CoM tt_unified tt_final trial_data;
        close all force;
        java.lang.System.gc();

    catch ME
        % Print error details without stopping execution
        fprintf(2, '\n[ERROR] Run %s failed: %s\n', runID, ME.message);
        fprintf(2, '%s\n', getReport(ME, 'extended', 'hyperlinks', 'off'));
        
        % Ensure open figures or video streams are closed before next iteration
        close all force;
        java.lang.System.gc();
    end

end

fprintf('\nPipeline processing complete across all specified runs.\n');
end

function idx = get_stream(streams, name)
    idx = find(cellfun(@(x) contains(x.info.name, name, 'IgnoreCase', true) && ~isempty(x.time_series), streams), 1);
end

function tt = build_tt(stream, varNames)
    tt = array2timetable(stream.time_series', 'RowTimes', seconds(stream.time_stamps'));
    tt.Properties.VariableNames = varNames;
end