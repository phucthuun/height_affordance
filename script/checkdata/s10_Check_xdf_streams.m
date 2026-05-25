%% 1. Select the Two Files Individually
clear; clc;

fprintf('Select the FIRST XDF file...\n');
[file1, path1] = uigetfile('*.xdf', 'Select the FIRST XDF file');
if isequal(file1,0); return; end

fprintf('Select the SECOND XDF file...\n');
[file2, path2] = uigetfile('*.xdf', 'Select the SECOND XDF file');
if isequal(file2,0); return; end

filePaths = {fullfile(path1, file1), fullfile(path2, file2)};
fileNames = {file1, file2};

% Data structure to hold analysis
summary = struct();

%% 2. Extract Metadata and Data Status
for f = 1:2
    fprintf('\nReading structure of File %d...\n', f);
    streams = load_xdf(filePaths{f});
    
    summary(f).name = fileNames{f};
    summary(f).table = table();
    
    for s = 1:length(streams)
        % Get metadata
        sName  = streams{s}.info.name;
        sType  = streams{s}.info.type;
        
        % Channel count (handling potential string types in XDF)
        if ischar(streams{s}.info.channel_count)
            sChans = str2double(streams{s}.info.channel_count);
        else
            sChans = streams{s}.info.channel_count;
        end
        
        % Check for data presence
        % time_series is usually [Channels x Samples]
        numSamples = size(streams{s}.time_series, 2);
        hasData = numSamples > 0;
        
        % Build comparison row
        row = table({sName}, {sType}, sChans, numSamples, hasData, ...
            'VariableNames', {'Stream_Name', 'Type', 'Chans', 'SampleCount', 'HasData'});
        
        summary(f).table = [summary(f).table; row];
    end
end

%% 3. Print Results to Command Window
% 1. Perform the full outer join based on Stream_Name
% 'MergeKeys', true ensures we have one 'Stream_Name' column instead of two
mergedTable = outerjoin(summary(1).table, summary(2).table, ...
    'Keys', 'Stream_Name', 'MergeKeys', true);

% 2. Rename columns to distinguish between File 1 and File 2
% The columns will currently be named 'Type_left', 'Type_right', etc.
varNames = mergedTable.Properties.VariableNames;
varNames = strrep(varNames, '_left',  '_File1');
varNames = strrep(varNames, '_right', '_File2');
mergedTable.Properties.VariableNames = varNames;

% 3. Sort by Stream Name for better readability
mergedTable = sortrows(mergedTable, 'Stream_Name');

% 4. Display the result
fprintf('\nMerged Stream Comparison (NA indicates stream missing in one file):\n');
disp(mergedTable);