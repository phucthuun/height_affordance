% startup.m - Automatic HPC Environment Config
eeglab_path = '/mnt/beegfs/home/nguyen/matlab/toolbox/EEGLAB/eeglab2026.0.0';

if exist(eeglab_path, 'dir')
    addpath(eeglab_path);
    if isunix
        opengl('save', 'software');
        set(0, 'DefaultFigureVisible', 'off');
	set(0, 'DefaultFigurePaperPositionMode', 'auto');   
    end
    % Boot EEGLAB HEADLESSLY (No GUI windows)
    [ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab;
    fprintf('=== Environment Loaded Successfully via startup.m ===\n');
end

if ~usejava('desktop') || ~usejava('swing')
    evalin('base', 'warndlg = @(msg, title, varargin) fprintf("\n[HPC WARN - %s]: %s\n\n", char(title), char(msg));');
end

if ~usejava('desktop') || ~usejava('swing')
    warndlg = @(msg, title, varargin) fprintf('\n[WARNING - %s]: %s\n\n', ...
        char(title), char(msg));
end