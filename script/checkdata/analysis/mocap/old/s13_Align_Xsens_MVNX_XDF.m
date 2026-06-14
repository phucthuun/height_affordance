% ========================================================================
%  XSENS MVNX & XDF (LSL) CROSS-CORRELATION SYNCHRONIZATION
% ========================================================================

% % % %% 1. Load Data Fields Safely
% % % clear; clc; close all;
% % % 
% % % % --- Load MVNX File ---
% % % [file_mvnx, path_mvnx] = uigetfile('*.mvnx', 'Select Xsens MVNX file');
% % % if isequal(file_mvnx,0); disp('User cancelled MVNX'); return; end
% % % fprintf('Loading MVNX file... This may take a moment.\n');
% % % tree = load_mvnx(fullfile(path_mvnx, file_mvnx));
% % % 
% % % % --- Load XDF File ---
% % % [file_xdf, path_xdf] = uigetfile('*.xdf', 'Select XDF file containing Xsens and Triggers');
% % % if isequal(file_xdf,0); disp('User cancelled XDF'); return; end
% % % fprintf('Loading XDF file... This may take a moment.\n');
% % % streams = load_xdf(fullfile(path_xdf, file_xdf));

%% 2. Find XDF Stream Indices (Fixes the 'xIdx' error)
xIdx = find(cellfun(@(x) contains(x.info.name, 'LinearSegmentKinematicsDatagram1'), streams), 1);
if isempty(xIdx); error('Kinematics stream not found in XDF.'); end

%% 3. Extract and Clean Data from Both Systems

% --- Extract XDF (LSL) Kinematics ---
xData = double(streams{xIdx}.time_series); 
xTime = streams{xIdx}.time_stamps;
fs_lsl = streams{xIdx}.info.nominal_srate;
if ischar(fs_lsl); fs_lsl = str2double(fs_lsl); end
if isnan(fs_lsl) || fs_lsl == 0; fs_lsl = 1 / mean(diff(xTime)); end

% Extract LSL Pelvis Position (First 3 channels: X, Y, Z)
lsl_pelvis = xData(1:3, :); 
lsl_vel = sqrt(sum(diff(lsl_pelvis, 1, 2).^2, 1));
lsl_time_vel = xTime(1:end-1); 

% --- Extract MVNX Kinematics ---
frameRate = tree.subject.frameRate;
segmentCount = double(tree.subject.segmentCount);
nSamples_mvnx = length(tree.subject.frames.frame);

allPos_mvnx = zeros(segmentCount * 3, nSamples_mvnx);

for i = 1:nSamples_mvnx
    currentFrame = tree.subject.frames.frame(i);
    % Check protection for identity/empty initialization frames
    if isfield(currentFrame, 'position') && ~isempty(currentFrame.position)
        allPos_mvnx(:, i) = currentFrame.position(:);
    end
end

% Extract MVNX Pelvis Position (First 3 channels: X, Y, Z)
mvnx_pelvis = allPos_mvnx(1:3, :); 
mvnx_vel = sqrt(sum(diff(mvnx_pelvis, 1, 2).^2, 1));
mvnx_time = (0:length(mvnx_vel)-1) / frameRate;

%% 4. Align Sampling Rates (Resampling)
if frameRate ~= fs_lsl
    fprintf('Resampling MVNX velocity from %d Hz to match LSL %d Hz...\n', frameRate, fs_lsl);
    [mvnx_vel_resampled, t_resampled] = resample(mvnx_vel, mvnx_time, fs_lsl);
else
    mvnx_vel_resampled = mvnx_vel;
end

%% 5. Perform Cross-Correlation to Find the Lag
fprintf('Calculating cross-correlation profile...\n');
% Slide the normalized velocity envelopes over each other
[correlation, lags] = xcorr(lsl_vel - mean(lsl_vel), mvnx_vel_resampled - mean(mvnx_vel_resampled));

[~, maxIdx] = max(correlation);
sample_lag = lags(maxIdx); 
time_lag_seconds = sample_lag / fs_lsl; 

fprintf('\n>>> SUCCESS! MVNX recording started exactly %.3f seconds after LSL started. <<<\n\n', time_lag_seconds);

%% 6. Synchronize Timelines
% Ground the MVNX timeline directly to the master LSL xTime clock
mvnx_sync_time = (0:nSamples_mvnx-1)/frameRate + (xTime(1) + time_lag_seconds);

%% 7. Verify the Alignment Visually
figure('Name', 'Sync Verification', 'Color', 'w');
plot(lsl_time_vel, lsl_vel / max(lsl_vel), 'b', 'LineWidth', 1); hold on;
plot(mvnx_sync_time(1:end-1), mvnx_vel / max(mvnx_vel), 'r--', 'LineWidth', 1.2);

legend('LSL Stream (Master)', 'Aligned MVNX Stream', 'Location', 'best');
title('Velocity Profiles After Automated Cross-Correlation Alignment');
xlabel('LSL Master Time (seconds)');
ylabel('Normalized Pelvis Velocity');
grid on;