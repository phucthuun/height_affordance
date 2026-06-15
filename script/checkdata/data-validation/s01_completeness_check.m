%% DATA VALIDATION AND COMPLETENESS CHECK SCRIPT
% 
% DESCRIPTION:
% This script checks data integrity and completeness 
% It verifies that raw data has been successfully recorded, structured, and 
% named according to BIDS (Brain Imaging Data Structure) formatting principles.
%
% WHAT THIS SCRIPT DOES:
% 1. Folder & Session Selection: Prompts the user to select a subject folder 
%    (must start with 'sub-') and targets a specific session folder ('ses-S001').
% 2. Multi-Stream Targeting: Evaluates 5 distinct data streams: Eyetracking, 
%    Force, MoCap, LSL Global, and Video (Note: EEG is intentionally saved within LSL Global).
% 3. Task & Run Compliance Check: Cross-references the directory against
%    the experiment protocol across three tasks (Training, Height Affordance, 
%    and Estimate), checking for the exact number of required runs (1, 4, or 1).
% 4. Modality-Specific File Verification: Inspects files to ensure the correct 
%    naming conventions and file formats exist:
%       - Eyetracking: Validates target subfolders.
%       - Force: Looks for BIDS-compliant .txt files.
%       - MoCap: Looks for .mvn files.
%       - LSL Global: Looks for .xdf files.
%       - Video: Ensures dual-angle camera data (.avi) exists for both Upper and Side views.
% 5. Reporting: Outputs a clear command window report flagging missing modalities 
%    or specific missing runs, concluding with a final global SUCCESS/FAILED status.
%
% AUTHOR: Phuc T. U. Nguyen
% =========================================================================

%% 1. Get the Subject Folder Path
fprintf('Please select the sub-XXX folder...\n');
sub_folder = uigetdir(pwd, 'Select the sub-XXX Folder');

if isequal(sub_folder, 0)
    fprintf('Operation cancelled by user.\n');
    return;
end

% Extract the subject ID (e.g., "sub-PHUC1") from the folder name
[~, sub_id, ~] = fileparts(sub_folder);
if ~startsWith(sub_id, 'sub-')
    error('Invalid folder selection. The folder name must start with "sub-".');
end

% Prompt for Session ID (defaulting to ses-S001 based on your example)
% ses_id = input('Enter Session ID [ses-S001]: ', 's');
% if isempty(ses_id), ses_id = 'ses-S001'; end
ses_id = 'ses-S001';

ses_path = fullfile(sub_folder, 'ses-S001');
if ~exist(ses_path, 'dir')
    error('The session folder "%s" does not exist inside %s.', ses_id, sub_folder);
end

%% 2. Define Validation Rules
% Modalities to check (EEG is excluded)
streams = {'eyetracking', 'force', 'mocap', 'lslglobal', 'video'};

% Define tasks and their expected run counts
tasks = struct(...
    'name', {'training', 'heightaffordance', 'estimate'}, ...
    'required_runs', {1, 4, 1} ...
);

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
    
    % Validate each task within this stream
    for t = 1:length(tasks)
        task_name = tasks(t).name;
        req_runs = tasks(t).required_runs;
        
        % Rules for tasks skipped in eyetracking & force
        if (strcmp(stream_name, 'eyetracking') || strcmp(stream_name, 'force')) && strcmp(task_name, 'estimate')
            %fprintf('  ➖ %-18s: Skipped (Not required for this stream)\n', task_name);
            continue;
        end
        
        task_valid = true;
        missing_runs = [];
        
        % Loop through each required run to verify its exact essential file/folder
        for r = 1:req_runs
            run_str = sprintf('run-%03d', r);
            bids_base = sprintf('%s_%s_task-%s_%s', sub_id, ses_id, task_name, run_str);
            
            switch stream_name
                case 'eyetracking'
                    % Eyetracking expects a specific subfolder name
                    target = fullfile(stream_path, sprintf('%s_eyetracking', bids_base));
                    item_exists = exist(target, 'dir') == 7;
                    
                case 'force'
                    % Force expects a .txt file
                    target = fullfile(stream_path, sprintf('%s_force.txt', bids_base));
                    item_exists = exist(target, 'file') == 2;
                    
                case 'mocap'
                    % Mocap expects a .mvn file
                    target = fullfile(stream_path, sprintf('%s_mocap.mvn', bids_base));
                    item_exists = exist(target, 'file') == 2;
                    
                case 'lslglobal'
                    % LSL Global expects an .xdf file
                    target = fullfile(stream_path, sprintf('%s_lslglobal.xdf', bids_base));
                    item_exists = exist(target, 'file') == 2;
                    
                case 'video'
                    % Video expects BOTH Upper and Side angles (.avi)
                    upper_video = fullfile(stream_path, sprintf('%s_acq-UpperView_beh.avi', bids_base));
                    side_video = fullfile(stream_path, sprintf('%s_acq-SideView_beh.avi', bids_base));
                    
                    item_exists = (exist(upper_video, 'file') == 2) && (exist(side_video, 'file') == 2);
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
