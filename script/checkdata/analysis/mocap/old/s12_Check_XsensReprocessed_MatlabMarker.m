% ========================================================================
%  XSENS MVNX KINEMATICS & CENTER OF MASS (CoM) VISUALIZATION
% ========================================================================

%% 1. Load Data
% clear; clc; close all;
[file, path] = uigetfile('*.mvnx', 'Select Xsens MVNX file');
if isequal(file,0); disp('User cancelled'); return; end
fullPath = fullfile(path, file);

fprintf('Loading MVNX file... This may take a moment.\n');
% tree = load_mvnx(fullPath);
% % tree = load_mvnx("C:\Data\Research\sub-PHUC1\ses-S001\mocap\sub-PHUC1_ses-S001_task-heightaffordance_run-002_mocap.mvnx");

%% 2. Extract Properties & Metadata
frameRate = tree.subject.frameRate;
segmentCount = double(tree.subject.segmentCount); % Typically 23
nSamples = length(tree.subject.frames.frame);

%% 3. Preallocate and Extract Kinematics & CoM
allPos = zeros(segmentCount * 3, nSamples);
comPos = zeros(3, nSamples);

fprintf('Extracting segment coordinates and Center of Mass...\n');
for i = 1:nSamples
    currentFrame = tree.subject.frames.frame(i);
    
    % Extract all segment positions for this frame
    if isfield(currentFrame, 'position') && ~isempty(currentFrame.position)
        allPos(:, i) = currentFrame.position(:);
    end
    
    % Extract Center of Mass with empty-check protection
    if isfield(currentFrame, 'centerOfMass') && ~isempty(currentFrame.centerOfMass)
        comPos(:, i) = currentFrame.centerOfMass(1:3);
    elseif isfield(currentFrame, 'com') && ~isempty(currentFrame.com)
        comPos(:, i) = currentFrame.com(1:3);
    else
        % Fallback: If CoM is empty/missing, calculate the geometric mean
        if ~isempty(allPos(:, i))
            rawCoords = reshape(allPos(:, i), 3, segmentCount)';
            comPos(:, i) = mean(rawCoords, 1)';
        else
            % Ultimate fallback for completely empty frames (like identity frames)
            comPos(:, i) = [0; 0; 0]; 
        end
    end
end

%% 4. Setup Animation Figure & Plots
figAnim = figure('Name', 'Xsens_MVNX_3D', 'Color', 'w', 'Position', [100 100 800 600]);
hold on;

% Layered rendering pipeline (consistent with your XDF script)
hBody = scatter3(0,0,0, 60, 'b', 'filled', ...
                 'MarkerFaceAlpha', 0.45, ...  
                 'MarkerEdgeAlpha', 0.60);     

hCoM = scatter3(0,0,0, 150, 'k', 'd', 'filled', ...
                'MarkerEdgeColor', 'w', 'LineWidth', 1.8, ...
                'MarkerFaceAlpha', 1.0); 

grid on; axis equal;
xlabel('X (m)'); ylabel('Y (m)'); zlabel('Z (m)');

% Establish dynamic axis limits based on movement boundary
minVal = min(allPos(:)); maxVal = max(allPos(:));
xlim([minVal maxVal]); ylim([minVal maxVal]); zlim([minVal maxVal]);
legend([hBody, hCoM], {'Body Segments', 'Center of Mass'}, 'Location', 'northeast');

%% 5. Video Export Setup
[~, outName] = fileparts(file);
videoPath = fullfile(path, [outName,'_MVNX_Kinematics.mp4']);
v = VideoWriter(videoPath, 'MPEG-4');
v.FrameRate = 30; 
open(v);

view(3);
fprintf('Processing and recording video frames...\n');

% Calculate downsampling step to match desired target video frame rate
frameStep = max(1, round(frameRate / v.FrameRate));

%% 6. Animation & Render Loop
for t = 1:frameStep:nSamples
    
    % 1. Reshape raw frame data back into an [N x 3] matrix for plotting
    currentFrameBody = reshape(allPos(:, t), 3, segmentCount)'; 
    
    % 2. Get CoM and apply the 1mm layer safety offset
    currentCoM = comPos(:, t);
    rOffsetZ = 0.001; 
    currentCoMLayered = [currentCoM(1); currentCoM(2); currentCoM(3) + rOffsetZ];
    
    % 3. Update Graphics safely
    if ishandle(hBody) && ishandle(hCoM)
        set(hBody, 'XData', currentFrameBody(:,1), ...
                   'YData', currentFrameBody(:,2), ...
                   'ZData', currentFrameBody(:,3));
        
        set(hCoM, 'XData', currentCoMLayered(1), ...
                  'YData', currentCoMLayered(2), ...
                  'ZData', currentCoMLayered(3));
        
        drawnow;
        writeVideo(v, getframe(figAnim));
    else
        break;
    end
end

close(v); 
fprintf('Video processing complete! Saved to: %s\n', videoPath);