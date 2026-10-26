function runIDs = judo_find_runs(cfg, participantID, sessionID, taskName, stage)
%JUDO_FIND_RUNS  Run IDs available for one participant/session/task at a given stage.
%
%   runIDs = judo_find_runs(cfg, id, ses, task, 'merged')        % runs imported by step 1 (input of 2A)
%   runIDs = judo_find_runs(cfg, id, ses, task, 'preprocessed')  % runs preprocessed by 2A (input of 2C)
%
%   Run IDs are read from the 'run-<ID>' part of the file names; files without one are an error.

base = sprintf('%s%s_ses-%s_task-%s_run-', cfg.filename_prefix, participantID, sessionID, taskName);

switch stage
    case 'merged'
        folder = fullfile(cfg.study_folder, cfg.raw_EEGLAB_data_folder, ...
            sprintf('sub-%s', participantID), sprintf('ses-%s', sessionID));
        files = dir(fullfile(folder, [base '*_' cfg.merged_filename]));
    case 'preprocessed'
        folder = fullfile(cfg.study_folder, cfg.EEG_preprocessing_data_folder);
        files = dir(fullfile(folder, [base '*'], [base '*_' cfg.preprocessed_filename]));
    otherwise
        error('judo:find_runs', 'Unknown stage "%s".', stage);
end

if isempty(files)
    error('judo:find_runs', ['No %s run files for participant %s, session %s, task %s in:\n  %s\n' ...
        'Check the IDs, and that the previous step finished for this participant.'], ...
        stage, participantID, sessionID, taskName, folder);
end

runIDs = cell(1, numel(files));
for i = 1:numel(files)
    tok = regexp(files(i).name, 'run-([a-zA-Z0-9]+)_', 'tokens', 'once');
    if isempty(tok)
        error('judo:find_runs', 'Cannot read the run ID from %s.', files(i).name);
    end
    runIDs{i} = tok{1};
end
runIDs = unique(runIDs);
fprintf('[judo] Found %d run(s) for %s: %s\n', numel(runIDs), participantID, strjoin(runIDs, ', '));
end
