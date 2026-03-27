% Subject and trial information

function[ID, filepath] = subject_info(loc)

% Asks for titel of the field opening
name='Experimental Setup Information';
prompt = {'Enter Subject Number:'}; 
% You can put in default responses in our case we can type in everything
defaults = {''};
% Opens dialog box
answer = inputdlg(prompt, name, 2.10, defaults); 

% Gives an error if nothing is written into fields for subject info
if isempty(answer{1,:})
        errordlg('Bitte ID eintragen'); 
        error ('keine VP Infos');
end

% Gets subject ID
ID = answer{1,:}; 

%make filename
filename = [['sub-' num2str(ID)] '_' ['task-heightaffordance']]; %BIDS STANDARD (read here: https://bids-standard.github.io/bids-starter-kit/faq.html#faq-session)
filepath = fullfile(loc.result,filename);
