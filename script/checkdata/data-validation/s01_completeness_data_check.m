%% DATA VALIDATION AND COMPLETENESS CHECK SCRIPT
% 
% DESCRIPTION:
% This script automates quality assurance and data integrity verification 
% for multi-modal experimental datasets. It systematically reviews selected 
% participant directories to confirm all raw and derivative file streams have 
% been successfully recorded, structured, and named according to Brain Imaging 
% Data Structure (BIDS) formatting standards.
%
% WHAT THIS SCRIPT DOES:
% 1. Folder & Session Isolation: Prompts the user to interactively select a 
%    valid subject directory (must utilize the 'sub-XXX' prefix) and targets 
%    the baseline session path ('ses-S001').
% 2. Multi-Stream Targeting: Evaluates 6 distinct raw data and telemetry streams: 
%    Behavioral (beh), Eyetracking, Force, LSL Global, Motion (MoCap), and Video.
% 3. Dynamic Task & Run Cross-Referencing: Verifies directory completeness 
%    against empirical protocol requirements across experimental phases:
%       - Behavioral ('beh'): Checks for both 'estimate' (1 run) and 
%         'heightaffordance' (4 runs) paradigms.
%       - Hardware Streams: Validates the 4 required runs strictly for the 
%         'heightaffordance' task.
% 4. Modality-Specific File Verification: Deep-inspects folders to guarantee 
%    exact naming structures, sidecar formats, and multi-file pairings:
%       - Behavioral: Confirms file triplets (.json, .mat, .tsv) per run.
%       - Eyetracking: Verifies target eye-tracking telemetry subfolders exist.
%       - Force: Validates BIDS-compliant load cell data (.txt).
%       - LSL Global: Looks for synchronized lab streaming layer data (.xdf).
%       - Motion: Validates specialized MVNX kinematic system data (.mvnx).
%       - Video: Ensures dual-angle camera data (.avi) paired alongside their 
%         corresponding BIDS metadata sidecars (.json) for Upper and Side views.
% 5. Automated Reporting: Outputs a scannable status report directly to the 
%    MATLAB Command Window, flagging missing runs, missing modality folders, 
%    and concluding with a binary global verdict (SUCCESS or FAILED).
%
% AUTHOR: Phuc T. U. Nguyen (2026)
% =========================================================================


%% 1. Get the Subject Folder Path
fprintf('Please select the sub-XXX folder...\n');
sub_folder = uigetdir(pwd, 'Select the sub-XXX Folder');
if isequal(sub_folder, 0)
    fprintf('Operation cancelled by user.\n');
    return;
end

% Extract the subject ID (e.g., "sub-C4TA1N") from the folder name
[~, sub_id, ~] = fileparts(sub_folder);
if ~startsWith(sub_id, 'sub-')
    error('Invalid folder selection. The folder name must start with "sub-".');
end

ses_id = 'ses-S001';
ses_path = fullfile(sub_folder, ses_id);
if ~exist(ses_path, 'dir')
    error('The session folder "%s" does not exist inside %s.', ses_id, sub_folder);
end

%% 2. Define Validation Rules
% Updated modalities based on new directory structure
streams = {'beh', 'eyetracking', 'force', 'lslglobal', 'motion', 'video'};

%% 3. Perform Validation
all_valid = true;
fprintf('\n==================================================\n');
fprintf(' VALIDATING DATA FOR: %s -> %s\n', sub_id, ses_id);
fprintf('==================================================\n\n');

for s = 1:length(streams)
    stream_name = streams{s};
    stream_path = fullfile(ses_path, stream_name);
    
    fprintf('Stream: [%s]\n', upper(stream_name));
    
    % Check if the modality container folder exists
    if ~exist(stream_path, 'dir')
        fprintf('  ❌ MISSING MODALITY FOLDER: %s\n\n', stream_path);
        all_valid = false;
        continue;
    end
    
    % Define tasks and runs dynamically per stream based on your architecture
    switch stream_name
        case 'beh'
            tasks = struct('name', {'estimate', 'heightaffordance'}, 'required_runs', {1, 4});
        otherwise
            % eyetracking, force, lslglobal, motion, video only have heightaffordance task
            tasks = struct('name', {'heightaffordance'}, 'required_runs', {4});
    end
    
    % Validate each task within this stream
    for t = 1:length(tasks)
        task_name = tasks(t).name;
        req_runs = tasks(t).required_runs;
        
        task_valid = true;
        missing_runs = [];
        
        % Loop through each required run to verify its exact essential file/folder
        for r = 1:req_runs
            run_str = sprintf('run-%03d', r);
            bids_base = sprintf('%s_%s_task-%s_%s', sub_id, ses_id, task_name, run_str);
            
            switch stream_name
                case 'beh'
                    % Expects a triplet of files: .json, .mat, and .tsv
                    f1 = fullfile(stream_path, sprintf('%s_beh.json', bids_base));
                    f2 = fullfile(stream_path, sprintf('%s_beh.mat', bids_base));
                    f3 = fullfile(stream_path, sprintf('%s_beh.tsv', bids_base));
                    item_exists = (exist(f1, 'file') == 2) && (exist(f2, 'file') == 2) && (exist(f3, 'file') == 2);
                    
                case 'eyetracking'
                    % Eyetracking expects a specific subfolder containing recording telemetry
                    target = fullfile(stream_path, sprintf('%s_eyetracking', bids_base));
                    item_exists = exist(target, 'dir') == 7;
                    
                case 'force'
                    % Force expects a BIDS-compliant .txt file
                    target = fullfile(stream_path, sprintf('%s_force.txt', bids_base));
                    item_exists = exist(target, 'file') == 2;
                    
                case 'lslglobal'
                    % LSL Global expects an ecosystem .xdf file
                    target = fullfile(stream_path, sprintf('%s_lslglobal.xdf', bids_base));
                    item_exists = exist(target, 'file') == 2;
                    
                case 'motion'
                    % Updated to match the new MVNX nomenclature rule
                    % target = fullfile(stream_path, sprintf('%s.mvnx', bids_base));
                    % item_exists = exist(target, 'file') == 2;

                    % Read all files ending in .mvnx within the motion directory
                    mvnx_contents = dir(fullfile(stream_path, '*.mvnx'));
                    
                    % Check if any file matches the starting base name criteria
                    if ~isempty(mvnx_contents)
                        file_names = {mvnx_contents.name};
                        % Look for files starting with the prefix: e.g., sub-C4TA1N_ses-S001_task-heightaffordance_run-004
                        item_exists = any(startsWith(file_names, bids_base));
                    else
                        item_exists = false;
                    end

                    
                case 'video'
                    % Video expects BOTH Upper and Side views, as well as their sidecar .json files
                    v_side = fullfile(stream_path, sprintf('%s_acq-SideView_beh.avi', bids_base));
                    j_side = fullfile(stream_path, sprintf('%s_acq-SideView_beh.json', bids_base));
                    v_uppr = fullfile(stream_path, sprintf('%s_acq-UpperView_beh.avi', bids_base));
                    j_uppr = fullfile(stream_path, sprintf('%s_acq-UpperView_beh.json', bids_base));
                    
                    item_exists = (exist(v_side, 'file') == 2) && (exist(j_side, 'file') == 2) && ...
                                  (exist(v_uppr, 'file') == 2) && (exist(j_uppr, 'file') == 2);
            end
            
            if ~item_exists
                task_valid = false;
                missing_runs = [missing_runs, r]; %#ok<AGROW>
            end
        end
        
        % Print evaluation results for the specific task
        if task_valid
            fprintf('  ✅ %-18s: Complete! All %d runs verified.\n', task_name, req_runs);
        else
            all_valid = false;
            missing_str = num2str(missing_runs, '%03d, ');
            missing_str = missing_str(1:end-1); % Clean trailing comma
            fprintf('  ❌ %-18s: INCOMPLETE! Missing run(s): [%s]\n', task_name, missing_str);
        end
    end
    fprintf('\n');
end

%% 4. Final Verdict
fprintf('==================================================\n');
if all_valid
    fprintf(' STATUS: SUCCESS! All essential data streams are complete.\n');
else
    fprintf(' STATUS: FAILED! Missing data detected. Review logs above.\n');
end
fprintf('==================================================\n');