function confirmation_text(stepDescription)
    % verifyExperimentStep - Forces the experimenter to type 'confirm' to proceed.
    %
    % Usage: verifyExperimentStep('Check LSL Signal and start EEG Recording')

    if nargin < 1
        stepDescription = 'the current setup step';
    end

    fprintf('\n======================================================\n');
    fprintf('EXPERIMENTER: %s.\n', stepDescription);
    fprintf('======================================================\n');

    user_input = "";
    % Loop until the user types 'confirm' (case-insensitive)
    while ~strcmpi(user_input, "confirm")
        user_input = input('Type "confirm" and press ENTER to continue: ', 's');
        
        if ~strcmpi(user_input, "confirm")
            fprintf('>> [!] Action required: You must type "confirm" to proceed.\n');
        end
    end

    fprintf('>> Step verified. Continuing...\n\n');
end