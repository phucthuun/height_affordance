%% Preprocessing Script for Judo Study EEG Data (BIDS-Compliant Naming)
% Based on template_bemobil_process_all_EEG_data.m
clear; clc; close all;
% addpath('C:\Users\nguyen\AppData\Roaming\MathWorks\MATLAB Add-Ons\Collections\EEGLAB\eeglab2026.0.0\plugins\Fieldtrip-lite');
% savepath;
%% Initialize EEGLAB 
if ~exist('ALLCOM','var')
	eeglab;
end

%% Load Configuration 
run('tp_judo_bemobil_config.m');
bemobil_config.channels_to_remove = {};

%% Interactive Participant/Subject Selection
prompt = { ...
    'Enter Participant ID (e.g., MH9HXJ):', ...
    'Enter Session ID (e.g., S001):', ...
    'Enter Task Name (e.g., heightaffordance):', ...
    'Enter Run ID (e.g., 001):' ...
};
dlgtitle = 'Interactive Subject Selection';
dims = [1 50];
definput = {'MH9HXJ', 'S001', 'heightaffordance', '001'};
userInput = inputdlg(prompt, dlgtitle, dims, definput);

if isempty(userInput)
    error('Processing cancelled by user.');
end

% Extract IDs exactly as entered
participantID = userInput{1};
sessionID     = userInput{2};
taskName      = userInput{3};
runID         = userInput{4};

% Build precise BIDS entity strings for filenames and directories
subEntity  = sprintf('sub-%s', participantID);
sesEntity  = sprintf('ses-%s', sessionID);
taskEntity = sprintf('task-%s', taskName);
runEntity  = sprintf('run-%s', runID);

% Combine entities to create the unique file base identifier
bids_base_string = sprintf('%s_%s_%s_%s', subEntity, sesEntity, taskEntity, runEntity);

% BIDS folder naming convention for derivatives targets sub-ID/ses-ID hierarchies
bids_folder_string = fullfile(subEntity, sesEntity);

% Set to 1 if files should be recomputed even if they already exist on disk
force_recompute = 0;

%% Prepare filepaths and check if already done
disp(['Processing Data for: ' bids_base_string]);

STUDY = []; CURRENTSTUDY = 0; ALLEEG = []; CURRENTSET=[]; EEG=[]; EEG_interp_avref = []; EEG_single_subject_final = [];

% Reconstruct BIDS subfolder hierarchies
input_filepath = fullfile(bemobil_config.study_folder, bemobil_config.raw_EEGLAB_data_folder, subEntity, sesEntity, 'eeg');
output_filepath = fullfile(bemobil_config.study_folder, bemobil_config.single_subject_analysis_folder, subEntity, sesEntity, 'eeg');

try
    % Build exact filename matching clean ICA set
    cleaned_filename = sprintf('%s_%s', bids_base_string, bemobil_config.single_subject_cleaned_ICA_filename);
    EEG_single_subject_final = pop_loadset('filename', cleaned_filename, 'filepath', output_filepath);
catch
    disp('...failed or file does not exist. Computing now.')
end

if ~force_recompute && exist('EEG_single_subject_final','var') && ~isempty(EEG_single_subject_final)
    clear EEG_single_subject_final
    disp('Subject is completely preprocessed already.')
else
    %% Load data in EEGLAB .set structure
    try 
        pop_editoptions('option_saveversion6', 0, 'option_single', 0, 'option_memmapdata', 0, 'option_savetwofiles', 1, 'option_storedisk', 0);
    catch
        warning('Could NOT edit EEGLAB memory options!!'); 
    end
    
    % Targets precise filename structure (e.g., sub-MH9HXJ_ses-S001_task-heightaffordance_run-001_merged_EEG.set)
    target_merged_filename = sprintf('%s_%s', bids_base_string, bemobil_config.merged_filename);
    EEG = pop_loadset('filename', target_merged_filename, 'filepath', input_filepath);
    
    %% Individual EEG processing to remove non-experiment segments
    allevents = {EEG.event.type}';
    earliest_onset_latency = inf;
    latest_offset_latency = -inf;
    
    for idx = 1:length(allevents)
        evt_type = allevents{idx};
        if startsWith(evt_type, 'TrialOnset')
            digit_part = regexp(evt_type, '\d+', 'match');
            if ~isempty(digit_part)
                earliest_onset_latency = min(earliest_onset_latency, EEG.event(idx).latency);
            end
        end
        if startsWith(evt_type, 'TrialOffset')
            digit_part = regexp(evt_type, '\d+', 'match');
            if ~isempty(digit_part)
                latest_offset_latency = max(latest_offset_latency, EEG.event(idx).latency);
            end
        end
    end
    
    if isinf(earliest_onset_latency) || latest_offset_latency == -inf
        warning('Could not locate specific TrialOnset/Offset markers. Defaulting to first and last markers.');
        earliest_onset_latency = EEG.event(1).latency;
        latest_offset_latency = EEG.event(end).latency;
    end
    
    removeindices = [0, max(1, earliest_onset_latency - EEG.srate)];
    removeindices(end+1, :) = [min(EEG.pnts, latest_offset_latency + EEG.srate), EEG.pnts];
    
    EEG_plot = pop_eegfiltnew(EEG, 'locutoff', 0.5, 'plotfreqz', 0);
    
    fig1 = figure; set(gcf, 'Color', 'w', 'InvertHardCopy', 'off', 'units', 'normalized', 'outerposition', [0 0 1 1])
    plot(normalize(EEG_plot.data') + [1:10:10*EEG_plot.nbchan], 'color', [78 165 216]/255)
    yticks([])
    xlim([0 EEG.pnts])
    ylim([-10 10*EEG_plot.nbchan+10])
    hold on
    
    for i = 1:size(removeindices,1)
        plot([removeindices(i,1) removeindices(i,1)], ylim, 'r', 'LineWidth', 1.5)
        plot([removeindices(i,2) removeindices(i,2)], ylim, 'g', 'LineWidth', 1.5)
    end
    
    print(gcf, fullfile(input_filepath, [bids_base_string '_raw-full_EEG.png']), '-dpng')
    close

    EEG = eeg_eegrej(EEG, removeindices);   
    
    %% BIDS COMPLIANCE ADJUSTMENTS HERE:
    % Instead of passing 'participantID' (e.g. 'MH9HXJ'), we pass 'bids_base_string'.
    % This forces the pipeline to name intermediate sets and plots using the full chain:
    % sub-MH9HXJ_ses-S001_task-heightaffordance_run-001_*
	
    % 1. Process baseline cleanups, filtering, and interpolation wrapper
	[ALLEEG, EEG_preprocessed, CURRENTSET] = bemobil_process_all_EEG_preprocessing(bids_base_string, bemobil_config, ALLEEG, EEG, CURRENTSET, force_recompute);

    % 2. Run spatial decomposition pipeline via AMICA
    % % Force-install/load FieldTrip-lite silently without a GUI prompt
    % plugin_askinstall('Fieldtrip-lite', 'ft_defaults', true);
	bemobil_process_all_AMICA(ALLEEG, EEG_preprocessed, CURRENTSET, bids_base_string, bemobil_config, force_recompute);
end

%% Finalization plots
try
    bemobil_copy_plots_in_one(bemobil_config);
catch
    disp('Could not gather pipeline overview plots automatically.');
end

disp(' ');
disp('=====================================================');
disp('      PROCESSING DONE FOR CURRENT BIDS PATH          ');
disp('=====================================================');