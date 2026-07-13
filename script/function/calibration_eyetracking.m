function calibration_eyetracking(window, screenX, screenY, ifi, log, PHONE_IP)
    % RUN_EYETRACKER_CALIBRATION Displays a 9-point moving dot calibration path
    % using an existing Psychtoolbox window context.

    %% --- 1. Settings Setup ---
    SCREEN_WIDTH_M  = 2.0;
    SCREEN_HEIGHT_M = 2.0;
    dotDiameter_m   = 0.06;

    trailLength     = 25;
    trailMinAlpha   = 0.0;
    trailMaxAlpha   = 0.8;

    fadeInDuration  = 0.5;
    dwellDuration   = 1.0;
    moveDuration    = 1.0;
    fadeOutDuration = 0.5;
    margin          = 0.30;
    useShortTravelOrder = true;

    % Inherit background/text colors and unified escape key mapping from your master config
    bgColor  = log.config.task.bg;
    white    = log.config.task.colour.white;
    escKey   = log.config.ptb.key.esc;

    [xCenter, yCenter] = RectCenter(Screen('Rect', window));

    %% --- 2. Metric Conversions ---
    pxPerMeter_X = screenX / SCREEN_WIDTH_M;
    pxPerMeter_Y = screenY / SCREEN_HEIGHT_M;
    pxPerMeter   = mean([pxPerMeter_X, pxPerMeter_Y]);
    dotDiameter  = dotDiameter_m * pxPerMeter;

    %% --- 3. Calibration Coordinates Generation ---
    marginX = screenX * margin;
    marginY = screenY * margin;

    left   = marginX;
    center = xCenter;
    right  = screenX - marginX;
    top    = marginY;
    middle = yCenter;
    bottom = screenY - marginY;

    positions = [
        left   top;    center top;    right  top;
        left   middle; center middle; right  middle;
        left   bottom; center bottom; right  bottom
    ];
    nPoints = size(positions, 1);

    if useShortTravelOrder
        order = [1 2 3 6 5 4 7 8 9]; % Serpentine routing trajectory
        if rand < 0.5, order = fliplr(order); end
    else
        order = randperm(nPoints);
    end
    orderedPositions = positions(order, :);

    %% --- 4. Presentation Welcome Phase ---
    Screen('TextSize', window, 30);
    DrawFormattedText(window, log.config.task.instruction.eyetracking, 'center', 'center', log.config.task.colour.white);
    Screen('Flip', window); lsl_send_corrected_neon_event(sprintf('Neon_calibration_start'), PHONE_IP);

    %% --- 5. Main Target Tracking Sequence Loop ---
    trailX = []; trailY = [];

    for i = 1:nPoints
        localAbortCheck(escKey);
        currentPos = orderedPositions(i, :);

        % --- FADE IN (First Anchor Only) ---
        if i == 1
            nFrames = max(1, round(fadeInDuration / ifi));
            for f = 1:nFrames
                localAbortCheck(escKey);
                alpha = f / nFrames;
                Screen('FillRect', window, bgColor);
                drawDotAlpha(window, white, currentPos(1), currentPos(2), dotDiameter, alpha);
                Screen('Flip', window);
            end
            trailX = currentPos(1); trailY = currentPos(2);
        end

        % --- FIXED DWELL DURATION ---
        nFrames = max(1, round(dwellDuration / ifi));
        for f = 1:nFrames
            localAbortCheck(escKey);
            trailX(end + 1) = currentPos(1);
            trailY(end + 1) = currentPos(2);
            if numel(trailX) > trailLength, trailX(1) = []; trailY(1) = []; end

            Screen('FillRect', window, bgColor);
            drawTrail(trailX, trailY, dotDiameter, trailMinAlpha, trailMaxAlpha, window, white);
            drawDotAlpha(window, white, currentPos(1), currentPos(2), dotDiameter, 1.0);
            Screen('Flip', window);
        end

        % --- INTER-POINT INTERPOLATED TRAVEL PATH ---
        if i < nPoints
            startPos = currentPos;
            endPos   = orderedPositions(i + 1, :);
            nFrames  = max(1, round(moveDuration / ifi));

            for f = 1:nFrames
                localAbortCheck(escKey);
                t = f / nFrames;
                tSmooth = 0.5 - 0.5 * cos(pi * t); % Smooth S-curve acceleration geometry

                x = startPos(1) + (endPos(1) - startPos(1)) * tSmooth;
                y = startPos(2) + (endPos(2) - startPos(2)) * tSmooth;

                trailX(end + 1) = x; trailY(end + 1) = y;
                if numel(trailX) > trailLength, trailX(1) = []; trailY(1) = []; end

                Screen('FillRect', window, bgColor);
                drawTrail(trailX, trailY, dotDiameter, trailMinAlpha, trailMaxAlpha, window, white);
                drawDotAlpha(window, white, x, y, dotDiameter, 1.0);
                Screen('Flip', window);
            end
        end
    end
    lsl_send_corrected_neon_event(sprintf('Neon_calibration_stop'), PHONE_IP);

    % --- TARGET FADE OUT ---
    lastPos = orderedPositions(end, :);
    nFrames = max(1, round(fadeOutDuration / ifi));
    for f = 1:nFrames
        localAbortCheck(escKey);
        alpha = 1 - (f / nFrames);
        Screen('FillRect', window, bgColor);
        drawDotAlpha(window, white, lastPos(1), lastPos(2), dotDiameter, alpha);
        Screen('Flip', window);
    end

    % --- BRIEF SYNC DELAY COMPLETE ---
    Screen('FillRect', window, bgColor);
    DrawFormattedText(window, 'Calibration Done', 'center', 'center', white);
    Screen('Flip', window);
    WaitSecs(1.0);
    KbReleaseWait;
end

%% ============================================================
% Helper Local Sub-functions
% ============================================================
function drawDotAlpha(window, white, x, y, diameter, alpha)
    col = [white(1:3) alpha * 255]; 
    radius = diameter / 2;
    rect = [x - radius, y - radius, x + radius, y + radius];
    Screen('FillOval', window, col, rect);
end

function drawTrail(trailX, trailY, dotDiameter, minAlpha, maxAlpha, window, white)
    n = numel(trailX);
    if n < 2, return; end
    trailDiameter = dotDiameter * 0.6;
    radius = trailDiameter / 2;

    for k = 1:n
        frac = (k - 1) / (n - 1);
        alpha = minAlpha + (maxAlpha - minAlpha) * frac;
        col = [white(1:3) alpha * 255];
        rect = [trailX(k) - radius, trailY(k) - radius, trailX(k) + radius, trailY(k) + radius];
        Screen('FillOval', window, col, rect);
    end
end

function localAbortCheck(escKey)
    [keyIsDown, ~, keyCode] = KbCheck;
    if keyIsDown && keyCode(escKey)
        error('EyeTracker:EscapePressed', 'Escape was pressed.');
    end
end