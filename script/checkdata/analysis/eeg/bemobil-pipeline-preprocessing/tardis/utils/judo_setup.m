function bemobil_config = judo_setup(step_name, start_eeglab)
%JUDO_SETUP  Load the s00 settings, start EEGLAB without its GUI and prepare MATLAB for headless use.
%
%   bemobil_config = judo_setup('2A')          % settings + EEGLAB
%   bemobil_config = judo_setup('3', false)    % settings only (no EEGLAB needed)
%
%   Adds the script folder and utils/ to the path, runs s00_judo_bemobil_config.m, adds EEGLAB from
%   bemobil_config.eeglab_root, applies the EEGLAB memory options (double precision, .set + .fdt files),
%   hides figures when there is no desktop, and prints the resolved folders.

if nargin < 2
    start_eeglab = true;
end

script_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(script_dir);
addpath(fullfile(script_dir, 'utils'));

run(fullfile(script_dir, 's00_judo_bemobil_config.m')); % creates bemobil_config
bemobil_config.script_dir = script_dir;
bemobil_config.step = step_name;

fprintf('\n[judo] Step %s | %s %s\n', step_name, bemobil_config.pipeline_name, bemobil_config.pipeline_version);
fprintf('[judo] Study folder: %s\n', bemobil_config.study_folder);

if ~usejava('desktop')
    try
        set(0, 'DefaultFigureVisible', 'off');
        set(0, 'DefaultFigureRenderer', 'painters');
    catch
    end
end

if ~start_eeglab
    return
end

if ~exist(bemobil_config.eeglab_root, 'dir')
    error('judo:setup', ['EEGLAB folder not found: %s\n' ...
        'Set bemobil_config.eeglab_root in s00_judo_bemobil_config.m, s00_local_paths.m or JUDO_EEGLAB_ROOT.'], ...
        bemobil_config.eeglab_root);
end
fprintf('[judo] EEGLAB: %s\n', bemobil_config.eeglab_root);
addpath(bemobil_config.eeglab_root);
eeglab('nogui');

% Double precision, no memory mapping, data in a separate .fdt file next to each .set.
pop_editoptions('option_saveversion6', 0, 'option_single', 0, 'option_memmapdata', 0, ...
    'option_savetwofiles', 1, 'option_storedisk', 0);

judo_remove_fieldtrip_externals();
end
