%% s00_judo_bemobil_config.m -- settings for every step of the judo EEG pipeline
%
% This file only defines settings. It is loaded by utils/judo_setup.m, which also starts EEGLAB and
% applies the EEGLAB memory options. Do not run it on its own.
%
% Paths are resolved in this order:
%   1. the tardis defaults below
%   2. the environment variables JUDO_PROJECT_ROOT and JUDO_EEGLAB_ROOT, if set
%   3. s00_local_paths.m in this folder, if it exists and MATLAB is NOT running inside a SLURM job
%      (copy s00_local_paths_TEMPLATE.m to s00_local_paths.m on your local PC for step 2B)

clear bemobil_config

%% Pipeline identity (written into every output, QC file and the methods text)
bemobil_config.pipeline_name    = 'judo-eeg-bemobil';
bemobil_config.pipeline_version = '2.0.0';

%% Paths
bemobil_config.project_root = fullfile('/mnt/beegfs/home', getenv('USER'), '1223-xplo-judo');
bemobil_config.eeglab_root  = '/mnt/beegfs/home/nguyen/matlab/toolbox/EEGLAB/eeglab2026.0.0';

if ~isempty(getenv('JUDO_PROJECT_ROOT'))
    bemobil_config.project_root = getenv('JUDO_PROJECT_ROOT');
end
if ~isempty(getenv('JUDO_EEGLAB_ROOT'))
    bemobil_config.eeglab_root = getenv('JUDO_EEGLAB_ROOT');
end
if isempty(getenv('SLURM_JOB_ID')) && exist('s00_local_paths', 'file') == 2
    s00_local_paths; % local overrides, e.g. on your PC for step 2B
end

bemobil_config.upper_folder    = fullfile(bemobil_config.project_root, '10_Data');
bemobil_config.raw_data_folder = fullfile(bemobil_config.upper_folder, 'sourcedata');
bemobil_config.study_folder    = fullfile(bemobil_config.upper_folder, 'derivatives', 'EEG_bemobil_pipeline');
bemobil_config.filename_prefix = 'sub-';

bemobil_config.source_data_folder             = ['0_source-data' filesep]; % not used, keeps bemobil quiet
bemobil_config.bids_target_folder             = ['1_BIDS-data' filesep];
bemobil_config.bids_data_folder               = bemobil_config.bids_target_folder;
bemobil_config.raw_EEGLAB_data_folder         = ['2_raw-EEGLAB' filesep];
bemobil_config.EEG_preprocessing_data_folder  = ['3_EEG-preprocessing' filesep];
bemobil_config.spatial_filters_folder         = ['4_spatial-filters' filesep];
bemobil_config.spatial_filters_folder_AMICA   = ['4-1_AMICA' filesep];
bemobil_config.single_subject_analysis_folder = ['5_single-subject-EEG-analysis' filesep];
bemobil_config.single_subject_motion_folder   = ['6_single-subject-motion-analysis' filesep];
bemobil_config.motion_analysis_folder         = bemobil_config.single_subject_motion_folder;
bemobil_config.single_subject_eye_folder      = ['7_single-subject-EYE-analysis' filesep];
bemobil_config.qc_folder                      = ['8_quality-control' filesep];

%% File names
bemobil_config.merged_filename                     = 'merged_EEG.set';
bemobil_config.basic_prepared_filename             = 'basic_prepared.set';
bemobil_config.preprocessed_filename               = 'preprocessed.set';
bemobil_config.filtered_filename                   = 'filtered.set';
bemobil_config.amica_filename_output               = 'AMICA.set';
bemobil_config.dipfitted_filename                  = 'dipfitted.set';
bemobil_config.preprocessed_and_ICA_filename       = 'preprocessed_and_ICA.set';
bemobil_config.preprocessed_and_rejected_filename  = 'preprocessed_and_rejected.set';
bemobil_config.rejected_segments_filename          = 'rejected_segments.mat';
bemobil_config.single_subject_cleaned_ICA_filename = 'cleaned_with_ICA.set'; % not written any more, kept for bemobil
bemobil_config.motion_filename                     = 'motion.set';
bemobil_config.merged_motion_filename              = 'merged_MOTION.set';
bemobil_config.processed_motion_filename           = 'motion_processed.set';

%% Step 1: import
bemobil_config.xdf_eeg_stream_name = 'EEG';
bemobil_config.save_bids_copy      = true;  % also write the dataset + sidecars to 1_BIDS-data (not a validated BIDS dataset)
bemobil_config.power_line_hz       = 50;

%% Step 2A: trimming and preprocessing

% Trimming: keep the data from trim_padding_s before the first trial onset to trim_padding_s after the last
% trial offset. With 1 s, the first and last epochs see a little of the 0.1 Hz filter's edge response
% (about 0.5 uV RMS in simulations, negligible in averages over many trials).
bemobil_config.trim_padding_s     = 1;
bemobil_config.trial_onset_regex  = '^TrialOnset\d+';
bemobil_config.trial_offset_regex = '^TrialOffset\d+';

% Motion sensor channels inside the EEG stream. They are saved separately (6_single-subject-motion-analysis)
% and removed from the EEG before preprocessing. Only the ones present in a recording are used.
bemobil_config.motion_channel_labels = {'AccX','AccY','AccZ','GyroX','GyroY','GyroZ','QuatW','QuatX','QuatY','QuatZ'};
bemobil_config.channels_to_remove    = {}; % filled per run with the motion channels that are present

% Bad-channel detection uses random channel subsets (RANSAC). clean_rawdata >= 2.7 resets MATLAB's random
% generator itself, so its result is already reproducible; the fixed seed also covers older versions.
bemobil_config.random_seed = 20261026;

bemobil_config.eog_channels    = {};
bemobil_config.ref_channel     = 'FCz';  % recording reference, added back as a channel before re-referencing
bemobil_config.rename_channels = {};
bemobil_config.resample_freq   = [];     % [] keeps the original sampling rate

% Automatic bad-channel detection (see bemobil_detect_bad_channels)
bemobil_config.chancorr_crit                    = 0.80;
bemobil_config.chan_max_broken_time             = 0.3;
bemobil_config.chan_detect_num_iter             = 10;
bemobil_config.chan_detected_fraction_threshold = 0.5;
bemobil_config.flatline_crit                    = 'off';
bemobil_config.line_noise_crit                  = 'off';
bemobil_config.num_chan_rej_max_target          = 1/5;

bemobil_config.channel_locations_filename = []; % [] = standard 10-5 template locations
bemobil_config.zaplineConfig.noisefreqs   = 50; % ZapLine-Plus line-noise removal

%% Step 2B: manual segment rejection (local PC)
bemobil_config.manual_rejection_protocol       = 'v1';  % version of the written rejection criteria (README)
bemobil_config.manual_rejection_blind          = true;  % hide condition labels while inspecting
bemobil_config.manual_rejection_window_s       = 20;
bemobil_config.manual_rejection_view_highpass  = 1;     % Hz, display only; [] shows the data unfiltered
bemobil_config.manual_rejection_save_set       = true;  % also save preprocessed_and_rejected.set for inspection

%% Step 2C: AMICA, dipole fitting, ICLabel cleaning

% 'auto'       = AMICA trained on the full preprocessed run, AMICA's own sample rejection only
% 'manualauto' = AMICA trained after removing the segments marked in step 2B, plus AMICA's sample rejection
% In both modes the weights are applied to the full, unfiltered preprocessed run.
bemobil_config.amica_modes = {'auto', 'manualauto'};

% High-pass filter of the copy used to train AMICA (Klug & Gramann 2021: up to 2 Hz for mobile data).
% The filter order is computed from the transition bandwidth and the sampling rate, so the -6 dB cutoff
% is 1.75 - 0.5/2 = 1.5 Hz at any sampling rate. Set filter_AMICA_highPassOrder to a number to force an order.
bemobil_config.filter_lowCutoffFreqAMICA          = 1.75; % passband edge (Hz)
bemobil_config.filter_AMICA_transition_bandwidth  = 0.5;  % Hz
bemobil_config.filter_AMICA_highPassOrder         = [];
bemobil_config.filter_highCutoffFreqAMICA         = [];
bemobil_config.filter_AMICA_lowPassOrder          = [];

bemobil_config.num_models                   = 1;
bemobil_config.AMICA_autoreject             = 1;
bemobil_config.AMICA_n_rej                  = 10;
bemobil_config.AMICA_reject_sigma_threshold = 3;
bemobil_config.AMICA_max_iter               = 2000;
bemobil_config.max_threads                  = 4;  % match --cpus-per-task in run_step2c.sh

bemobil_config.warping_channel_names      = [];
bemobil_config.residualVariance_threshold = 100;
bemobil_config.do_remove_outside_head     = 'off';
bemobil_config.number_of_dipoles          = 1;

% ICLabel classes: 1 Brain, 2 Muscle, 3 Eye, 4 Heart, 5 Line Noise, 6 Channel Noise, 7 Other
bemobil_config.iclabel_classifier = 'lite';
bemobil_config.iclabel_threshold  = -1;  % -1 = popularity: each IC gets its most probable class
bemobil_config.ic_cleaning_levels = struct( ...
    'name',            {'rmEye',                   'rmEyeMuscle'}, ...
    'label',           {'Eye components removed', 'Eye and muscle components removed'}, ...
    'classes_to_keep', {[1 2 4 5 6 7],            [1 4 5 6 7]});
bemobil_config.iclabel_classes = [1 4 5 6 7]; % only read by bemobil wrapper functions this pipeline no longer calls

% Final high-pass of the cleaned data (passband edge). EEGLAB's default transition band gives a -6 dB cutoff
% of 0.05 Hz and a filter about 33 s long.
bemobil_config.final_filter_lower_edge  = 0.1;
bemobil_config.final_filter_higher_edge = [];   % no low-pass in the saved data; filter per analysis later

%% Conditions: per-condition trial counts and the quick average response in the QC report
bemobil_config.condition_names       = {'NPose', 'Neutral', 'Fight'};
bemobil_config.condition_event_regex = ['^(' strjoin(bemobil_config.condition_names, '|') ')\d*$'];
bemobil_config.erp_window_s          = [-0.2 0.8];
bemobil_config.erp_baseline_s        = [-0.2 0];
bemobil_config.erp_channels          = {'Cz', 'FCz', 'Pz', 'Fz'}; % the first one present is plotted

%% Quality-control warnings (only flag runs for review; nothing is removed automatically)
bemobil_config.qc.max_interpolated_fraction      = 0.15;
bemobil_config.qc.max_amica_rejected_percent     = 25;
bemobil_config.qc.max_manual_rejected_percent    = 30;
bemobil_config.qc.min_samples_per_channel_sq     = 30;   % rule of thumb for AMICA data amount
bemobil_config.qc.min_brain_ics                  = 5;
bemobil_config.qc.min_trials_per_condition       = 20;
bemobil_config.qc.motion_corr_threshold          = 0.3;  % |r| between an IC and a motion channel
bemobil_config.qc.motion_envelope_corr_threshold = 0.5;  % r between IC and head-acceleration envelopes
bemobil_config.qc.motion_band_hz                 = [1 20];
bemobil_config.qc.max_topoplots                  = 35;
bemobil_config.qc.figure_dpi                     = 110;

%% Motion processing parameters (bemobil defaults, not used by this pipeline yet)
bemobil_config.lowpass_motion                  = 8;
bemobil_config.lowpass_motion_after_derivative = 24;
