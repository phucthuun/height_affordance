% PTB-3 settings
function ptbconfig = ptb_setting(log)
% 1. DO NOT CALL Screen('OpenWindow') HERE.
% Instead, grab the pointers we already created in initialize_PTB
ptbconfig.window1 = log.config.ptb.window1; % Participant
ptbconfig.window2 = log.config.ptb.window2; % Instructor

% 2. Get the Rects from the existing windows
ptbconfig.windowRect1 = Screen('Rect', ptbconfig.window1);
ptbconfig.windowRect2 = Screen('Rect', ptbconfig.window2);

% 3. Get the size
[ptbconfig.screenXpixels1, ptbconfig.screenYpixels1] = Screen('WindowSize', ptbconfig.window1);
[ptbconfig.screenXpixels2, ptbconfig.screenYpixels2] = Screen('WindowSize', ptbconfig.window2);

% 4. Get the centre coordinate
[ptbconfig.xCenter1, ptbconfig.yCenter1] = RectCenter(ptbconfig.windowRect1);
[ptbconfig.xCenter2, ptbconfig.yCenter2] = RectCenter(ptbconfig.windowRect2);

% ... [Rest of your BlendFunction and Key settings remain the same] ...

% Set the blend funciton for the screen
Screen('BlendFunction', ptbconfig.window1, 'GL_SRC_ALPHA', 'GL_ONE_MINUS_SRC_ALPHA');
Screen('BlendFunction', ptbconfig.window2, 'GL_SRC_ALPHA', 'GL_ONE_MINUS_SRC_ALPHA'); 

% get refresh rate of monitor 1 and 2
ptbconfig.ifi1=Screen('GetFlipInterval',(ptbconfig.window1));
ptbconfig.ifi2=Screen('GetFlipInterval',(ptbconfig.window2));

% Key settings
KbName('KeyNamesWindows');

keysOfInterest=zeros(1,256);
keysOfInterest(27)=1; %esc
keysOfInterest(32)=1; %space
keysOfInterest(37)=1; %left
keysOfInterest(39)=1; %right
keysOfInterest(48)=1; %'0' above letters 
keysOfInterest(49)=1; %'1' above letters 
keysOfInterest(96)=1; %'0' in right panel
keysOfInterest(97)=1; %'1' in right panel
ptbconfig.key.keysEnabled  = keysOfInterest;


% Unififed specifications:
RestrictKeysForKbCheck([32, 97:99, 27]);

%set which device is used for key responses
ptbconfig.device=0; %o=keyboard= default/button box USB, 1= buttonbox EEG

% Hides cursor when window appears
HideCursor;
