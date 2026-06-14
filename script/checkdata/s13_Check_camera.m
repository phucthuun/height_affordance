%% LSL Video-Marker Synchronizer + Trimmer
% Single MATLAB file:  - sync XDF → frame indices
%                       - open videos
%                       - cut + embed marker overlay
% Author: you
clear; clc;

%% ----------------------------------------------------------
%% 0.  Set up path utilities
%     ----------------------------------------------------------
[videoFile0,  videoPath0]  = uigetfile({'*.avi;*.mp4;*.mkv','Video files'},...
                                        'Select Upper-Cam video');
[videoFile1,  videoPath1]  = uigetfile({'*.avi;*.mp4;*.mkv','Video files'},...
                                        'Select Side-Cam video (ESC to skip)');
[xdfFile, xdfPath] = uigetfile('*.xdf','Select XDF with Euleria triggers');
if any(isequal({videoFile0,xdfFile},0))
    error('Video 0 + XDF required.');
end
vidPaths = {fullfile(videoPath0,videoFile0)};
if ~isequal(videoFile1,0)
    vidPaths{end+1} = fullfile(videoPath1,videoFile1);
end

fprintf('Loading XDF: %s...\n',xdfFile);
streams = load_xdf(fullfile(xdfPath,xdfFile));

%% ----------------------------------------------------------
%% 1.  Read streams
%     ----------------------------------------------------------
mIdx   = find(cellfun(@(x) contains(x.info.name,'Trigger','IgnoreCase',true),...
                       streams),1);
cam0   = find(cellfun(@(x) strcmp(x.info.name,'FrameMarker_0'), streams),1);
cam1   = find(cellfun(@(x) strcmp(x.info.name,'FrameMarker_1'), streams),1);

assert(~isempty(mIdx) && ~isempty(cam0),'Required streams not found.');

mText  = streams{mIdx}.time_series(:);
mTime  = streams{mIdx}.time_stamps(:);

v0Frm  = streams{cam0}.time_series(:);
v0T    = streams{cam0}.time_stamps(:);
v1Frm  = []; v1T = [];
if ~isempty(cam1)
    v1Frm = streams{cam1}.time_series(:);
    v1T   = streams{cam1}.time_stamps(:);
end

%% ----------------------------------------------------------
%% 2.  Build marker <--> frame map
%     ----------------------------------------------------------
numM = numel(mText);
tbl  = table(mText(:),mTime(:), repmat(NaN,numM,1), repmat(NaN,numM,1), ...
           'VariableNames',{'Event','LSL_Timestamp','Cam0_Frame','Cam1_Frame'});

% Quick nearest frame look-up
[~,c0] = min(abs(v0T' - tbl.LSL_Timestamp));     tbl.Cam0_Frame = v0Frm(c0).';
if ~isempty(v1Frm)
    [~,c1] = min(abs(v1T' - tbl.LSL_Timestamp)); tbl.Cam1_Frame = v1Frm(c1).';
end
disp(tbl);

%% ----------------------------------------------------------
%% 3. Frame-rate sanity check
%     ----------------------------------------------------------
intervals = diff(v0T);
fprintf('\n--- Diagnostics ---\n');
fprintf('Actual fps  : %.2f\n',1/mean(intervals));
fprintf('Potential dropped frames: %d\n',nnz(diff(v0Frm)>1));

%% ----------------------------------------------------------
%% 4. Video cutter / overlay – MATLAB version
%    Requires Computer Vision toolbox (VideoFileReader / VideoFileWriter)
%     ----------------------------------------------------------
if ~exist('vision.VideoFileReader','class')
    warning('Skipping trim phase – Vision Toolbox not available.');
    return;
end
for camID = 1:numel(vidPaths)
    vidPath = vidPaths{camID};
    [~,fn,ext] = fileparts(vidPath);
    outPath = fullfile(xdfPath, sprintf('TRIMMED_%s%s', fn, ext));

    colName = sprintf('Cam%d_Frame',camID-1); % Cam0, Cam1
    if ~isfield(tbl,colName);  continue; end

    frmMask = ~isnan(tbl.(colName));
    if ~any(frmMask); continue; end

    % boundaries
    frmStart = cast(min(tbl.(colName)(frmMask)) , 'int32');
    frmEnd   = cast(max(tbl.(colName)(frmMask)) , 'int32');
    fprintf('Trimming %s frames %d-%d\n',fn,frmStart,frmEnd);

    % locate this frame-column's exact-to-Event LUT
    lut = containers.Map(tbl.(colName)(frmMask), tbl.Event(frmMask));

    % video IO
    reader  = vision.VideoFileReader(vidPath,'ImageColorSpace','RGB');
    vidInfo = info(reader);
    vidInfo.VideoFrames = frmEnd - frmStart + 1;
    writer  = VideoWriter(outPath,'MP4');
    writer.FrameRate     = vidInfo.FrameRate;
    writer.Quality       = 100;
    open(writer);

    frameIdx = int32(0);
    for k = 1:frmStart-1 % seek without decoding (cheap in MATLAB)
        step(reader); % discard
    end
    while frameIdx < frmEnd
        [~, img] = step(reader);
        frameIdx  = frameIdx + 1;

        % overlay
        if isKey(lut,double(frameIdx))
            lbl = sprintf('MARKER: %s',lut(double(frameIdx)));
            img = insertText(img,[10 10], lbl,...
                        'FontSize',22,'TextColor',[0 255 0],'BoxColor','black');
        end

        img = insertText(img,[10 70], sprintf('Frame: %d',frameIdx),...
                         'FontSize',16,'TextColor','white');
        writeVideo(writer, img);
    end
    release(reader); close(writer);
    fprintf('Saved -> %s\n',outPath);
end
fprintf('\nUpload/inspect "_TRIMMED_" files in the chosen folder.\n');
