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

taskconfig.instruction.training = ['YOUR TASK\n\n\n\n ' ...
                                    'Only move when the fighter is defensive!'];

taskconfig.instruction.heightaffordance = ['YOUR TASK\n\n\n\n ' ...
                                    'White fighter = KRAUL\n\n ' ...
                                    'Blue fighter = Brustschwimmen \n\n 9AYZH6 = JUDO'];

taskconfig.instruction.estimate = ['YOUR TASK\n\n\n\n ' ...
                                    'Tell the experiment your estimation\n\n' ...
                                    'How TALL are the fighters'];




% --------------------------------------
% Timing
% --------------------------------------
taskconfig.numBlocks.training         = 1.00;
taskconfig.numBlocks.heightaffordance = 4.00;
taskconfig.time.offload                    = 5.00; 
taskconfig.time.fixation                   = 0.25; 
taskconfig.time.neutral                    = 0.50; 
taskconfig.time.fight                      = 10.0;
taskconfig.time.iti                        = 0.5; % interstimulus intervall


% --------------------------------------
% Background
% --------------------------------------
taskconfig.bg = taskconfig.colour.dark;


end