%% CONSOLE FOLDER TREE GENERATOR (MAX 5 LEVELS)
% This script prompts the user to select a folder and prints out the 
% directory tree directly to the MATLAB console up to 5 levels deep.

clear; clc;

%% 1. Prompt User for Folder
fprintf('Please select the root folder to display...\n');
root_folder = uigetdir(pwd, 'Select Root Folder for Console Print');

if isequal(root_folder, 0)
    fprintf('Operation cancelled by user.\n');
    return;
end

%% 2. Print Header and Start Tree Traversal
[~, root_name, ~] = fileparts(root_folder);
if isempty(root_name), root_name = root_folder; end

fprintf('\n==================================================\n');
fprintf(' DIRECTORY STRUCTURE FOR: %s\n', root_name);
fprintf('==================================================\n');
fprintf('[Root] %s/\n', root_name);

% Call the helper function to print contents recursively up to level 5
print_directory_level(root_folder, 1, 5);

fprintf('==================================================\n');


%% 3. Recursive Helper Function
function print_directory_level(current_dir, current_level, max_levels)
    % Stop if we have breached our maximum allowed depth level
    if current_level > max_levels
        return;
    end
    
    % Get directory contents
    dir_contents = dir(current_dir);
    if isempty(dir_contents)
        return;
    end
    
    % Create an indentation prefix based on the current level depth
    indent = repmat('    ', 1, current_level);
    
    % First, separate folders and files so folders print first (optional, for neatness)
    is_dir = [dir_contents.isdir];
    names = {dir_contents.name};
    
    % Filter out '.' and '..'
    valid_idx = ~strcmp(names, '.') & ~strcmp(names, '..');
    dir_contents = dir_contents(valid_idx);
    is_dir = is_dir(valid_idx);
    
    % Loop through contents
    for i = 1:length(dir_contents)
        item = dir_contents(i);
        full_item_path = fullfile(current_dir, item.name);
        
        if item.isdir
            % Print folder with a trailing slash and folder icon indicator
            fprintf('%s📁 %s/\n', indent, item.name);
            
            % Recursively move down to the next level inside this folder
            print_directory_level(full_item_path, current_level + 1, max_levels);
        else
            % Print file with a file icon indicator
            fprintf('%s📄 %s\n', indent, item.name);
        end
    end
end