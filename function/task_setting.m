 % Temporal and spatial information of stimuli and trials
function taskconfig=task_setting()

% --------------------------------------
% Color palette
% --------------------------------------

taskconfig.colour.black=[0 0 0];
taskconfig.colour.white=[255 255 255];
taskconfig.colour.dark =[10 10 12];



% --------------------------------------
% Instruction
% --------------------------------------

taskconfig.instruction.welcome = ['Herzlich Willkommen'];




% --------------------------------------
% Timing
% --------------------------------------

taskconfig.time.offload                    = 2.00; 
taskconfig.time.fixation                   = 0.25; 
taskconfig.time.neutral                    = 0.50; 
taskconfig.time.fight                      = 1.50;
taskconfig.time.iti                        = 0.5; % interstimulus intervall


% --------------------------------------
% Background
% --------------------------------------
taskconfig.bg = taskconfig.colour.dark;


end