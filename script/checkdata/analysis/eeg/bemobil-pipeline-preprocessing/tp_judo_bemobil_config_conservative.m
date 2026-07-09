%% tp_judo_bemobil_config_conservative.m
% Configuration script for the Judo Study EEG Data Processing Pipeline
clear bemobil_config;

%% General Setup
% Upper data repository directory mapping
bemobil_config.upper_folder = 'C:\Data\Research\10_Data';
bemobil_config.raw_data_folder = fullfile(bemobil_config.upper_folder, 'sourcedata');
bemobil_config.study_folder = fullfile(bemobil_config.upper_folder, 'derivatives', 'EEG_bemobil_pipeline');
bemobil_config.filename_prefix = 'sub-';

% BIDS derivatives structural folders (must end with a filesep!)
bemobil_config.bids_target_folder             = ['1_BIDS-data' filesep];
bemobil_config.raw_EEGLAB_data_folder         = ['2_raw-EEGLAB' filesep];
bemobil_config.EEG_preprocessing_data_folder  = ['3_EEG-preprocessing' filesep];
bemobil_config.spatial_filters_folder         = ['4_spatial-filters' filesep];
bemobil_config.spatial_filters_folder_AMICA   = ['4-1_AMICA' filesep];
bemobil_config.single_subject_analysis_folder = ['5_single-subject-EEG-analysis' filesep];
bemobil_config.single_subject_motion_folder   = ['6_single-subject-motion-analysis' filesep];
bemobil_config.single_subject_eye_folder      = ['7_single-subject-EYE-analysis' filesep];

% Standard pipeline filenames
bemobil_config.merged_filename                     = 'merged_EEG.set';
bemobil_config.basic_prepared_filename             = 'basic_prepared.set';
bemobil_config.preprocessed_filename               = 'preprocessed.set';
bemobil_config.filtered_filename                   = 'filtered.set';
bemobil_config.amica_filename_output               = 'AMICA.set';
bemobil_config.dipfitted_filename                  = 'dipfitted.set';
bemobil_config.preprocessed_and_ICA_filename       = 'preprocessed_and_ICA.set';
bemobil_config.single_subject_cleaned_ICA_filename = 'cleaned_with_ICA.set';

%% Preprocessing Settings
% Remove non-EEG auxiliary sensor streams
bemobil_config.channels_to_remove = {'AccX','AccY','AccZ','GyroX','GyroY','GyroZ'};

% EOG channel definition
bemobil_config.eog_channels = {};

% Reference channel layout target
bemobil_config.ref_channel = 'FCz';

% Global channel prefix renamer matrix layout 
bemobil_config.rename_channels = {};

% Resample frequency target (Keep empty if keeping native source srate)
bemobil_config.resample_freq = [];

% Automatic clean_rawdata channel criteria
bemobil_config.chancorr_crit = 0.70;
bemobil_config.chan_max_broken_time = 0.5;
bemobil_config.chan_detect_num_iter = 10;
bemobil_config.chan_detected_fraction_threshold = 0.5;
bemobil_config.flatline_crit = 'off';
bemobil_config.line_noise_crit = 'off';
bemobil_config.num_chan_rej_max_target = 1/5;

% Custom channel locations coordinate map (Empty defaults to standard 10-5)
bemobil_config.channel_locations_filename = [];

% ZapLine-Plus targeted frequencies 
bemobil_config.zaplineConfig.noisefreqs = [50];

%% AMICA Mathematical Parameters
% High-pass filtering for stable AMICA spatial decomposition (Klug & Gramann, 2021)
bemobil_config.filter_lowCutoffFreqAMICA = 1.75;
bemobil_config.filter_AMICA_highPassOrder = 1650;
bemobil_config.filter_highCutoffFreqAMICA = [];
bemobil_config.filter_AMICA_lowPassOrder = [];

% Core AMICA algorithm constraints
bemobil_config.num_models = 1;
bemobil_config.AMICA_autoreject = 1;
bemobil_config.AMICA_n_rej = 10;
bemobil_config.AMICA_reject_sigma_threshold = 3;
bemobil_config.AMICA_max_iter = 2000;
bemobil_config.max_threads = 4;

% Warping channel parameters for non-standard caps
bemobil_config.warping_channel_names = [];

% Dipfit source modeling constraints
bemobil_config.residualVariance_threshold = 100;
bemobil_config.do_remove_outside_head = 'off';
bemobil_config.number_of_dipoles = 1;

% ICLabel classification setup ('lite' outperforms default for muscle classification)
bemobil_config.iclabel_classifier = 'lite';
bemobil_config.iclabel_classes = [1 2 4 5 6 7]; % Removes eye components from standard track
bemobil_config.iclabel_threshold = -1;          % Uses strict majority profile classifier

%% Continuous Finalization Filters (Post-ICA)
bemobil_config.final_filter_lower_edge = 0.2;
bemobil_config.final_filter_higher_edge = [];

%% Motion Processing Parameters
bemobil_config.lowpass_motion = 8;
bemobil_config.lowpass_motion_after_derivative = 24;

%% Global EEGLAB Environment Memory Settings Override
try 
    pop_editoptions('option_saveversion6', 0, 'option_single', 0, ...
                    'option_memmapdata', 0, 'option_savetwofiles', 1, 'option_storedisk', 0);
catch
    warning('Could NOT automatically optimize EEGLAB memory and file options.');
end