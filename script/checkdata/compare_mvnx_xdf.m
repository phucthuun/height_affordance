%% Xsens-Loadsol Final Integration: Real-Time Sync & Video
clear; clc; close all;

%% 1. File Selection
[xFile, xPath] = uigetfile('*.xdf', 'Select Xsens XDF File');
if isequal(xFile,0); return; end

%% 2. Load Xsens Data (Master)
fprintf('Loading XDF: %s...\n', xFile);
streams = load_xdf(fullfile(xPath, xFile));

xIdx = find(cellfun(@(x) contains(x.info.name, 'QuaternionDatagram1'), streams), 1);
tIdx = find(cellfun(@(x) contains(x.info.name, 'Trigger', 'IgnoreCase', true) || ...
                          contains(x.info.name, 'MATLAB_Trigger'), streams), 1);

xData = double(streams{xIdx}.time_series); 
xTime = streams{xIdx}.time_stamps;
tText = streams{tIdx}.time_series;
tTime = streams{tIdx}.time_stamps;

% Calculate Actual Sample Rate
srateX = 1 / mean(diff(xTime));
fprintf('Master Sample Rate: %.2f Hz\n', srateX);



%% 1. File Selection
[xFile, xPath] = uigetfile('*.mvnx', 'Select Xsens MVNX File');

%% Load data
% Change the filename here to the name of the file you would like to import
tree = load_mvnx(fullfile(xPath, xFile));

%% Read some basic data from the file
mvnxVersion = tree.metaData.mvnx_version; % version of the MVN Studio used during recording

if (isfield(tree.metaData, 'comment'))
    fileComments = tree.metaData.comment; % comments written when saving the file
end

%% Read some basic properties of the subject;
frameRate = tree.metaData.subject_frameRate;
suitLabel = tree.metaData.subject_label;
originalFilename = tree.metaData.subject_originalFilename;
recDate = tree.metaData.subject_recDate;
segmentCount = tree.metaData.subject_segmentCount;

%% Retrieve sensor labels
%creates a struct with sensor data
if isfield(tree,'sensorData') && isstruct(tree.sensorData)
    sensorData = tree.sensorData;
end

%% Retrieve segment labels
%creates a struct with segment definitions
if isfield(tree,'segmentData') && isstruct(tree.segmentData)
    segmentData = tree.segmentData;
end


%% --- Bridge Script: MVNX to XDF Format Conversion & Validation ---
fprintf('Transforming MVNX tree structure into XDF matrix format...\n');

% 1. Extract structural constants safely with data type checking
if iscell(tree.metaData.subject_segmentCount)
    nSegments = str2double(tree.metaData.subject_segmentCount{1});
elseif ischar(tree.metaData.subject_segmentCount) || isstring(tree.metaData.subject_segmentCount)
    nSegments = str2double(tree.metaData.subject_segmentCount);
else
    nSegments = double(tree.metaData.subject_segmentCount);
end

% Fallback check: count actual elements if metadata parsing is messy
if isnan(nSegments) || isempty(nSegments)
    nSegments = numel(tree.segmentData);
end

% Extract frame counts safely
nFrames = size(tree.segmentData(1).position, 1);

% Ensure scalar confirmation
nSegments = double(nSegments(1));
nFrames = double(nFrames(1));

% Preallocate the flat matrix to match Script 1 layout (7-channel blocks)
xData_from_mvnx = zeros(nSegments * 7, nFrames);

% 2. Reshape and Flatten MVNX into the [Channels x Time] Matrix
for s = 1:nSegments
    % Calculate row spans for the current segment
    rowStart = (s - 1) * 7 + 1;
    
    % Extract orientation (4 rows) and position (3 rows)
    % Transposing (') converts [Time x Dim] to [Dim x Time]
    quat_stream = tree.segmentData(s).orientation'; 
    pos_stream  = tree.segmentData(s).position';
    
    % Pack into the consolidated array
    xData_from_mvnx(rowStart:(rowStart+3), :) = quat_stream;
    xData_from_mvnx((rowStart+4):(rowStart+6), :) = pos_stream;
end

fprintf('Transformation complete. New matrix size: [%d x %d]\n\n', size(xData_from_mvnx));


%% 3. Cross-File Similarity Verification
% Run this step ONLY if you have loaded both variables (xData from Script 1 and xData_from_mvnx)

if exist('xData', 'var')
    fprintf('=== RUNNING SIMILARITY CHECKS ===\n');
    
    % Check 1: Absolute Size Comparison
    [rowsXDF, colsXDF] = size(xData);
    [rowsMVNX, colsMVNX] = size(xData_from_mvnx);
    
    fprintf('XDF Shape:  [%d x %d]\n', rowsXDF, colsXDF);
    fprintf('MVNX Shape: [%d x %d]\n', rowsMVNX, colsMVNX);
    
    % Temporal alignment check
    if colsXDF ~= colsMVNX
        warning('Time lengths differ! XDF has %d frames, MVNX has %d frames. Aligning to shorter file for comparison.', colsXDF, colsMVNX);
        minFrames = min(colsXDF, colsMVNX);
        xData_cmp = xData(1:min(rowsXDF, rowsMVNX), 1:minFrames);
        mvnx_cmp  = xData_from_mvnx(1:min(rowsXDF, rowsMVNX), 1:minFrames);
    else
        xData_cmp = xData;
        mvnx_cmp = xData_from_mvnx;
    end
    
    % Check 2: Statistical Verification (Correlation & MSE)
    % Let's isolate Pelvis Position (Rows 5:7) and Pelvis Quaternions (Rows 1:4)
    cc_pos  = corrcoef(xData_cmp(5, :), mvnx_cmp(5, :));
    cc_quat = corrcoef(xData_cmp(1, :), mvnx_cmp(1, :));
    
    mse_pos = mean((xData_cmp(5, :) - mvnx_cmp(5, :)).^2);
    
    fprintf('Pelvis X-Position Pearson Correlation: %.4f\n', cc_pos(1,2));
    fprintf('Pelvis q0-Quaternion Pearson Correlation: %.4f\n', cc_quat(1,2));
    fprintf('Mean Squared Error (MSE) of Position: %.6e\n', mse_pos);
    
    % Visualizing Comparison
    figure('Color', 'w', 'Name', 'XDF vs MVNX Direct Trace Comparison');
    subplot(2,1,1);
    plot(xData_cmp(5, :), 'LineWidth', 2, 'Color', [0 0.4470 0.7410]); hold on;
    plot(mvnx_cmp(5, :), '--', 'LineWidth', 1.5, 'Color', [0.8500 0.3250 0.0980]);
    title('Pelvis Position X-Axis'); ylabel('Meters'); legend('XDF (LSL)', 'MVNX (File Export)'); grid on;
    
    subplot(2,1,2);
    plot(xData_cmp(1, :), 'LineWidth', 2, 'Color', [0.4660 0.6740 0.1880]); hold on;
    plot(mvnx_cmp(1, :), '--', 'LineWidth', 1.5, 'Color', [0.4940 0.1840 0.5560]);
    title('Pelvis Quaternion (q0)'); ylabel('Value'); legend('XDF (LSL)', 'MVNX (File Export)'); grid on;
    
else
    fprintf('⚠️ Could not check similarity: "xData" variable from Script 1 is not found in the workspace.\n');
    fprintf('Load an XDF file using Script 1 first, then run this conversion to run cross-validation.\n');
end