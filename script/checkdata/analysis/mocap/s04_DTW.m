%% Body Movement Similarity Across Trials via Dynamic Time Warping (DTW)
% Description: Picks a participant, finds every trial's synchronized motion .mat file
%              (as exported by s03_data_sync_interactive.m) across ALL sessions and runs
%              of a given task, and runs TWO separate DTW similarity analyses:
%
%              1) PELVIS      -- Pelvis 3D position (x,y,z), centered to each trial's own
%                                 start sample. Captures whole-body TRANSLATION through the
%                                 room (footwork/approach), independent of starting location.
%              2) WHOLE BODY  -- every other tracked segment's 3D position expressed RELATIVE
%                                 TO THE PELVIS at each time sample (pelvis itself dropped,
%                                 since after this transform it is constantly zero). Captures
%                                 body CONFIGURATION/posture, decoupled from locomotion.
%
%              Each trial is matched against its experimental-condition table
%              (sourcedata/.../beh/..._beh.mat) to recover the fighterID and posture
%              ("upright"/"lowered"). A fighter's HEIGHT is estimated as the max "stance"
%              value recorded for that fighterID (their most upright trials read closest to
%              true height; "lowered" trials read lower).
%
%              Trials in each distance matrix/heatmap are ordered:
%                 height (tall -> short) > posture (upright -> lowered)
%                 > fighter (grouped, same fighter order repeated in both posture blocks)
%                 > original trial order within a fighter/posture/height group
%              e.g. tallA-up, tallB-up, tallC-up, tallA-low, tallB-low, tallC-low,
%                   shortD-up, shortE-up, shortF-up, shortD-low, shortE-low, shortF-low
%
%              IMPORTANT: because each analysis applies its OWN missing-data quality check
%              (a trial can have clean pelvis tracking but dropped wrist tracking, or vice
%              versa), the Pelvis and Whole Body analyses may not include exactly the same
%              set of trials. Check the console output / included-trial counts for each.
%
% Requires: Signal Processing Toolbox (dtw), Statistics and Machine Learning Toolbox
%           (pdist/linkage/dendrogram helpers -- only used for the optional clustering plot)
%
% Input:  .mat files produced by s03_data_sync_interactive.m
%         (PIPELINE_ROOT/sub-*/ses-*/motion/*_desc-synchronized_motion.mat)
%         + condition tables in sourcedata/sub-*/ses-*/beh/*_beh.mat
% Output: per analysis (pelvis / wholebody), saved under its own subfolder:
%         pairwise DTW distance matrix + trial metadata (.mat + .csv),
%         a distance-matrix heatmap (ordered by height/posture/fighter), and a
%         hierarchical-clustering dendrogram.

clear; clc; close all;

%% 0. CONFIGURATION
fprintf('============ BODY MOVEMENT DTW SIMILARITY ============ \n');

BASE_LOC         = '\\mpib-berlin.mpg.de\Share\Projects\1223-xplo-judo\private\10_Data\sourcedata';
DERIVATIVES_LOC  = '\\mpib-berlin.mpg.de\Share\Projects\1223-xplo-judo\private\10_Data\derivatives';
% BASE_LOC        = 'C:\Data\Research\10_Data\sourcedata';
% DERIVATIVES_LOC = 'C:\Data\Research\10_Data\derivatives';
PIPELINE_NAME    = 'syncdata';
PIPELINE_ROOT    = fullfile(DERIVATIVES_LOC, PIPELINE_NAME);

taskName = 'heightaffordance';
pelvisLabel = 'Pelvis'; % must match a label in xsens_segment_labels
heightThreshold_cm = 180; % fighters with max stance > this are "tall", else "short"
max_missing_fraction = 0.10; % trials with more than this fraction of NaN samples (for a given analysis' channels) are skipped
dtw_distance_metric  = 'euclidean'; % 'euclidean' or 'absolute', passed to dtw()

% --- the two analyses to run ---
analysisDefs = struct('name', {}, 'description', {}, 'mode', {}, 'center_to_trial_start', {}, 'zscore', {});

analysisDefs(1).name = 'pelvis';
analysisDefs(1).description = 'Pelvis 3D position (x,y,z), centered to trial start -- captures translation/footwork.';
analysisDefs(1).mode = 'pelvis_absolute';
analysisDefs(1).center_to_trial_start = true;
analysisDefs(1).zscore = false; % x/y/z are already comparable units; usually leave off

analysisDefs(2).name = 'wholebody';
analysisDefs(2).description = 'All other segments'' 3D positions relative to the Pelvis at each time sample -- captures posture/configuration independent of locomotion.';
analysisDefs(2).mode = 'pelvis_relative_all_segments';
analysisDefs(2).center_to_trial_start = false; % already implicitly centered by the pelvis-relative transform
analysisDefs(2).zscore = true; % recommended: segments differ hugely in movement amplitude (hands vs spine), z-score keeps one limb from dominating the DTW sum

%% 1. PICK PARTICIPANT
if ~exist(PIPELINE_ROOT, 'dir')
    error('Pipeline root not found: %s\nHas s03_data_sync_interactive.m been run for anyone yet?', PIPELINE_ROOT);
end

subDirs = dir(fullfile(PIPELINE_ROOT, 'sub-*'));
subDirs = subDirs([subDirs.isdir]);
if isempty(subDirs)
    error('No sub-* folders found under %s', PIPELINE_ROOT);
end
subIDs = {subDirs.name};

[selIdx, ok] = listdlg('ListString', subIDs, 'SelectionMode', 'single', ...
    'PromptString', 'Select Participant ID:', 'ListSize', [300 300]);
if ~ok, error('Participant selection cancelled.'); end
subID = subIDs{selIdx};

fprintf('\nParticipant: %s\n', subID);
fprintf('Task:        %s\n', taskName);

%% 2. FIND ALL TRIAL MOTION FILES ACROSS ALL SESSIONS/RUNS FOR THIS TASK
searchPattern = sprintf('%s_*_task-%s_run-*_trial-*_desc-synchronized_motion.mat', subID, taskName);
sesDirs = dir(fullfile(PIPELINE_ROOT, subID, 'ses-*'));
sesDirs = sesDirs([sesDirs.isdir]);

trialFiles = {};
for s = 1:numel(sesDirs)
    motionDir = fullfile(PIPELINE_ROOT, subID, sesDirs(s).name, 'motion');
    if ~exist(motionDir, 'dir'), continue; end
    f = dir(fullfile(motionDir, searchPattern));
    for k = 1:numel(f)
        trialFiles{end+1} = fullfile(motionDir, f(k).name); %#ok<AGROW>
    end
end

if isempty(trialFiles)
    error('No synchronized motion files found for %s, task-%s, under %s', subID, taskName, PIPELINE_ROOT);
end
fprintf('Found %d trial motion file(s) across %d session folder(s).\n', numel(trialFiles), numel(sesDirs));

OUTPUT_DIR = fullfile(DERIVATIVES_LOC, 'motion_dtw_similarity', subID);
%% 3. LOAD EACH TRIAL: FULL-BODY TRAJECTORY + MATCHING CONDITION (fighterID/posture/stance)
trials = struct('label', {}, 'sessionID', {}, 'runID', {}, 'trialID', {}, 'file', {}, ...
                 'fullTraj', {}, 'segLabels', {}, 'pelvisSegIdx', {}, 'numSegments', {}, 'nSamples', {}, 'srate_est', {}, ...
                 'fighterID', {}, 'posture', {}, 'stance', {}, 'laterality', {}, 'cam', {}, 'block', {}, 'exemplar', {}, ...
                 'height', {}, 'heightCategory', {});

behCache = containers.Map(); % behPath -> condition table, avoids reloading the same run's file per trial

for i = 1:numel(trialFiles)
    thisFile = trialFiles{i};
    [~, baseName] = fileparts(thisFile);

    tok = regexp(baseName, 'ses-(?<ses>[^_]+)_task-[^_]+_run-(?<run>[^_]+)_trial-(?<trial>[^_]+)_desc-synchronized_motion', 'names');
    if isempty(tok)
        warning('  Skipping %s: filename does not match the expected ses-/run-/trial- pattern.', baseName);
        continue;
    end
    sessionID = tok.ses; runID = tok.run; trialID = tok.trial;
    trialLabel = sprintf('%s_run-%s_trial-%s', sessionID, runID, trialID);

    S = load(thisFile, 'syncTrialData');
    if ~isfield(S, 'syncTrialData')
        warning('  Skipping %s: does not contain syncTrialData.', baseName);
        continue;
    end
    d = S.syncTrialData;

    segLabels = d.xsens_segment_labels;
    pelvisSegIdx = find(strcmpi(segLabels, pelvisLabel), 1);
    if isempty(pelvisSegIdx)
        pelvisSegIdx = find(contains(segLabels, pelvisLabel, 'IgnoreCase', true), 1);
    end
    if isempty(pelvisSegIdx)
        warning('  Skipping %s: segment "%s" not found in xsens_segment_labels.', baseName, pelvisLabel);
        continue;
    end

    % --- load/match the condition table for this trial (fighterID, posture, stance, ...) ---
    behFilename = sprintf('%s_ses-%s_task-%s_run-%s_beh.mat', subID, sessionID, taskName, runID);
    behPath = fullfile(BASE_LOC, subID, ['ses-' sessionID], 'beh', behFilename);

    if isKey(behCache, behPath)
        condTable = behCache(behPath);
    else
        if ~exist(behPath, 'file')
            warning('  Skipping %s: condition file not found: %s', baseName, behPath);
            continue;
        end
        Sbeh = load(behPath);
        condTable = [];
        behVarNames = fieldnames(Sbeh);
        for v = 1:numel(behVarNames)
            candidate = Sbeh.(behVarNames{v});
            if istable(candidate) && all(ismember({'trial_id','fighterID','posture','stance'}, candidate.Properties.VariableNames))
                condTable = candidate;
                break;
            end
        end
        if isempty(condTable)
            warning('  Skipping %s: no table with trial_id/fighterID/posture/stance found in %s', baseName, behPath);
            continue;
        end
        behCache(behPath) = condTable; %#ok<NASGU>
    end

    trialNum = str2double(trialID);
    rowMatch = find(condTable.trial_id == trialNum, 1);
    if isempty(rowMatch)
        warning('  Skipping %s: trial_id %d not found in condition table %s', baseName, trialNum, behFilename);
        continue;
    end

    idx = numel(trials) + 1;
    trials(idx).label = trialLabel;
    trials(idx).sessionID = sessionID;
    trials(idx).runID = runID;
    trials(idx).trialID = trialID;
    trials(idx).file = thisFile;
    trials(idx).fullTraj = d.xsens_positions_3D; % numSegments*3 x nSamples, kept in full; each analysis extracts what it needs
    trials(idx).segLabels = segLabels;
    trials(idx).pelvisSegIdx = pelvisSegIdx;
    trials(idx).numSegments = numel(segLabels);
    trials(idx).nSamples = size(d.xsens_positions_3D, 2);
    if isfield(d, 'elapsed_trial_time') && numel(d.elapsed_trial_time) > 1
        trials(idx).srate_est = 1 / mean(diff(d.elapsed_trial_time));
    else
        trials(idx).srate_est = NaN;
    end

    trials(idx).fighterID  = char(string(condTable.fighterID(rowMatch)));
    trials(idx).posture    = char(string(condTable.posture(rowMatch)));
    trials(idx).stance     = condTable.stance(rowMatch);
    if ismember('laterality', condTable.Properties.VariableNames)
        trials(idx).laterality = char(string(condTable.laterality(rowMatch)));
    else
        trials(idx).laterality = '';
    end
    if ismember('cam', condTable.Properties.VariableNames), trials(idx).cam = condTable.cam(rowMatch); else, trials(idx).cam = NaN; end
    if ismember('block', condTable.Properties.VariableNames), trials(idx).block = condTable.block(rowMatch); else, trials(idx).block = NaN; end
    if ismember('exemplar', condTable.Properties.VariableNames), trials(idx).exemplar = condTable.exemplar(rowMatch); else, trials(idx).exemplar = NaN; end

    % height/heightCategory filled in step 4 below, once every fighter's max stance is known
    trials(idx).height = NaN;
    trials(idx).heightCategory = '';
end

if numel(trials) < 2
    error('Fewer than 2 usable trials found (%d) -- cannot compute pairwise similarity.', numel(trials));
end
fprintf('Usable trials after condition-matching checks: %d\n', numel(trials));

% Sanity check: warn (do not error) if effective sampling rates differ notably across trials,
% since DTW compares samples 1:1 in "distance per matched sample" terms, not physical time.
srates = [trials.srate_est];
srates = srates(~isnan(srates));
if ~isempty(srates) && (max(srates) - min(srates)) / mean(srates) > 0.05
    warning(['Estimated sampling rates vary by more than 5%% across trials (%.2f - %.2f Hz). ' ...
        'This is usually fine for DTW (it warps in sample space), but keep it in mind when interpreting durations.'], ...
        min(srates), max(srates));
end

%% 4. ESTIMATE FIGHTER HEIGHT (max "stance" value seen for that fighterID) AND ASSIGN CATEGORY
% Pooled across every condition table encountered above (i.e. every run touched by this
% participant's trials), not just the matched trial rows, so the max is as robust as possible.
allCondTables = values(behCache);
allCond = vertcat(allCondTables{:});
fighterIDs_all = string(allCond.fighterID);
uniqueFighters = unique(fighterIDs_all);

fighterHeightMap = containers.Map();
for f = 1:numel(uniqueFighters)
    fID = uniqueFighters(f);
    fighterHeightMap(char(fID)) = max(allCond.stance(fighterIDs_all == fID));
end

fprintf('\nFighter height estimates (max stance value observed):\n');
for f = 1:numel(uniqueFighters)
    fID = char(uniqueFighters(f));
    h = fighterHeightMap(fID);
    if h > heightThreshold_cm, cat = 'tall'; else, cat = 'short'; end
    fprintf('  %-10s h=%3d cm -> %s\n', fID, h, cat);
end

for i = 1:numel(trials)
    h = fighterHeightMap(trials(i).fighterID);
    trials(i).height = h;
    if h > heightThreshold_cm
        trials(i).heightCategory = 'tall';
    else
        trials(i).heightCategory = 'short';
    end
end

%% 4.5 SORT TRIALS: HEIGHT (tall->short) > POSTURE (upright->lowered) > FIGHTER (grouped) > original order
% Fighters are grouped consistently (same fighter order) within both the upright and lowered
% blocks of a height category, e.g.:
%   tallA-up, tallB-up, tallC-up, tallA-low, tallB-low, tallC-low, shortD-up, shortE-up, ...
% Fighter order within a height category = descending fighter height, then alphabetical fighterID.
fighterHeightsVec = arrayfun(@(f) fighterHeightMap(char(f)), uniqueFighters);
fighterOrderTbl = table(uniqueFighters(:), fighterHeightsVec(:), 'VariableNames', {'fighterID', 'height'});
fighterOrderTbl = sortrows(fighterOrderTbl, {'height', 'fighterID'}, {'descend', 'ascend'});
fighterRankMap = containers.Map(cellstr(fighterOrderTbl.fighterID), num2cell(1:height(fighterOrderTbl)));

heightCatRank = arrayfun(@(t) double(strcmpi(t.heightCategory, 'short')), trials); % tall=0, short=1
postureRank   = arrayfun(@(t) double(strcmpi(t.posture, 'lowered')), trials);      % upright=0, lowered=1
fighterRank   = arrayfun(@(t) fighterRankMap(t.fighterID), trials);

sortKeyTable = table((1:numel(trials))', heightCatRank(:), postureRank(:), fighterRank(:), ...
    'VariableNames', {'origIdx', 'heightCatRank', 'postureRank', 'fighterRank'});
sortKeyTable = sortrows(sortKeyTable, {'heightCatRank', 'postureRank', 'fighterRank'}); % stable: ties keep original order
trials = trials(sortKeyTable.origIdx);

fprintf('\nTrial order (shared by both analyses'' heatmaps):\n');
for i = 1:numel(trials)
    fprintf('  %2d. %-28s fighter=%-8s height=%3d (%-5s) posture=%s\n', ...
        i, trials(i).label, trials(i).fighterID, trials(i).height, trials(i).heightCategory, trials(i).posture);
end

%% 5. RUN EACH ANALYSIS (Pelvis, Whole Body)
for a = 1:numel(analysisDefs)
    A = analysisDefs(a);
    fprintf('\n---------------------------------------------------------\n');
    fprintf('ANALYSIS: %s\n  %s\n', A.name, A.description);
    fprintf('---------------------------------------------------------\n');

    analysisTrials = trials; % start from the full, already height/posture/fighter-sorted list
    keepMask = true(1, numel(analysisTrials));

    for i = 1:numel(analysisTrials)
        t = analysisTrials(i);
        pelvisRows = (3*t.pelvisSegIdx - 2):(3*t.pelvisSegIdx);

        switch A.mode
            case 'pelvis_absolute'
                traj = t.fullTraj(pelvisRows, :); % 3 x nSamples

            case 'pelvis_relative_all_segments'
                pelvisPos = t.fullTraj(pelvisRows, :); % 3 x nSamples
                relTraj = t.fullTraj - repmat(pelvisPos, t.numSegments, 1); % subtract pelvis xyz from every segment's xyz
                keepRows = true(3*t.numSegments, 1);
                keepRows(pelvisRows) = false; % drop the pelvis rows themselves -- now constantly zero, no information
                traj = relTraj(keepRows, :);

            otherwise
                error('Unknown analysis mode: %s', A.mode);
        end

        % --- per-analysis missing-data quality check ---
        missingFrac = mean(any(isnan(traj), 1));
        if missingFrac > max_missing_fraction
            fprintf('  [%s] excluding %s: %.1f%% missing samples (threshold %.0f%%)\n', ...
                A.name, t.label, 100*missingFrac, 100*max_missing_fraction);
            keepMask(i) = false;
            continue;
        elseif missingFrac > 0
            for r = 1:size(traj, 1)
                traj(r, :) = fillmissing(traj(r, :), 'linear', 'EndValues', 'nearest');
            end
        end

        if A.center_to_trial_start
            traj = traj - traj(:, 1);
        end

        analysisTrials(i).traj = traj;
    end

    analysisTrials = analysisTrials(keepMask);
    if numel(analysisTrials) < 2
        warning('  [%s] fewer than 2 usable trials after QC (%d) -- skipping this analysis.', A.name, numel(analysisTrials));
        continue;
    end
    fprintf('  [%s] usable trials after QC: %d / %d\n', A.name, numel(analysisTrials), numel(trials));

    % --- optional per-channel z-score across included trials ---
    if A.zscore
        nRows = size(analysisTrials(1).traj, 1);
        mu = zeros(nRows, 1); sig = zeros(nRows, 1);
        for r = 1:nRows
            rowVals = cell2mat(arrayfun(@(t) t.traj(r, :), analysisTrials, 'UniformOutput', false));
            mu(r) = mean(rowVals, 'omitnan');
            sig(r) = std(rowVals, 'omitnan');
        end
        sig(sig == 0) = 1;
        for i = 1:numel(analysisTrials)
            analysisTrials(i).traj = (analysisTrials(i).traj - mu) ./ sig;
        end
    end

    % --- pairwise DTW distance matrix ---
    nTrials = numel(analysisTrials);
    distMatrix = zeros(nTrials, nTrials);
    fprintf('  [%s] computing pairwise DTW distances (%d pairs, %d channels)...\n', ...
        A.name, nchoosek(nTrials, 2), size(analysisTrials(1).traj, 1));
    for i = 1:nTrials
        for j = (i+1):nTrials
            x = analysisTrials(i).traj;
            y = analysisTrials(j).traj;
            [dd, ix, ~] = dtw(x, y, dtw_distance_metric);
            distMatrix(i, j) = dd / numel(ix); % normalize by warping-path length so trial duration doesn't dominate
            distMatrix(j, i) = distMatrix(i, j);
        end
    end
    fprintf('  [%s] done.\n', A.name);

    trialLabels = {analysisTrials.label};
    plotLabels = arrayfun(@(t) sprintf('%s | %s | %dcm | %s', t.label, t.fighterID, t.height, t.posture), analysisTrials, 'UniformOutput', false);

    % --- save results ---
    analysisOutDir = fullfile(OUTPUT_DIR, A.name);
    if ~exist(analysisOutDir, 'dir'), mkdir(analysisOutDir); end

    outMatPath = fullfile(analysisOutDir, sprintf('%s_task-%s_desc-%sDTWsimilarity.mat', subID, taskName, A.name));
    outCsvPath = fullfile(analysisOutDir, sprintf('%s_task-%s_desc-%sDTWsimilarity.csv', subID, taskName, A.name));
    outMetaCsvPath = fullfile(analysisOutDir, sprintf('%s_task-%s_desc-%sTrialMetadata.csv', subID, taskName, A.name));

    save(outMatPath, 'distMatrix', 'trialLabels', 'analysisTrials', 'A', 'taskName', 'subID', ...
        'heightThreshold_cm', 'fighterHeightMap', 'max_missing_fraction');

    distTable = array2table(distMatrix, 'VariableNames', matlab.lang.makeValidName(trialLabels), 'RowNames', trialLabels);
    writetable(distTable, outCsvPath, 'WriteRowNames', true);

    metaTable = table({analysisTrials.label}', {analysisTrials.fighterID}', [analysisTrials.height]', {analysisTrials.heightCategory}', ...
        {analysisTrials.posture}', [analysisTrials.stance]', {analysisTrials.laterality}', [analysisTrials.cam]', ...
        [analysisTrials.block]', [analysisTrials.exemplar]', {analysisTrials.file}', ...
        'VariableNames', {'trial_label','fighterID','height_cm','heightCategory','posture','stance','laterality','cam','block','exemplar','file'});
    writetable(metaTable, outMetaCsvPath);

    fprintf('  [%s] saved to: %s\n', A.name, analysisOutDir);

    % --- heatmap, ordered by height/posture/fighter, with group separators ---
    figHeatmap = figure('Name', sprintf('%s DTW Distance Matrix', A.name), 'Color', 'w', 'Position', [100 100 1000 900]);
    imagesc(distMatrix);
    colormap(figHeatmap, parula);
    cb = colorbar; cb.Label.String = 'Normalized DTW distance (lower = more similar)';
    axis square;
    set(gca, 'XTick', 1:nTrials, 'XTickLabel', plotLabels, 'XTickLabelRotation', 90, ...
             'YTick', 1:nTrials, 'YTickLabel', plotLabels, 'FontSize', 7, 'TickLabelInterpreter', 'none');
    title(sprintf('%s -- task-%s -- %s: movement similarity (DTW)', subID, taskName, A.name), 'Interpreter', 'none');
    hold on;
    heightCats = {analysisTrials.heightCategory};
    postures   = {analysisTrials.posture};
    fighters   = {analysisTrials.fighterID};
    for i = 1:(nTrials - 1)
        if ~strcmp(heightCats{i}, heightCats{i+1})
            xline(i + 0.5, 'w-', 'LineWidth', 2.5);
            yline(i + 0.5, 'w-', 'LineWidth', 2.5);
        elseif ~strcmp(postures{i}, postures{i+1})
            xline(i + 0.5, 'w--', 'LineWidth', 1.5);
            yline(i + 0.5, 'w--', 'LineWidth', 1.5);
        elseif ~strcmp(fighters{i}, fighters{i+1})
            xline(i + 0.5, 'w:', 'LineWidth', 0.75);
            yline(i + 0.5, 'w:', 'LineWidth', 0.75);
        end
    end
    hold off;
    saveas(figHeatmap, fullfile(analysisOutDir, sprintf('%s_task-%s_desc-%sDTWheatmap.png', subID, taskName, A.name)));

    % --- clustering dendrogram (re-orders by similarity, independent of the height/posture ordering above) ---
    try
        condensedDist = squareform(distMatrix, 'tovector');
        Z = linkage(condensedDist, 'average');
        figDendro = figure('Name', sprintf('%s DTW Clustering', A.name), 'Color', 'w', 'Position', [100 100 1100 500]);
        dendrogram(Z, 0, 'Labels', plotLabels, 'Orientation', 'top');
        xtickangle(90);
        set(gca, 'FontSize', 7, 'TickLabelInterpreter', 'none');
        title(sprintf('%s -- task-%s -- %s: clustering (DTW, average linkage)', subID, taskName, A.name), 'Interpreter', 'none');
        ylabel('Normalized DTW distance');
        saveas(figDendro, fullfile(analysisOutDir, sprintf('%s_task-%s_desc-%sDTWdendrogram.png', subID, taskName, A.name)));
    catch ME
        warning('  [%s] clustering dendrogram skipped (Statistics and Machine Learning Toolbox required): %s', A.name, ME.message);
    end

    % --- mean DTW distance within each condition (height x posture) ---
    % For each of the 4 conditions (tall-upright, tall-lowered, short-upright, short-lowered),
    % average the pairwise DTW distance between all trials that share that condition. This is a
    % measure of movement CONSISTENCY within a condition (lower = more similar/stereotyped
    % movement across trials of that condition), not a comparison to other conditions' trials.
    groupHeights  = {'tall', 'short'};
    groupPostures = {'upright', 'lowered'};
    condMeanMat = nan(2, 2); condStdMat = nan(2, 2); condNTrials = zeros(2, 2); condNPairs = zeros(2, 2);
    for hIdx = 1:2
        for pIdx = 1:2
            condMask = strcmpi(heightCats, groupHeights{hIdx}) & strcmpi(postures, groupPostures{pIdx});
            condIdx = find(condMask);
            condNTrials(hIdx, pIdx) = numel(condIdx);
            if numel(condIdx) >= 2
                subDist = distMatrix(condIdx, condIdx);
                pairVals = subDist(triu(true(numel(condIdx)), 1));
                condMeanMat(hIdx, pIdx) = mean(pairVals);
                condStdMat(hIdx, pIdx) = std(pairVals);
                condNPairs(hIdx, pIdx) = numel(pairVals);
            end
        end
    end

    figCond = figure('Name', sprintf('%s Mean DTW Distance by Condition', A.name), 'Color', 'w', 'Position', [100 100 700 550]);
    bh = bar(condMeanMat);
    hold on;
    for pIdx = 1:2
        xpos = bh(pIdx).XEndPoints;
        errorbar(xpos, condMeanMat(:, pIdx), condStdMat(:, pIdx), 'k.', 'LineWidth', 1, 'HandleVisibility', 'off');
        for hIdx = 1:2
            if condNTrials(hIdx, pIdx) >= 2
                labelStr = sprintf('n=%d\n(%d pairs)', condNTrials(hIdx, pIdx), condNPairs(hIdx, pIdx));
            else
                labelStr = sprintf('n=%d\n(insufficient)', condNTrials(hIdx, pIdx));
            end
            yTop = condMeanMat(hIdx, pIdx) + condStdMat(hIdx, pIdx);
            if isnan(yTop), yTop = 0; end
            text(xpos(hIdx), yTop, labelStr, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 8);
        end
    end
    hold off;
    set(gca, 'XTickLabel', groupHeights);
    legend(groupPostures, 'Location', 'best');
    ylabel('Mean within-condition normalized DTW distance');
    title(sprintf('%s -- task-%s: movement consistency by condition', subID, taskName), 'Interpreter', 'none');
    saveas(figCond, fullfile(analysisOutDir, sprintf('%s_task-%s_desc-%sDTW_withinCondition.png', subID, taskName, A.name)));

    condSummaryTable = table( ...
        [repmat(groupHeights(1), 2, 1); repmat(groupHeights(2), 2, 1)], ...
        repmat(groupPostures(:), 2, 1), ...
        [condNTrials(1, :)'; condNTrials(2, :)'], ...
        [condNPairs(1, :)'; condNPairs(2, :)'], ...
        [condMeanMat(1, :)'; condMeanMat(2, :)'], ...
        [condStdMat(1, :)'; condStdMat(2, :)'], ...
        'VariableNames', {'heightCategory', 'posture', 'nTrials', 'nPairs', 'meanDTWdistance', 'stdDTWdistance'});
    writetable(condSummaryTable, fullfile(analysisOutDir, sprintf('%s_task-%s_desc-%sDTWbyCondition.csv', subID, taskName, A.name)));

    % --- NEW: Mean DTW Distance Between Specific Condition Pairs ---
    % Pair 1: short-upright vs short-lowered
    % Pair 2: tall-upright vs tall-lowered
    % Pair 3: tall-lowered vs short-upright

    % Define masks for each condition
    mask_short_up  = strcmpi(heightCats, 'short') & strcmpi(postures, 'upright');
    mask_short_low = strcmpi(heightCats, 'short') & strcmpi(postures, 'lowered');
    mask_tall_up   = strcmpi(heightCats, 'tall')  & strcmpi(postures, 'upright');
    mask_tall_low  = strcmpi(heightCats, 'tall')  & strcmpi(postures, 'lowered');

    % Function handle to extract off-diagonal/cross-condition pairwise distances
    % Function handle to extract cross-condition pairwise distances as a column vector
    getCrossDistances = @(m1, m2, dist) reshape(dist(m1, m2), [], 1);

    % Extract pairwise values for each requested pair
    p1_vals = getCrossDistances(mask_short_up, mask_short_low, distMatrix);
    p2_vals = getCrossDistances(mask_tall_up,  mask_tall_low,  distMatrix);
    p3_vals = getCrossDistances(mask_tall_low, mask_short_up,  distMatrix);

    pairValsCell = {p1_vals, p2_vals, p3_vals};
    pairMeans    = cellfun(@(x) mean(x, 'omitnan'), pairValsCell);
    pairStds     = cellfun(@(x) std(x, 'omitnan'),  pairValsCell);
    pairNPairs   = cellfun(@numel, pairValsCell);

    pairLabels = { ...
        sprintf('Short-Up vs Short-Low'), ...
        sprintf('Tall-Up vs Tall-Low'), ...
        sprintf('Tall-Low vs Short-Up')};

    % Plot Pairwise Comparisons
    figCrossCond = figure('Name', sprintf('%s Mean DTW Distance Across Pairs', A.name), ...
        'Color', 'w', 'Position', [150 150 650 500]);
    
    bCross = bar(pairMeans, 'FaceColor', [0.2 0.6 0.8]);
    hold on;
    errorbar(1:3, pairMeans, pairStds, 'k.', 'LineWidth', 1.2, 'HandleVisibility', 'off');

    % Add count labels above bars
    for pIdx = 1:3
        if pairNPairs(pIdx) > 0 && ~isnan(pairMeans(pIdx))
            lbl = sprintf('n=%d pairs', pairNPairs(pIdx));
            yPos = pairMeans(pIdx) + pairStds(pIdx);
        else
            lbl = 'n/a';
            yPos = 0;
        end
        text(pIdx, yPos, lbl, 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'bottom', 'FontSize', 8);
    end
    hold off;

    set(gca, 'XTick', 1:3, 'XTickLabel', pairLabels, 'FontSize', 9);
    ylabel('Mean normalized DTW distance');
    title(sprintf('%s -- task-%s: distance between condition pairs', subID, taskName), 'Interpreter', 'none');
    grid on; grid minor;

    % Save plot & table
    saveas(figCrossCond, fullfile(analysisOutDir, sprintf('%s_task-%s_desc-%sDTWAcrossCondition.png', subID, taskName, A.name)));

    pairSummaryTable = table( ...
        {'short-upright vs short-lowered'; 'tall-upright vs tall-lowered'; 'tall-lowered vs short-upright'}, ...
        pairNPairs', pairMeans', pairStds', ...
        'VariableNames', {'ConditionPair', 'nPairs', 'meanDTWdistance', 'stdDTWdistance'});
    writetable(pairSummaryTable, fullfile(analysisOutDir, sprintf('%s_task-%s_desc-%sDTW_AcrossCondition.csv', subID, taskName, A.name)));
    % done across-condition comparisons
    
    % --- summary ---
    offDiag = distMatrix; offDiag(logical(eye(nTrials))) = Inf;
    [minVal, minIdx] = min(offDiag(:)); [mi, mj] = ind2sub(size(offDiag), minIdx);
    offDiag2 = distMatrix; offDiag2(logical(eye(nTrials))) = -Inf;
    [maxVal, maxIdx] = max(offDiag2(:)); [mi2, mj2] = ind2sub(size(offDiag2), maxIdx);
    fprintf('  [%s] most similar:  %s <-> %s (d=%.4f)\n', A.name, trialLabels{mi}, trialLabels{mj}, minVal);
    fprintf('  [%s] least similar: %s <-> %s (d=%.4f)\n', A.name, trialLabels{mi2}, trialLabels{mj2}, maxVal);
end

fprintf('\n============ DONE ============\n');