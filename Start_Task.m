%% 1. Preparations 
sca;            % Close PTB windows
close all;      % Close MATLAB figures
clearvars;      % Clear variables
clc;            % Clear command window
totalTic = tic;

%% Set paths
loc = find_folderpath();
taskLabel = task_info();
run(fullfile(loc.script,sprintf("s01_Task_%s.m", taskLabel)));
