%% Settings for Psychtoolbox
%taken from EB OPC functions
function cfg = initialize_PTB(cfg)

% Default settings for setting up Psychtoolbox
PsychDefaultSetup(2);

% preventing Matlab from crashing due to synchro failure
Screen('Preference', 'SkipSyncTests', 1);

% Get the screen numbers
cfg.screens.available = Screen('Screens');
% Draw to the external screen if avaliable
%cfg.screens.screenNumber = max(cfg.screens.available);
%cfg.screens.screenInstructor = 1;


% Unify Key Names
KbName('KeyNamesWindows');

% Define the keyboard keys that are listened for: 

cfg.key.escapeKey   = KbName('ESCAPE');
cfg.key.oneKey      = KbName('1!');
cfg.key.twoKey      = KbName('2@');
cfg.key.threeKey    = KbName('3#');
cfg.key.fourKey     = KbName('4$');


keysOfInterest=zeros(1,256);
keysOfInterest([cfg.key.oneKey, cfg.key.twoKey ,cfg.key.threeKey,cfg.key.escapeKey])=1;
keysOfInterest([8])=1; % backspace
keysOfInterest([109])=1; % minus [-]
keysOfInterest([65:90])=1; % alphabet
keysOfInterest([27])=1; %esc
cfg.key.keysOfInterest  = keysOfInterest;

HideCursor;

% Open an on screen window   
[cfg.screens.window, cfg.screens.windowRect] = Screen('OpenWindow',cfg.screens.participant, cfg.screens.backgroundcol);
cfg.screens.xCenter = (cfg.screens.windowRect(3) - cfg.screens.windowRect(1))/2; 
cfg.screens.yCenter = (cfg.screens.windowRect(4) - cfg.screens.windowRect(2))/2;
cfg.screens.center = [(cfg.screens.windowRect(3) - cfg.screens.windowRect(1))/2, (cfg.screens.windowRect(4) - cfg.screens.windowRect(2))/2];

[cfg.screens.windowInstructor, cfg.screens.windowRectInstructor] = Screen('OpenWindow', cfg.screens.experimenter, cfg.screens.backgroundcol);
cfg.screens.xCenterInstructor = (cfg.screens.windowRectInstructor(3) - cfg.screens.windowRectInstructor(1))/2; 
cfg.screens.yCenterInstructor = (cfg.screens.windowRectInstructor(4) - cfg.screens.windowRectInstructor(2))/2;
cfg.screens.centerInstructor = [(cfg.screens.windowRectInstructor(3) - cfg.screens.windowRectInstructor(1))/2, (cfg.screens.windowRectInstructor(4) - cfg.screens.windowRectInstructor(2))/2];

[cfg.screenXpixels, cfg.screenYpixels] = Screen('WindowSize', cfg.screens.window);
[cfg.screenXpixelsInstructor, cfg.screenYpixelsInstructor] = Screen('WindowSize', cfg.screens.windowInstructor);
cfg.screens.ifi = Screen('GetFlipInterval', cfg.screens.window); 
cfg.screens.frame_dur = cfg.screens.ifi * 1000;

end