function success = lsl_send_corrected_neon_event(eventName, PHONE_IP)
    % --- CONFIGURATION ---
%     PHONE_IP = '192.168.0.163'; % Your Neon phone's local IP
    PORT     = '8080';          % Default Pupil Companion API port
    
    % FIX 1: Neon uses the singular "/api/event" endpoint for injecting annotations
    events_url = sprintf('http://%s:%s/api/event', PHONE_IP, PORT);
    
    % Configure web options for tight timeouts
    options = weboptions('MediaType', 'application/json', ...
                         'Timeout', 2, ...
                         'RequestMethod', 'post');

    try
        % =================================================================
        % STEP 1: CONSTRUCT THE NEON REST PAYLOAD
        % =================================================================
        % Pupil Neon automatically timestamps incoming network events on 
        % arrival if you pass the name inside an "event" nested object.
        
        payload = struct(...
            'name', eventName, ...
            'source', 'matlab_master_pipeline'...
        );
        
        % =================================================================
        % STEP 2: TRANSMIT THE EVENT
        % =================================================================
        webwrite(events_url, payload, options);
        
        fprintf(' -> Sync Event "%s"\n', eventName);
        success = true;
        
    catch ME
        warning(' ! Failed to send Pupil Neon event. Error: %s', ME.message);
        success = false;
    end
end