classdef PrompterMessageType < int8
    %PROMPTERMESSAGETYPE Integer enumeration for handling different generic classes of UDP JSON-serialized messages.
    %
    % This enumeration/field is always the first thing checked in any
    % received serialized UDP message. 
    %
    % See also: typewriter.Prompter, typewriter.Prompter.onMessageReceived
    enumeration
        Method (1) % "Method" Message type (invokes a method of Prompter class).
        IO (2)     % "Input/Output" Message type (e.g. Keyboard emulation).
    end
end
