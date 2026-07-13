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

taskconfig.instruction.eyetracking=           ['YOUR TASK: Eye Tracking Calibration\n\n' ...
                                             '+\n\n\n'...
                                             '1. Do not move your head\n'...
                                             '2. Only move your eyes\n\n\n'...
                                             'Keep N-Pose and Follow the dot with your eyes'];

taskconfig.instruction.training =           ['YOUR TASK\n\n\n\n ' ...
                                             'Choose and execute the most efficient technique you think \n'...
                                             'that could throw the opponent to the ground \n\n\n'...
                                             '1. Hold N-Pose when you see letter N\n\n' ...
                                             '2. Only move when the fighter is defensive!'];

taskconfig.instruction.heightaffordance =   ['YOUR TASK\n\n\n\n ' ...
                                             'Choose and execute the most efficient technique you think \n'...
                                             'that could throw the opponent to the ground \n\n\n'...
                                             '1. Hold N-Pose when you see letter N\n\n' ...
                                             '2. Only move when the fighter is defensive!'];

taskconfig.instruction.estimate = ['YOUR TASK\n\n\n\n ' ...
                                    'Tell us your estimation\n\n' ...
                                    'How TALL were these fighters when standing upright\n\n' ...
                                    '(Feel free to come closer to the screen or use the ruler to give your best estimation)'];




% --------------------------------------
% Timing
% --------------------------------------
taskconfig.numBlocks.training         = 1.00;
taskconfig.numBlocks.heightaffordance = 6.00;
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