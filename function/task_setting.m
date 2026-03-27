 % Temporal and spatial information of stimuli and trials
function taskconfig=tasks_etting(log)

% --------------------------------------
% Instruction
% --------------------------------------
%% Welcome
taskconfig.instruction.welcome = ['Herzlich Willkommen'];

%% RSVP
taskconfig.instruction.rsvp=['[RSVP]']


%% ENC
taskconfig.instruction.enc=['[ENC] ']


%% Test
taskconfig.instruction.test=['[TEST] ']

% --------------------------------------
% Timing
% --------------------------------------
%% Encoding
% Idea: sound + image (5s) > iti (fixation cross: 2s) 
taskconfig.enc.baselinedur.image=0.1;
taskconfig.enc.stimdur.image=0.5;
taskconfig.enc.iti=1;

%% Test
% Idea: sound (2s) > blank page (5s) > target & lure (self-paced) > iti ('Bereit?' instead of fixation cross: 2s) 
taskconfig.test.stimdur.image=NaN();
taskconfig.test.stimdur.sound=2;
taskconfig.test.iti=2; 
taskconfig.test.blank=5;

%% Rapid Serial Visual Presentation (rsvp) %added by Tydings
% structure: image (1s) > iti (fixation cross 1s) > ...
taskconfig.rsvp.stimdur.image   = .7;
taskconfig.rsvp.iti             = .8;


% --------------------------------------
% Presentation
% --------------------------------------


%% Phuc's presentation rect
% Idea:  present objects inside a customized rectangle (size 25x15 unit)
% H, W: height and width of the rectangle
% h, w: onset of the rectangle relative to the (0,0) point of the real screen
% See: ...\function\customize-rect.jpg

% Experimenter screen
% @Phuc: area of the PN's rect is 90% of the full screen
taskconfig.presentationrect.window1.proportionFull = 0.9;
taskconfig.presentationrect.window1.ratioFull = log.config.ptb.screenXpixels1/log.config.ptb.screenYpixels1;
taskconfig.presentationrect.window1.ratioRect = 25/15;

taskconfig.presentationrect.window1.H = sqrt((taskconfig.presentationrect.window1.proportionFull*taskconfig.presentationrect.window1.ratioFull*log.config.ptb.screenYpixels1^2)/taskconfig.presentationrect.window1.ratioRect);
taskconfig.presentationrect.window1.W = taskconfig.presentationrect.window1.ratioRect * taskconfig.presentationrect.window1.H;
taskconfig.presentationrect.window1.h = (log.config.ptb.screenYpixels1 - taskconfig.presentationrect.window1.H)* 0.5;
taskconfig.presentationrect.window1.w = (log.config.ptb.screenXpixels1 - taskconfig.presentationrect.window1.W)* 0.5;
taskconfig.presentationrect.window1.Hunit = taskconfig.presentationrect.window1.H/15;
taskconfig.presentationrect.window1.Wunit = taskconfig.presentationrect.window1.W/25;
taskconfig.presentationrect.window1.Rect = [taskconfig.presentationrect.window1.w, taskconfig.presentationrect.window1.h, taskconfig.presentationrect.window1.w + taskconfig.presentationrect.window1.W, taskconfig.presentationrect.window1.h + taskconfig.presentationrect.window1.H];

% Subject screen
% @Phuc: area of the PN's rect is 90% of the full screen
taskconfig.presentationrect.window2.proportionFull = 0.9;
taskconfig.presentationrect.window2.ratioFull = log.config.ptb.screenXpixels2/log.config.ptb.screenYpixels2;
taskconfig.presentationrect.window2.ratioRect = 25/15;

taskconfig.presentationrect.window2.H = sqrt((taskconfig.presentationrect.window2.proportionFull*taskconfig.presentationrect.window2.ratioFull*log.config.ptb.screenYpixels2^2)/taskconfig.presentationrect.window2.ratioRect);
taskconfig.presentationrect.window2.W = taskconfig.presentationrect.window2.ratioRect * taskconfig.presentationrect.window2.H;
taskconfig.presentationrect.window2.h = (log.config.ptb.screenYpixels2 - taskconfig.presentationrect.window2.H)* 0.5;
taskconfig.presentationrect.window2.w = (log.config.ptb.screenXpixels2 - taskconfig.presentationrect.window2.W)* 0.5;
taskconfig.presentationrect.window2.Hunit = taskconfig.presentationrect.window2.H/15;
taskconfig.presentationrect.window2.Wunit = taskconfig.presentationrect.window2.W/25;
taskconfig.presentationrect.window2.Rect = [taskconfig.presentationrect.window2.w, taskconfig.presentationrect.window2.h, taskconfig.presentationrect.window2.w + taskconfig.presentationrect.window2.W, taskconfig.presentationrect.window2.h + taskconfig.presentationrect.window2.H];

sqrt((taskconfig.presentationrect.window1.proportionFull*taskconfig.presentationrect.window1.ratioFull*log.config.ptb.screenYpixels1^2)/taskconfig.presentationrect.window1.ratioRect);
sqrt((taskconfig.presentationrect.window2.proportionFull*taskconfig.presentationrect.window2.ratioFull*log.config.ptb.screenYpixels1^2)/taskconfig.presentationrect.window2.ratioRect);


end