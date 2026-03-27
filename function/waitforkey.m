function [terminate]=waitforkey(waitforkey)
while 1
    [secs, keyCodelist, deltaSecs] = KbWait([]);
    keyCode=find(keyCodelist==1);
    if keyCode==waitforkey
        terminate=0; WaitSecs(1);
        break
    elseif keyCode==27
        %stops psychtoolbox    
        disp('Escape key pressed.');
        terminate=1; 
        break;
    end
end
