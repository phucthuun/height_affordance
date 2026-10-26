function P = judo_paths(cfg, participantID, sessionID, taskName, runID, mode)
%JUDO_PATHS  Every folder and file name for one run (and optionally one ICA mode), defined in one place.
%
%   P = judo_paths(cfg, '155T4T', 'S001', 'heightaffordance', '001')
%   P = judo_paths(cfg, '155T4T', 'S001', 'heightaffordance', '001', 'auto')
%
%   Folder layout (inside cfg.study_folder):
%     2_raw-EEGLAB/sub-<id>/ses-<ses>/                      merged (imported) run
%     3_EEG-preprocessing/sub-<run>/                        preprocessed run, manual marks (step 2B)
%     4_spatial-filters/4-1_AMICA/sub-<run>_<mode>/         AMICA and dipole-fit files
%     5_single-subject-EEG-analysis/sub-<run>_<mode>/       ICA-weighted and cleaned data
%     6_single-subject-motion-analysis/sub-<run>/           motion sensor channels
%     8_quality-control/sub-<run>/                          QC JSON files, figures, HTML report
%   where <run> = <id>_ses-<ses>_task-<task>_run-<run>.

if nargin < 6
    mode = '';
end

P.participant = participantID;
P.session     = sessionID;
P.task        = taskName;
P.run         = runID;
P.mode        = mode;

P.bids_base = sprintf('%s_ses-%s_task-%s_run-%s', participantID, sessionID, taskName, runID);
P.sub_base  = [cfg.filename_prefix P.bids_base];
P.sub_entity = sprintf('sub-%s', participantID);
P.ses_entity = sprintf('ses-%s', sessionID);

% Step 1 output
P.raw_folder  = fullfile(cfg.study_folder, cfg.raw_EEGLAB_data_folder, P.sub_entity, P.ses_entity);
P.merged_file = [P.sub_base '_' cfg.merged_filename];
P.bids_folder = fullfile(cfg.study_folder, cfg.bids_target_folder, P.sub_entity, P.ses_entity);
P.bids_file   = [P.sub_base '_eeg.set'];

% Step 2A / 2B outputs
P.pre_folder        = fullfile(cfg.study_folder, cfg.EEG_preprocessing_data_folder, P.sub_base);
P.preprocessed_file = [P.sub_base '_' cfg.preprocessed_filename];
P.preprocessed_json = strrep(P.preprocessed_file, '.set', '.json');
P.marks_file        = [P.sub_base '_' cfg.rejected_segments_filename];
P.marks_json        = strrep(P.marks_file, '.mat', '.json');
P.rejected_file     = [P.sub_base '_' cfg.preprocessed_and_rejected_filename];

P.motion_folder = fullfile(cfg.study_folder, cfg.single_subject_motion_folder, P.sub_base);
P.motion_file   = [P.sub_base '_' cfg.motion_filename];

% Quality control
P.qc_folder  = fullfile(cfg.study_folder, cfg.qc_folder, P.sub_base);
P.qc_2a_json = fullfile(P.qc_folder, [P.sub_base '_qc-2a.json']);
P.qc_report  = fullfile(P.qc_folder, [P.sub_base '_qc-report.html']);

% Step 2C outputs (per mode)
if ~isempty(mode)
    P.mode_base       = [P.sub_base '_' mode];
    P.amica_folder    = fullfile(cfg.study_folder, cfg.spatial_filters_folder, cfg.spatial_filters_folder_AMICA, P.mode_base);
    P.analysis_folder = fullfile(cfg.study_folder, cfg.single_subject_analysis_folder, P.mode_base);
    P.amica_file      = [P.mode_base '_' cfg.amica_filename_output];
    P.dipfitted_file  = [P.mode_base '_' cfg.dipfitted_filename];
    P.dipfitted_json  = strrep(P.dipfitted_file, '.set', '.json');
    P.ica_file        = [P.mode_base '_' cfg.preprocessed_and_ICA_filename];
    P.qc_2c_json      = fullfile(P.qc_folder, [P.sub_base '_qc-2c_' mode '.json']);
end
end
