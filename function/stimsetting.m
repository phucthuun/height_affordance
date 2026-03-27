% setting fixation cross 
function stimconfig=stimsetting()

%%
%width Feedback Box Item Spec 
% stimconfig.penWidthPixels=6; 

%% fixation positions
% Set size of the arms of fixation cross
stimconfig.fix.crossdimpix=40;
% Set coordinates
stimconfig.fix.xCoords=[-stimconfig.fix.crossdimpix stimconfig.fix.crossdimpix 0 0];
stimconfig.fix.yCoords=[0 0 -stimconfig.fix.crossdimpix stimconfig.fix.crossdimpix];
stimconfig.fix.allCoords=[stimconfig.fix.xCoords; stimconfig.fix.yCoords];

% Line width of fixation cross
stimconfig.fix.lineWidthPix=4;



end