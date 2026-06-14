% PTB-3 settings
function ptb = ptb_setting(log)
    % --- 1. System Setup ---
    PsychDefaultSetup(2);
%     Screen('Preference', 'ConserveVRAM', 4096); % alternative method for v-sync since DWM cannot be disabled on newer Win systems, if not used PTB will give sync failures 
%     Screen('Preference', 'VBLEndlineOverride', 2160); % PTB can crash if endline isn't set fixed
    Screen('Preference', 'SkipSyncTests', 1);
    KbName('UnifyKeyNames');
    
    % --- 2. Window Setup ---
    % Accessing background color from the nested log structure
    bgColor = log.config.task.bg; 
    
    s1 = max(Screen('Screens'));

    [ptb.w1, ptb.rect1] = Screen('OpenWindow', s1, bgColor); 
    Screen('BlendFunction', ptb.w1, 'GL_SRC_ALPHA', 'GL_ONE_MINUS_SRC_ALPHA'); % Enable Alpha Blending for transparency
    % [ptb.w2, ptb.rect2] = Screen('OpenWindow', s2, bgColor);
    % Screen('BlendFunction', ptb.w1, 'GL_SRC_ALPHA', 'GL_ONE_MINUS_SRC_ALPHA'); % Enable Alpha Blending for transparency
    
    % --- 3. Measurements & Timing ---
    [ptb.sw, ptb.sh] = Screen('WindowSize', ptb.w1);
    [ptb.xc, ptb.yc] = RectCenter(ptb.rect1);
    ptb.ifi = Screen('GetFlipInterval', ptb.w1);
    
    % --- 4. Inputs & Visuals ---
    ptb.key.esc = KbName('ESCAPE');
    ptb.key.space = KbName('space');
    
    % Restrict keys (Space and Esc)
    RestrictKeysForKbCheck([ptb.key.space, ptb.key.esc]);

    % --- 4. Inputs & Visuals ---
    ptb.key.esc   = KbName('RightArrow');
    ptb.key.space = KbName('space');
    ptb.key.pause = KbName('ESCAPE');

    % FIXED: Restrict keys but include Shift keys so the experimenter intervention works!
    RestrictKeysForKbCheck([ptb.key.space, ptb.key.esc, ptb.key.pause]);
    
    % Use Arial (standard) or a font defined in your log
    Screen('TextFont', ptb.w1, 'Arial');
    Screen('TextSize', ptb.w1, 30);
    
    % Enable transparency for images/fixation
    Screen('BlendFunction', ptb.w1, 'GL_SRC_ALPHA', 'GL_ONE_MINUS_SRC_ALPHA');
    
    HideCursor;
end