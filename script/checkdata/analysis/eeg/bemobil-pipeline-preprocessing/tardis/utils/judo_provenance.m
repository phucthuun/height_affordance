function prov = judo_provenance(cfg)
%JUDO_PROVENANCE  Who/what/where produced an output: versions, code hash, git commit, SLURM job, date.

prov = struct();
prov.pipeline         = cfg.pipeline_name;
prov.pipeline_version = cfg.pipeline_version;
prov.step             = cfg.step;
prov.date             = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss'));
prov.user             = first_nonempty(getenv('USER'), getenv('USERNAME'));
prov.host             = hostname();
prov.slurm_job_id     = getenv('SLURM_JOB_ID');
prov.matlab           = version;
prov.eeglab           = eeglab_version();
prov.toolboxes = struct( ...
    'bemobil',       plugin_version('bemobil_process_all_EEG_preprocessing'), ...
    'amica',         plugin_version('runamica15'), ...
    'iclabel',       plugin_version('iclabel'), ...
    'zapline_plus',  plugin_version('clean_data_with_zapline_plus'), ...
    'clean_rawdata', plugin_version('clean_artifacts'), ...
    'firfilt',       plugin_version('pop_eegfiltnew'), ...
    'dipfit',        plugin_version('dipfitdefs'), ...
    'xdf_import',    plugin_version('pop_loadxdf'));
prov.code_hash   = code_hash(cfg.script_dir);
prov.git_commit  = git_commit(cfg.script_dir);
prov.random_seed = cfg.random_seed;
end

function v = first_nonempty(varargin)
v = '';
for i = 1:numel(varargin)
    if ~isempty(varargin{i})
        v = varargin{i};
        return
    end
end
end

function h = hostname()
h = getenv('HOSTNAME');
if isempty(h)
    [status, out] = system('hostname');
    if status == 0
        h = strtrim(out);
    end
end
end

function v = eeglab_version()
v = 'unknown';
try
    v = eeg_getversion();
catch
end
end

function v = plugin_version(function_name)
%PLUGIN_VERSION  Name of the EEGLAB plugin folder that contains a function (e.g. 'bemobil-pipeline2.0.1').
p = which(function_name);
if isempty(p)
    v = 'not found';
    return
end
parts = strsplit(fileparts(p), filesep);
k = find(strcmpi(parts, 'plugins'), 1, 'last');
if ~isempty(k) && k < numel(parts)
    v = parts{k + 1};
else
    v = parts{end};
end
end

function h = code_hash(script_dir)
%CODE_HASH  SHA-256 over all pipeline .m and .sh files, so every output can be traced to the exact code.
persistent cached_dir cached_hash
if ~isempty(cached_hash) && strcmp(cached_dir, script_dir)
    h = cached_hash;
    return
end
files = [dir(fullfile(script_dir, '*.m')); dir(fullfile(script_dir, '*.sh')); dir(fullfile(script_dir, 'utils', '*.m'))];
names = sort(arrayfun(@(f) fullfile(f.folder, f.name), files, 'UniformOutput', false));
names = names(~contains(names, 's00_local_paths.m'));
parts = cell(1, 2 * numel(names));
for i = 1:numel(names)
    [~, n, e] = fileparts(names{i});
    parts{2 * i - 1} = [n e];
    parts{2 * i} = fileread(names{i});
end
h = judo_hash(parts);
cached_dir = script_dir;
cached_hash = h;
end

function c = git_commit(script_dir)
c = '';
if ispc
    quiet = '2>nul';
else
    quiet = '2>/dev/null';
end
[status, out] = system(sprintf('git -C "%s" rev-parse --short HEAD %s', script_dir, quiet));
if status == 0
    c = strtrim(out);
    [status2, out2] = system(sprintf('git -C "%s" status --porcelain %s', script_dir, quiet));
    if status2 == 0 && ~isempty(strtrim(out2))
        c = [c '-dirty'];
    end
end
end
