%% DATA VALIDATION AND COMPLETENESS CHECK SCRIPT (DETAILED STREAM EXCEL EXPORT)
% 
% DESCRIPTION:
% This script automates quality assurance and data integrity verification 
% for multi-modal experimental datasets across ALL participant folders (sub-XXXXXX)[cite: 1].
% Missing runs/folders are written DIRECTLY into each stream's respective Excel column[cite: 1].
%
% AUTHOR: Phuc T. U. Nguyen (2026)
% =========================================================================

%% 1. Select Dataset Parent Directory & Detect All Subjects
fprintf('Please select the root folder containing all sub-XXXXXX directories...\n');
parent_folder = uigetdir(pwd, 'Select Root Dataset Directory');
if isequal(parent_folder, 0)
    fprintf('Operation cancelled by user.\n');
    return;
end

% Query all directories starting with 'sub-'
dir_entries = dir(fullfile(parent_folder, 'sub-*'));
sub_dirs = dir_entries([dir_entries.isdir]);

if isempty(sub_dirs)
    error('No "sub-*" participant directories found in: %s', parent_folder);
end

fprintf('Found %d participant directory(ies) to validate.\n', length(sub_dirs));

%% 2. Define Validation Rules
streams = {'beh', 'eyetracking', 'force', 'lslglobal', 'motion', 'video'};
ses_id = 'ses-S001';

% Struct array to log high-level batch results for Excel export
summary_results = struct('Subject_ID', {}, ...
                         'Overall_Status', {}, ...
                         'BEH', {}, ...
                         'Eyetracking', {}, ...
                         'Force', {}, ...
                         'LSLGlobal', {}, ...
                         'Motion', {}, ...
                         'Video', {});

%% 3. Batch Validation Loop
for k = 1:length(sub_dirs)
    sub_id = sub_dirs(k).name;
    sub_folder = fullfile(parent_folder, sub_id);
    ses_path = fullfile(sub_folder, ses_id);
    
    sub_valid = true;
    
    % Default stream column values
    stream_results = struct('beh', '', ...
                            'eyetracking', '', ...
                            'force', '', ...
                            'lslglobal', '', ...
                            'motion', '', ...
                            'video', '');
    
    fprintf('\n==================================================\n');
    fprintf(' VALIDATING DATA (%d/%d): %s -> %s\n', k, length(sub_dirs), sub_id, ses_id);
    fprintf('==================================================\n\n');
    
    % Check if baseline session folder exists
    if ~exist(ses_path, 'dir')
        fprintf('  ❌ MISSING SESSION FOLDER: %s\n\n', ses_path);
        
        summary_results(k).Subject_ID = sub_id;
        summary_results(k).Overall_Status = 'FAILED';
        summary_results(k).BEH = 'MISSING SESSION FOLDER';
        summary_results(k).Eyetracking = 'MISSING SESSION FOLDER';
        summary_results(k).Force = 'MISSING SESSION FOLDER';
        summary_results(k).LSLGlobal = 'MISSING SESSION FOLDER';
        summary_results(k).Motion = 'MISSING SESSION FOLDER';
        summary_results(k).Video = 'MISSING SESSION FOLDER';
        continue;
    end
    
    for s = 1:length(streams)
        stream_name = streams{s};
        stream_path = fullfile(ses_path, stream_name);
        
        fprintf('Stream: [%s]\n', upper(stream_name));
        
        % Check if the modality container folder exists
        if ~exist(stream_path, 'dir')
            fprintf('  ❌ MISSING MODALITY FOLDER: %s\n\n', stream_path);
            sub_valid = false;
            stream_results.(stream_name) = 'MISSING FOLDER';
            continue;
        end
        
        % Define tasks and runs dynamically per stream
        switch stream_name
            case 'beh'
                tasks = struct('name', {'estimate', 'heightaffordance'}, 'required_runs', {1, 5});
            otherwise
                tasks = struct('name', {'heightaffordance'}, 'required_runs', {5});
        end
        
        stream_missing_details = {};
        
        % Validate each task within this stream
        for t = 1:length(tasks)
            task_name = tasks(t).name;
            req_runs = tasks(t).required_runs;
            
            task_valid = true;
            missing_runs = [];
            
            for r = 1:req_runs
                run_str = sprintf('run-%03d', r);
                bids_base = sprintf('%s_%s_task-%s_%s', sub_id, ses_id, task_name, run_str);
                
                switch stream_name
                    case 'beh'
                        % File triplet: .json, .mat, and .tsv
                        f1 = fullfile(stream_path, sprintf('%s_beh.json', bids_base));
                        f2 = fullfile(stream_path, sprintf('%s_beh.mat', bids_base));
                        f3 = fullfile(stream_path, sprintf('%s_beh.tsv', bids_base));
                        item_exists = (exist(f1, 'file') == 2) && (exist(f2, 'file') == 2) && (exist(f3, 'file') == 2);
                        
                    case 'eyetracking'
                        % Expects MP4 inside run-specific subfolder
                        eyetrack_dir = fullfile(stream_path, sprintf('%s_eyetracking', bids_base));
                        target_file  = fullfile(eyetrack_dir, 'Neon Scene Camera v1 ps1.mp4');
                        item_exists  = exist(target_file, 'file') == 2;
                        
                    case 'force'
                        % BIDS-compliant load cell data (.txt)
                        target = fullfile(stream_path, sprintf('%s_force.txt', bids_base));
                        item_exists = exist(target, 'file') == 2;
                        
                    case 'lslglobal'
                        % Synchronized lab streaming layer data (.xdf)
                        target = fullfile(stream_path, sprintf('%s_lslglobal.xdf', bids_base));
                        item_exists = exist(target, 'file') == 2;
                        
                    case 'motion'
                        % MVNX kinematic system data (.mvnx) matching bids_base prefix
                        mvnx_contents = dir(fullfile(stream_path, '*.mvnx'));
                        if ~isempty(mvnx_contents)
                            file_names = {mvnx_contents.name};
                            item_exists = any(startsWith(file_names, bids_base));
                        else
                            item_exists = false;
                        end
                        
                    case 'video'
                        % Dual-angle camera data (.avi) and metadata (.json)
                        v_side = fullfile(stream_path, sprintf('%s_acq-SideView_beh.avi', bids_base));
                        j_side = fullfile(stream_path, sprintf('%s_acq-SideView_beh.json', bids_base));
                        v_uppr = fullfile(stream_path, sprintf('%s_acq-UpperView_beh.avi', bids_base));
                        j_uppr = fullfile(stream_path, sprintf('%s_acq-UpperView_beh.json', bids_base));
                        v_grnd = fullfile(stream_path, sprintf('%s_acq-GroundView_beh.avi', bids_base));
                        j_grnd = fullfile(stream_path, sprintf('%s_acq-GroundView_beh.json', bids_base));
                        
                        item_exists = (exist(v_grnd, 'file') == 2) && (exist(j_grnd, 'file') == 2) && ...
                                      (exist(v_side, 'file') == 2) && (exist(j_side, 'file') == 2) && ...
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
                sub_valid = false;
                missing_str = num2str(missing_runs, '%03d, ');
                missing_str = missing_str(1:end-1);
                fprintf('  ❌ %-18s: INCOMPLETE! Missing run(s): [%s]\n', task_name, missing_str);
                
                if length(tasks) > 1
                    stream_missing_details{end+1} = sprintf('%s: run(s) [%s]', task_name, missing_str); %#ok<AGROW>
                else
                    stream_missing_details{end+1} = sprintf('Missing run(s): [%s]', missing_str); %#ok<AGROW>
                end
            end
        end
        
        % Write specific missing detail string directly into stream column
        if ~isempty(stream_missing_details)
            stream_results.(stream_name) = sprintf('%s', strjoin(stream_missing_details, '; '));
        end
        
        fprintf('\n');
    end
    
    % Populate structure row for Excel table output
    summary_results(k).Subject_ID = sub_id;
    if sub_valid
        summary_results(k).Overall_Status = 'SUCCESS';
    else
        summary_results(k).Overall_Status = 'FAILED';
    end
    
    summary_results(k).BEH = stream_results.beh;
    summary_results(k).Eyetracking = stream_results.eyetracking;
    summary_results(k).Force = stream_results.force;
    summary_results(k).LSLGlobal = stream_results.lslglobal;
    summary_results(k).Motion = stream_results.motion;
    summary_results(k).Video = stream_results.video;
end

%% 4. Final Batch Summary Report (Command Window)
fprintf('==================================================\n');
fprintf(' OVERALL BATCH VALIDATION SUMMARY\n');
fprintf('==================================================\n');
fprintf('%-15s | %-10s\n', 'Subject ID', 'Status');
fprintf('--------------------------------------------------\n');
total_passed = 0;
for k = 1:length(summary_results)
    fprintf('%-15s | %-10s\n', summary_results(k).Subject_ID, summary_results(k).Overall_Status);
    if strcmp(summary_results(k).Overall_Status, 'SUCCESS')
        total_passed = total_passed + 1;
    end
end
fprintf('--------------------------------------------------\n');
fprintf(' Total Processed: %d | Passed: %d | Failed: %d\n', ...
    length(summary_results), total_passed, length(summary_results) - total_passed);
fprintf('==================================================\n');

%% 5. Export Results to Excel Spreadsheet (.xlsx)
results_table = struct2table(summary_results);

% Generate timestamped filename inside the parent dataset folder
timestamp = datestr(now, 'yyyy-mm-dd_HHMMSS');
excel_filename = sprintf('completeness_data_%s.xlsx', timestamp);
excel_path = fullfile(parent_folder, excel_filename);

try
    writetable(results_table, excel_path);
    fprintf('\n📊 Batch validation report successfully exported to Excel:\n   %s\n\n', excel_path);
catch ME
    warning('Could not export Excel file: %s', ME.message);
end