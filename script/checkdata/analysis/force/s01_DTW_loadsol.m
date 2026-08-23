%% Ground Reaction Force Similarity Across Trials via Dynamic Time Warping (DTW)
% Description: Standalone script -- picks a participant, finds every trial's synchronized
%              motion .mat file (as exported by s03_data_sync_function.m / s03_data_sync_interactive.m)
%              across ALL sessions and runs of a given task, and runs ONE DTW similarity analysis:
%
%              LOADSOL  -- Right + Left foot ground reaction force, stacked as a 2-channel signal
%                          [loadsol_force_N_right; loadsol_force_N_left] (Newtons). DTW aligns the
%                          two-channel R+L force trace of one trial against another, so the distance
%                          reflects both the SHAPE (timing/magnitude of loading) and the L/R BALANCE
%                          of the force profile jointly, not just one foot in isolation.
%
%              NOTE ON CROSS-PARTICIPANT COMPARABILITY: unlike position/COM, force in Newtons scales
%              with body MASS, not height. This script normalizes each trial's forces by that
%              participant's body weight (in Newtons, from a participants.tsv demographics file --
%              see WEIGHT NORMALIZATION config below), so distances are comparable across fighters
%              of different mass. Both channels are divided by the SAME participant-level body
%              weight (not z-scored independently), so R/L asymmetry is preserved as part of the
%              compared signal -- only the overall body-mass scale is removed.
%
%              Trials are ordered in the heatmap: height (tall -> short) > posture (upright -> lowered)
%              > fighter (grouped) > original trial order -- same convention as s04_DTW.m, for visual
%              consistency across this project's DTW outputs.
%
% Requires: Signal Processing Toolbox (dtw), Statistics and Machine Learning Toolbox
%           (pdist/linkage/dendrogram helpers -- only used for the optional clustering plot)
%
% Input:  .mat files produced by s03_data_sync_function.m / s03_data_sync_interactive.m
%         (PIPELINE_ROOT/sub-*/ses-*/motion/*_desc-synchronized_motion.mat)
%         + condition tables in sourcedata/sub-*/ses-*/beh/*_beh.mat
%         + a participants demographics file with body weight/mass (see WEIGHT NORMALIZATION below)
% Output: pairwise DTW distance matrix + trial metadata (.mat + .csv), a distance-matrix heatmap
%         (ordered by height/posture/fighter), and a hierarchical-clustering dendrogram, all saved
%         under derivatives/motion_dtw_similarity/<subID>/loadsol/

clear; clc; close all;

%% 0. CONFIGURATION
fprintf('============ LOADSOL (L+R) DTW SIMILARITY ============ \n');

BASE_LOC         = '\\mpib-berlin.mpg.de\Share\Projects\1223-xplo-judo\private\10_Data\sourcedata';
DERIVATIVES_LOC  = '\\mpib-berlin.mpg.de\Share\Projects\1223-xplo-judo\private\10_Data\derivatives';
% BASE_LOC        = 'C:\Data\Research\10_Data\sourcedata';
% DERIVATIVES_LOC = 'C:\Data\Research\10_Data\derivatives';
PIPELINE_NAME    = 'syncdata';
PIPELINE_ROOT    = fullfile(DERIVATIVES_LOC, PIPELINE_NAME);

taskName = 'heightaffordance';
heightThreshold_cm   = 180;   % fighters with max stance > this are "tall", else "short" (grouping/plot order only)
max_missing_fraction = 0.10;  % trials with more than this fraction of NaN samples (either channel) are skipped
dtw_distance_metric   = 'euclidean'; % 'euclidean' or 'absolute', passed to dtw()

% --- WEIGHT NORMALIZATION -------------------------------------------------------------------
% Divides each trial's [right; left] force by that fighter's body weight in Newtons, so DTW
% distances are comparable across participants of different body mass. Source: the LimeSurvey
% posttest_questionnaire.csv export, which holds every participant's answers -- comma-delimited,
% quoted headers, ID/Height/Weight columns already have simple names even though most other
% columns are messy LimeSurvey question codes (e.g. "TechniqueUse[T01_When]").
weight_normalize      = true;
PARTICIPANTS_CSV      = fullfile(BASE_LOC, 'posttest_questionnaire.csv'); % adjust path if stored elsewhere
participants_id_col   = 'ID';       
participants_mass_col = 'Weight';   % body mass in kg (e.g. 86 for ID "K2DJJ8")
participants_mass_is_kg = true;
GRAVITY_MS2 = 9.81;
% ---------------------------------------------------------------------------------------------
zscore_channels        = false; % if true, z-score right/left channels independently across included trials before DTW,
                                 % so a naturally larger dominant-leg force doesn't dominate the DTW sum over the non-dominant leg.
                                 % Leave false to preserve raw L/R magnitude asymmetry as part of the compared signal.

analysisName = 'loadsol';
analysisDescription = 'Right+Left foot ground reaction force (N), stacked as a 2-channel signal -- captures loading shape and L/R balance jointly.';

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

%% 3. LOAD EACH TRIAL: LOADSOL R+L FORCE + MATCHING CONDITION (fighterID/posture/stance)
trials = struct('label', {}, 'sessionID', {}, 'runID', {}, 'trialID', {}, 'file', {}, ...
                 'forceLR', {}, 'nSamples', {}, 'srate_est', {}, ...
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

    % --- validate loadsol fields before doing anything else with this trial ---
    if ~isfield(d, 'loadsol_force_N_right') || ~isfield(d, 'loadsol_force_N_left')
        warning('  Skipping %s: loadsol_force_N_right/left field(s) missing from syncTrialData.', baseName);
        continue;
    end
    fR = d.loadsol_force_N_right(:)'; % force to row vector regardless of stored orientation
    fL = d.loadsol_force_N_left(:)';
    if numel(fR) ~= numel(fL)
        warning('  Skipping %s: right (%d samples) and left (%d samples) loadsol channels have mismatched length.', ...
            baseName, numel(fR), numel(fL));
        continue;
    end
    if numel(fR) < 2
        warning('  Skipping %s: loadsol channels have too few samples (%d).', baseName, numel(fR));
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
    trials(idx).forceLR = [fR; fL]; % 2 x nSamples: row 1 = right, row 2 = left
    trials(idx).nSamples = numel(fR);
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
% Used only for heatmap grouping/ordering below -- loadsol force itself is NOT height-normalized
% (force scales with body mass, not height; see header note).
allCondTables = values(behCache);
allCond = vertcat(allCondTables{:});
fighterIDs_all = string(allCond.fighterID);
uniqueFighters = unique(fighterIDs_all);

fighterHeightMap = containers.Map();
for f = 1:numel(uniqueFighters)
    fID = uniqueFighters(f);
    fighterHeightMap(char(fID)) = max(allCond.stance(fighterIDs_all == fID));
end

fprintf('\nFighter height estimates (max stance value observed, grouping/plot order only):\n');
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

%% 4.1 LOAD BODY WEIGHT (for force normalization, section 5 below)
fighterWeightMap = containers.Map();
if weight_normalize
    if ~exist(PARTICIPANTS_CSV, 'file')
        error(['weight_normalize is true but posttest questionnaire file not found: %s\n' ...
               'Set weight_normalize = false to run unnormalized, or fix PARTICIPANTS_CSV.'], PARTICIPANTS_CSV);
    end

    partTbl = readtable(PARTICIPANTS_CSV, 'FileType', 'text', 'Delimiter', ',');
    if ~ismember(participants_id_col, partTbl.Properties.VariableNames)
        error('Column "%s" not found in %s. Available columns: %s', ...
            participants_id_col, PARTICIPANTS_CSV, strjoin(partTbl.Properties.VariableNames, ', '));
    end
    if ~ismember(participants_mass_col, partTbl.Properties.VariableNames)
        error('Column "%s" not found in %s. Available columns: %s', ...
            participants_mass_col, PARTICIPANTS_CSV, strjoin(partTbl.Properties.VariableNames, ', '));
    end
    partIDs = string(partTbl.(participants_id_col));

    if ~ismember(participants_id_col, partTbl.Properties.VariableNames)
        error('Column "%s" not found in %s.', participants_id_col, PARTICIPANTS_CSV);
    end
    if ~ismember(participants_mass_col, partTbl.Properties.VariableNames)
        error('Column "%s" not found in %s.', participants_mass_col, PARTICIPANTS_CSV);
    end

    partIDs = strtrim(string(partTbl.(participants_id_col)));
    
    % Get Subject Weight
    subKey = erase(subID, "sub-");
    rowMatch = find(partIDs == subKey, 1);
    if isempty(rowMatch)
        error('Subject ID "%s" not found in %s.', subKey, PARTICIPANTS_CSV);
    end
    
    subMass = partTbl.(participants_mass_col)(rowMatch);
    if isnan(subMass) || subMass <= 0
        error('Invalid weight value for subject "%s".', subKey);
    end
    
    subjectWeight_N = subMass * (participants_mass_is_kg * GRAVITY_MS2 + ~participants_mass_is_kg);
    fprintf('\nNormalized by Subject %s Body Weight: %.1f N (%.1f kg)\n', subID, subjectWeight_N, subMass);
end

%% 4.2 SORT TRIALS: HEIGHT (tall->short) > POSTURE (upright->lowered) > FIGHTER (grouped) > original order
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

fprintf('\nTrial order (heatmap):\n');
for i = 1:numel(trials)
    fprintf('  %2d. %-28s fighter=%-8s height=%3d (%-5s) posture=%s\n', ...
        i, trials(i).label, trials(i).fighterID, trials(i).height, trials(i).heightCategory, trials(i).posture);
end

%% 5. QUALITY CHECK, OPTIONAL Z-SCORE, AND PAIRWISE DTW
fprintf('\n---------------------------------------------------------\n');
fprintf('ANALYSIS: %s\n  %s\n', analysisName, analysisDescription);
fprintf('---------------------------------------------------------\n');

analysisTrials = trials;
keepMask = true(1, numel(analysisTrials));

for i = 1:numel(analysisTrials)
    t = analysisTrials(i);
    traj = t.forceLR; % 2 x nSamples: row 1 = right, row 2 = left

    % --- missing-data quality check (either channel) ---
    missingFrac = mean(any(isnan(traj), 1));
    if missingFrac > max_missing_fraction
        fprintf('  [%s] excluding %s: %.1f%% missing samples (threshold %.0f%%)\n', ...
            analysisName, t.label, 100*missingFrac, 100*max_missing_fraction);
        keepMask(i) = false;
        continue;
    elseif missingFrac > 0
        for r = 1:size(traj, 1)
            traj(r, :) = fillmissing(traj(r, :), 'linear', 'EndValues', 'nearest');
        end
    end

    % --- weight normalization: both channels divided by the SAME body weight, so R/L asymmetry
    %     is preserved -- only the participant-level mass scale is removed ---
    if weight_normalize
        bw_N = fighterWeightMap(t.fighterID);
        traj = traj / bw_N;
    end

    analysisTrials(i).traj = traj;
end

analysisTrials = analysisTrials(keepMask);
if numel(analysisTrials) < 2
    error('[%s] fewer than 2 usable trials after QC (%d) -- cannot compute pairwise similarity.', analysisName, numel(analysisTrials));
end
fprintf('  [%s] usable trials after QC: %d / %d\n', analysisName, numel(analysisTrials), numel(trials));

% --- optional per-channel z-score across included trials (right vs left kept separate) ---
if zscore_channels
    nRows = size(analysisTrials(1).traj, 1); % always 2 (right, left)
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
    analysisName, nchoosek(nTrials, 2), size(analysisTrials(1).traj, 1));
for i = 1:nTrials
    for j = (i+1):nTrials
        x = analysisTrials(i).traj;
        y = analysisTrials(j).traj;
        [dd, ix, ~] = dtw(x, y, dtw_distance_metric);
        distMatrix(i, j) = dd / numel(ix); % normalize by warping-path length so trial duration doesn't dominate
        distMatrix(j, i) = distMatrix(i, j);
    end
end
fprintf('  [%s] done.\n', analysisName);

trialLabels = {analysisTrials.label};
plotLabels = arrayfun(@(t) sprintf('%s | %s | %dcm | %s', t.label, t.fighterID, t.height, t.posture), analysisTrials, 'UniformOutput', false);

%% 6. SAVE RESULTS
analysisOutDir = fullfile(OUTPUT_DIR, analysisName);
if ~exist(analysisOutDir, 'dir'), mkdir(analysisOutDir); end

outMatPath = fullfile(analysisOutDir, sprintf('%s_task-%s_desc-%sDTWsimilarity.mat', subID, taskName, analysisName));
outCsvPath = fullfile(analysisOutDir, sprintf('%s_task-%s_desc-%sDTWsimilarity.csv', subID, taskName, analysisName));
outMetaCsvPath = fullfile(analysisOutDir, sprintf('%s_task-%s_desc-%sTrialMetadata.csv', subID, taskName, analysisName));

save(outMatPath, 'distMatrix', 'trialLabels', 'analysisTrials', 'analysisName', 'taskName', 'subID', ...
    'heightThreshold_cm', 'fighterHeightMap', 'max_missing_fraction', 'zscore_channels', ...
    'weight_normalize', 'fighterWeightMap');

distTable = array2table(distMatrix, 'VariableNames', matlab.lang.makeValidName(trialLabels), 'RowNames', trialLabels);
writetable(distTable, outCsvPath, 'WriteRowNames', true);

metaTable = table({analysisTrials.label}', {analysisTrials.fighterID}', [analysisTrials.height]', {analysisTrials.heightCategory}', ...
    {analysisTrials.posture}', [analysisTrials.stance]', {analysisTrials.laterality}', [analysisTrials.cam]', ...
    [analysisTrials.block]', [analysisTrials.exemplar]', [analysisTrials.srate_est]', {analysisTrials.file}', ...
    'VariableNames', {'trial_label','fighterID','height_cm','heightCategory','posture','stance','laterality','cam','block','exemplar','srate_est_Hz','file'});
writetable(metaTable, outMetaCsvPath);

fprintf('  [%s] saved to: %s\n', analysisName, analysisOutDir);

%% 7. HEATMAP, ordered by height/posture/fighter, with group separators
figHeatmap = figure('Name', sprintf('%s DTW Distance Matrix', analysisName), 'Color', 'w', 'Position', [100 100 1000 900]);
imagesc(distMatrix);
colormap(figHeatmap, parula);
cb = colorbar; cb.Label.String = 'Normalized DTW distance (lower = more similar)';
axis square;
set(gca, 'XTick', 1:nTrials, 'XTickLabel', plotLabels, 'XTickLabelRotation', 90, ...
         'YTick', 1:nTrials, 'YTickLabel', plotLabels, 'FontSize', 7, 'TickLabelInterpreter', 'none');
title(sprintf('%s -- task-%s -- %s: movement similarity (DTW)', subID, taskName, analysisName), 'Interpreter', 'none');
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
saveas(figHeatmap, fullfile(analysisOutDir, sprintf('%s_task-%s_desc-%sDTWheatmap.png', subID, taskName, analysisName)));

%% 8. CLUSTERING DENDROGRAM (re-orders by similarity, independent of the height/posture ordering above)
try
    condensedDist = squareform(distMatrix, 'tovector');
    Z = linkage(condensedDist, 'average');
    figDendro = figure('Name', sprintf('%s DTW Clustering', analysisName), 'Color', 'w', 'Position', [100 100 1100 500]);
    dendrogram(Z, 0, 'Labels', plotLabels, 'Orientation', 'top');
    xtickangle(90);
    set(gca, 'FontSize', 7, 'TickLabelInterpreter', 'none');
    title(sprintf('%s -- task-%s -- %s: clustering (DTW, average linkage)', subID, taskName, analysisName), 'Interpreter', 'none');
    ylabel('Normalized DTW distance');
    saveas(figDendro, fullfile(analysisOutDir, sprintf('%s_task-%s_desc-%sDTWdendrogram.png', subID, taskName, analysisName)));
catch ME
    warning('  [%s] clustering dendrogram skipped (Statistics and Machine Learning Toolbox required): %s', analysisName, ME.message);
end

%% 9. SUMMARY
offDiag = distMatrix; offDiag(logical(eye(nTrials))) = Inf;
[minVal, minIdx] = min(offDiag(:)); [mi, mj] = ind2sub(size(offDiag), minIdx);
offDiag2 = distMatrix; offDiag2(logical(eye(nTrials))) = -Inf;
[maxVal, maxIdx] = max(offDiag2(:)); [mi2, mj2] = ind2sub(size(offDiag2), maxIdx);
fprintf('  [%s] most similar:  %s <-> %s (d=%.4f)\n', analysisName, trialLabels{mi}, trialLabels{mj}, minVal);
fprintf('  [%s] least similar: %s <-> %s (d=%.4f)\n', analysisName, trialLabels{mi2}, trialLabels{mj2}, maxVal);

fprintf('\n============ DONE ============\n');