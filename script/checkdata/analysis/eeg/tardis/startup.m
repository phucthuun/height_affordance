% startup.m - Automatic HPC Environment Config

eeglab_path = '/mnt/beegfs/home/nguyen/matlab/toolbox/EEGLAB/eeglab2026.0.0';

if exist(eeglab_path, 'dir')
    addpath(eeglab_path);
    if isunix
        opengl('save', 'software');
        set(0, 'DefaultFigureVisible', 'off');
    end
    % Boot EEGLAB to auto-load BeMoBIL plugin
    [ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab;
    fprintf('=== Environment Loaded Successfully via startup.m ===\n');
end