%% CNV extraction: Neutral-locked and Fight-locked, shared pre-Neutral baseline
%
% Rationale: CNV is the slow negativity building from S1 (Neutral) toward
% S2 (Fight). Baselining the Fight-locked epoch using a window just before
% Fight would subtract out part of the CNV itself. Instead, this script
% computes ONE baseline per trial from the pre-Neutral period and applies
% it to both the Neutral-locked and Fight-locked versions of that trial.

clear; clc;

if ~exist('ALLCOM','var')
    [ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab;
end

run('tp_judo_bemobil_config.m');

%% 1. USER METADATA INPUT
prompt = { ...
    'Enter Participant ID (e.g., MH9HXJ):', ...
    'Enter Session ID (e.g., S001):', ...
    'Enter Task Name (e.g., heightaffordance):', ...
    'Enter Run ID (e.g., 001):' ...
};
dlgtitle = 'CNV Analysis - Participant Selection';
dims = [1 50];
definput = {'MH9HXJ', 'S001', 'heightaffordance', '001'};
userInput = inputdlg(prompt, dlgtitle, dims, definput);
if isempty(userInput), error('Processing cancelled.'); end

participantID = userInput{1};
sessionID     = userInput{2};
taskName      = userInput{3};
runID         = userInput{4};

bids_base_string = sprintf('%s_ses-%s_task-%s_run-%s', participantID, sessionID, taskName, runID);

%% 2. ANALYSIS SETTINGS — adjust after checking the jitter report printed below
% Trial timing: Neutral = t0, Fight stimulus onset = +500ms, window of interest extends to +1000ms post-Fight
baseline_window        = [-200 0];     % ms, pre-Neutral, used for BOTH locks
neutral_epoch_window   = [-0.2 1.5];   % s, relative to Neutral (covers baseline through the post-Fight window of interest)
fight_epoch_window     = [-0.7 1.0];   % s, relative to Fight (-0.7s reaches exactly to -200ms pre-Neutral)

% CNV quantification windows — defaults assume a FIXED 500ms Neutral->Fight interval (no jitter).
% neutral_late/fight_terminal both sample the anticipatory period just before Fight, viewed from each lock.
% fight_response is NOT part of the CNV — it's the post-Fight (500-1000ms after Fight) window of interest,
% kept separate since it reflects motor execution/response rather than anticipatory slow-wave activity.
cnv_windows = struct( ...
    'neutral_early',  [100 300], ...   % ms post-Neutral: orienting-related CNV
    'neutral_late',   [350 480], ...   % ms post-Neutral: anticipatory CNV, just before Fight
    'fight_terminal', [-150 0], ...    % ms pre-Fight: terminal CNV amplitude at S2
    'fight_response', [500 1000] ...   % ms post-Fight: window of interest (not CNV — likely response/motor activity)
);

expected_jitter_ms = 500; % expected fixed Neutral->Fight isi, for the sanity-check warning below

roi_labels = {'Fz','Cz'};

analysis_filepath = fullfile(bemobil_config.study_folder, bemobil_config.single_subject_analysis_folder, ...
    [bemobil_config.filename_prefix bids_base_string]);

cnv_epoched_filepath = fullfile(analysis_filepath, 'epoched', 'CNV');
if ~exist(cnv_epoched_filepath, 'dir'), mkdir(cnv_epoched_filepath); end

cleaned_versions = {'cleaned_eyeOnly.set', 'cleaned_eyeMuscle.set'};

results_table = table();

%% 3. PROCESS EACH CLEANED VERSION
for v = 1:numel(cleaned_versions)

    infile = [bemobil_config.filename_prefix bids_base_string '_' cleaned_versions{v}];
    EEG_continuous = pop_loadset('filename', infile, 'filepath', analysis_filepath);

    version_label = erase(cleaned_versions{v}, {'cleaned_', '.set'});
    fprintf('\n=== %s (%s) ===\n', infile, version_label);

    % --- Identify Neutral<N> and Fight<N> events dynamically ---
    allevents = {EEG_continuous.event.type};
    neutral_mask = ~cellfun(@isempty, regexp(allevents, '^Neutral\d+$', 'once'));
    fight_mask   = ~cellfun(@isempty, regexp(allevents, '^Fight\d+$', 'once'));
    neutral_types = unique(allevents(neutral_mask));
    fight_types   = unique(allevents(fight_mask));

    if isempty(neutral_types) || isempty(fight_types)
        warning('Missing Neutral or Fight events in %s — skipping.', infile);
        continue
    end

    % --- Report empirical Neutral->Fight jitter as a sanity check ---
    neutral_idx = find(neutral_mask);
    jitters_ms = nan(size(neutral_idx));
    for i = 1:numel(neutral_idx)
        trial_num = regexp(allevents{neutral_idx(i)}, '\d+$', 'match', 'once');
        fight_i = find(strcmp(allevents, ['Fight' trial_num]));
        if ~isempty(fight_i)
            dt_samples = EEG_continuous.event(fight_i(1)).latency - EEG_continuous.event(neutral_idx(i)).latency;
            jitters_ms(i) = dt_samples / EEG_continuous.srate * 1000;
        end
    end
    fprintf('Neutral->Fight jitter: mean=%.0fms, min=%.0fms, max=%.0fms (n=%d trials)\n', ...
        mean(jitters_ms,'omitnan'), min(jitters_ms), max(jitters_ms), sum(~isnan(jitters_ms)));
    if any(abs(jitters_ms - expected_jitter_ms) > 50)
        warning('Some trials deviate more than 50ms from the expected %dms Neutral->Fight interval — check cnv_windows/epoch windows above.', expected_jitter_ms);
    end

    % --- Epoch 1: Neutral-locked ---
    EEG_neutral = pop_epoch(EEG_continuous, neutral_types, neutral_epoch_window, 'epochinfo', 'yes');
    EEG_neutral = eeg_checkset(EEG_neutral, 'eventconsistency');

    % Compute per-trial, per-channel baseline BEFORE correcting, so it can be reused for the Fight-locked epoch
    base_idx = EEG_neutral.times >= baseline_window(1) & EEG_neutral.times <= baseline_window(2);
    baseline_values = mean(EEG_neutral.data(:, base_idx, :), 2); % [nchan x 1 x ntrials]
    neutral_trial_nums = get_trial_numbers(EEG_neutral, 'Neutral');

    EEG_neutral.data = EEG_neutral.data - baseline_values; % manual baseline correction (equivalent to pop_rmbase here)

    % --- Epoch 2: Fight-locked (from a fresh copy of the continuous data) ---
    EEG_fight = pop_epoch(EEG_continuous, fight_types, fight_epoch_window, 'epochinfo', 'yes');
    EEG_fight = eeg_checkset(EEG_fight, 'eventconsistency');
    fight_trial_nums = get_trial_numbers(EEG_fight, 'Fight');

    % --- Match trials between the two epoch sets (windows/rejections can differ at recording edges) ---
    [common_nums, i_neutral, i_fight] = intersect(neutral_trial_nums, fight_trial_nums);
    if numel(common_nums) < numel(neutral_trial_nums)
        warning('%d trial(s) present in Neutral-locked but not Fight-locked epochs (or vice versa) — using only the %d common trials.', ...
            numel(neutral_trial_nums) - numel(common_nums), numel(common_nums));
    end
    EEG_neutral = pop_select(EEG_neutral, 'trial', i_neutral);
    EEG_fight   = pop_select(EEG_fight, 'trial', i_fight);
    baseline_values_matched = baseline_values(:, :, i_neutral);

    % Apply the SAME pre-Neutral baseline to the Fight-locked epoch — do not baseline near Fight itself
    EEG_fight.data = EEG_fight.data - baseline_values_matched;

    % --- Save both epoch sets ---
    outfile_neutral = [bemobil_config.filename_prefix bids_base_string '_' version_label '_CNV_Neutral-locked.set'];
    outfile_fight    = [bemobil_config.filename_prefix bids_base_string '_' version_label '_CNV_Fight-locked.set'];
    pop_saveset(EEG_neutral, 'filename', outfile_neutral, 'filepath', cnv_epoched_filepath);
    pop_saveset(EEG_fight, 'filename', outfile_fight, 'filepath', cnv_epoched_filepath);
    fprintf('Saved %d matched trials to:\n  %s\n  %s\n', numel(common_nums), outfile_neutral, outfile_fight);

    % --- Quantify CNV in ROI channels ---
    roi_idx = find(ismember({EEG_neutral.chanlocs.labels}, roi_labels));
    if isempty(roi_idx)
        warning('None of the ROI channels %s found in %s — skipping CNV quantification.', strjoin(roi_labels, ', '), infile);
        continue
    end

    early_win  = EEG_neutral.times >= cnv_windows.neutral_early(1) & EEG_neutral.times <= cnv_windows.neutral_early(2);
    late_win   = EEG_neutral.times >= cnv_windows.neutral_late(1)  & EEG_neutral.times <= cnv_windows.neutral_late(2);
    term_win   = EEG_fight.times   >= cnv_windows.fight_terminal(1) & EEG_fight.times  <= cnv_windows.fight_terminal(2);
    resp_win   = EEG_fight.times   >= cnv_windows.fight_response(1) & EEG_fight.times  <= cnv_windows.fight_response(2);

    cnv_early_amp     = squeeze(mean(mean(EEG_neutral.data(roi_idx, early_win, :), 1), 2));
    cnv_late_amp       = squeeze(mean(mean(EEG_neutral.data(roi_idx, late_win, :), 1), 2));
    cnv_terminal_amp   = squeeze(mean(mean(EEG_fight.data(roi_idx, term_win, :), 1), 2));
    post_fight_amp      = squeeze(mean(mean(EEG_fight.data(roi_idx, resp_win, :), 1), 2)); % not CNV — see comment above

    %% Plot grand-average CNV waveform: Neutral-locked vs Fight-locked
    grand_neutral = squeeze(mean(mean(EEG_neutral.data(roi_idx, :, :), 1), 3));
    sem_neutral   = squeeze(std(mean(EEG_neutral.data(roi_idx, :, :), 1), 0, 3)) / sqrt(EEG_neutral.trials);
    grand_fight   = squeeze(mean(mean(EEG_fight.data(roi_idx, :, :), 1), 3));
    sem_fight     = squeeze(std(mean(EEG_fight.data(roi_idx, :, :), 1), 0, 3)) / sqrt(EEG_fight.trials);
    mean_jitter   = mean(jitters_ms(ismember(1:numel(jitters_ms), i_neutral)), 'omitnan');

    fig = figure('Color', 'w', 'Position', [100 100 1000 420]);

    subplot(1,2,1); hold on
    fill([EEG_neutral.times, fliplr(EEG_neutral.times)], ...
        [grand_neutral + sem_neutral, fliplr(grand_neutral - sem_neutral)], ...
        [0.7 0.7 0.95], 'EdgeColor', 'none', 'FaceAlpha', 0.5);
    plot(EEG_neutral.times, grand_neutral, 'b', 'LineWidth', 1.5);
    xline(0, 'k--', 'Neutral onset');
    xline(mean_jitter, 'r--', 'Mean Fight onset');
    xline(cnv_windows.neutral_early, 'k:');
    xline(cnv_windows.neutral_late, 'g:');
    set(gca, 'YDir', 'reverse'); grid on
    ylim([-15 25]);
    xlabel('Time relative to Neutral (ms)'); ylabel('Amplitude (\muV)');
    title('Neutral-locked');

    subplot(1,2,2); hold on
    fill([EEG_fight.times, fliplr(EEG_fight.times)], ...
        [grand_fight + sem_fight, fliplr(grand_fight - sem_fight)], ...
        [0.95 0.75 0.75], 'EdgeColor', 'none', 'FaceAlpha', 0.5);
    plot(EEG_fight.times, grand_fight, 'r', 'LineWidth', 1.5);
    xline(0, 'k--', 'Fight onset');
    xline(cnv_windows.fight_terminal, 'm:');
    xline(cnv_windows.fight_response, 'c:');
    set(gca, 'YDir', 'reverse'); grid on
    ylim([-15 25]);
    xlabel('Time relative to Fight (ms)'); ylabel('Amplitude (\muV)');
    title('Fight-locked');

    sgtitle(sprintf('CNV grand average — %s, %s cleaning, ROI = %s (n=%d trials)', ...
        participantID, version_label, strjoin(roi_labels, ', '), numel(common_nums)), 'Interpreter', 'none');

    fig_filename = fullfile(cnv_epoched_filepath, [bemobil_config.filename_prefix bids_base_string '_' version_label '_CNV_plot.png']);
    saveas(fig, fig_filename);
    fprintf('Saved CNV plot to: %s\n', fig_filename);

    trial_rows = table(common_nums(:), repmat({participantID}, numel(common_nums),1), repmat({version_label}, numel(common_nums),1), ...
        cnv_early_amp(:), cnv_late_amp(:), cnv_terminal_amp(:), post_fight_amp(:), jitters_ms(ismember(1:numel(jitters_ms), i_neutral))', ...
        'VariableNames', {'trial','participantID','cleaning_version','CNV_early_uV','CNV_late_uV','CNV_terminal_uV','postFight_500to1000ms_uV','jitter_ms'});
    results_table = [results_table; trial_rows]; %#ok<AGROW>
end

%% 4. SAVE PER-TRIAL CNV RESULTS TABLE
results_filename = fullfile(cnv_epoched_filepath, [bemobil_config.filename_prefix bids_base_string '_CNV_results.csv']);
writetable(results_table, results_filename);
fprintf('\nSaved per-trial CNV results to: %s\n', results_filename);

%% Local function
function trial_nums = get_trial_numbers(EEG, prefix)
% Extracts the trial number of the time-locking event (latency == 0) for each epoch
trial_nums = nan(EEG.trials, 1);
for i = 1:EEG.trials
    lat = EEG.epoch(i).eventlatency;
    typ = EEG.epoch(i).eventtype;
    if ~iscell(lat), lat = {lat}; end
    if ~iscell(typ), typ = {typ}; end
    zero_idx = find(cellfun(@(x) isnumeric(x) && abs(x) < 1, lat));
    for z = zero_idx(:)'
        num = regexp(typ{z}, ['^' prefix '(\d+)$'], 'tokens', 'once');
        if ~isempty(num)
            trial_nums(i) = str2double(num{1});
            break
        end
    end
end
end