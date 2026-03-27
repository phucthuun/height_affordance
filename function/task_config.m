%% General Settings

function cfg = task_config

% Overall Settings
cfg.date                            = datestr(now, 'dd/mm/yy-HH:MM');
cfg.deviceIndex                     = 0;
cfg.screens.fonttype                = 'Arial'; 
cfg.screens.fontsize                = 30; 
cfg.screens.fontcolor.experiment    = [255 255 255];
cfg.screens.fontcolor.instruction   = [255 255 255];
cfg.screens.backgroundcol           = [0 0 0];
cfg.screens.fixationcross.length    = 20;
cfg.screens.fixationcross.width     = 6;

cfg.time.offload                    = 2.00; 
cfg.time.fixation                   = 0.25; 
cfg.time.neutral                    = 0.50; 
cfg.time.fight                      = 1.50;
cfg.time.iti                        = 0.5; % interstimulus intervall

cfg.screens.experimenter            = max(Screen('Screens')) -1;
cfg.screens.participant             = max(Screen('Screens'));

% keys
KbName('UnifyKeyNames') %so that key names are unified across PCs
cfg.key.escape = 'ESCAPE';%27
cfg.key.space = 'space'; %32

cfg.log.responseIndex = 1;

end
