%EXAMPLE_AUTO_PROMPTER
%
%   Note: This can be run from outside the `+typewriter` folder; use:
%   ```
%       typewriter.example_auto_prompter;
%   ```
%   (Called from the project workspace folder where you have installed this
%    as a gitmodule using the +typewriter package syntax. If you do not
%    want to mess with git, then at the very least make sure the folder
%    containing this file is named +typewriter and that you are in a folder
%    containing the +typewriter folder (or the folder containing
%    +typewriter is on your MATLAB path) when you try to interact with
%    the code.)

close all force;
clear;
clc;

mainTick = tic();
SUBJ = "TEST";
YYYY = year(datetime('now'));
MM = month(datetime('now'));
DD = day(datetime('now'));
BLOCK = 1;

logFile = sprintf("%s_%04d_%02d_%02d_%d.typewriterdata", ...
    SUBJ, YYYY, MM, DD, BLOCK);

prompter = typewriter.Prompter(...
    'AutoAdvanceOnComplete',true, ...
    'MainTick',mainTick);
prompter.startLogging(logFile);
fprintf(1,'\n\t->\tLogging to %s: FID = %d\n', ...
    logFile, prompter.logFileID_);

sock = udpport("IPV4",'Timeout', 0.25); 
sock.UserData = struct(...
        'Paused', false, ...
        'Destination', struct( ...
            'Address', "127.0.0.1", ...
            'Port', 7053), ... % Or, use: prompter.getPort(), ...
        'Prompt', '', ...
        'Index', [], ...
        'N', [], ...
        'MainTick', mainTick, ...
        'RequestMessage', jsonencode(struct(...
            'ip', "127.0.0.1", ...      % Origin IP of sender
            'port', sock.LocalPort, ... % Origin port of sender
            'type', typewriter.PrompterMessageType.Method, ...
            'method', typewriter.PrompterMethod.GetPrompt)), ...
        'ControlMessage', struct(...
            'type', typewriter.PrompterMessageType.IO, ...
            'device', typewriter.PrompterDevice.VKeyboard, ...
            'in', '_'));
sock.configureCallback("terminator", @(src,evt)handlePauseMessage(src,evt));

fprintf(1,...
    '\nThis example will send virtual keystrokes to "%s:%d".\n', ...
    sock.UserData.Destination.Address, ...
    sock.UserData.Destination.Port);

while isvalid(prompter)
    if ~sock.UserData.Paused
        sock.UserData.Index = 0;
        % sock.UserData.Prompt = prompter.getPrompt(); % If we want to do it without using UDP 
        sock.configureCallback("off"); % Temporarily remove callback
        sock.writeline(sock.UserData.RequestMessage, ...
            sock.UserData.Destination.Address, ...
            sock.UserData.Destination.Port);
        try
            msg = jsondecode(sock.readline()); % (We want this to block)
        catch
            sock.UserData.Paused = true;
        end
        % Return to \r\n terminated JSON message listening
        sock.configureCallback("terminator", @(src,evt)handlePauseMessage(src,evt));
        sock.UserData.Prompt = msg.value;
        sock.UserData.N = strlength(sock.UserData.Prompt);
        while (sock.UserData.Index < sock.UserData.N) && ~sock.UserData.Paused
            sock.UserData.Index = sock.UserData.Index + 1;
            sock.UserData.ControlMessage.in = sock.UserData.Prompt(sock.UserData.Index);
            sock.writeline(jsonencode(sock.UserData.ControlMessage), ...
                sock.UserData.Destination.Address, ...
                sock.UserData.Destination.Port);
            pause(0.100);
            if sock.UserData.Paused
                break;
            end
        end
    end
    pause(0.150); % Make sure to leave time to reset the input textbox.
end
% `prompter` will automatically call `stopLogging` if it is deleted.
% `prompter` is automatically deleted if you close the GUI window.
loggedData = typewriter.Prompter.read(logFile);
fprintf(1,'Logged %d keystroke events in %.1f minutes:\n', ...
    size(loggedData,1), round(toc(mainTick)/60,1));
head(loggedData);

    function handlePauseMessage(src, evt)
        %HANDLEPAUSEMESSAGE Simple callback to handle pause/unpause
        rcv = readline(src);
        msg = jsondecode(rcv);
        if isfield(msg,'paused')
            src.UserData.Paused = msg.paused;
            fprintf(1,'[%s]::Received::%s\n', string(evt.AbsoluteTime), rcv);
        else
            fprintf(1,'[%s]::Received::[NON-PAUSE-MESSAGE]::%s\n', string(evt.AbsoluteTime), rcv);
        end
    end