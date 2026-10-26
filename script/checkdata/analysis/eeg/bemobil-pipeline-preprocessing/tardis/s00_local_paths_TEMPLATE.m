%% s00_local_paths_TEMPLATE.m -- local path overrides (for step 2B on your own PC)
%
% Copy this file to s00_local_paths.m in the same folder and edit the two paths.
% s00_judo_bemobil_config.m picks it up automatically, except inside SLURM jobs on tardis.
% s00_local_paths.m is listed in .gitignore so it never ends up on the cluster by accident.
%
% project_root is the folder that contains 10_Data (copy the run folders you inspect into
% 10_Data/derivatives/EEG_bemobil_pipeline/3_EEG-preprocessing/ with the same names as on tardis).

bemobil_config.project_root = 'D:\judo\1223-xplo-judo';
bemobil_config.eeglab_root  = 'C:\toolbox\eeglab2026.0.0';
