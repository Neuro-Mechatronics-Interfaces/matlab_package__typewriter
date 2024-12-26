classdef PrompterDevice < int8
    %PROMPTERDEVICE Integer enumeration for parsing JSON-Serialized UDP messages that control keystroke input.
    %
    % Keyboard (0) - Standard keyboard
    % VKeyboard (1) - Virtual keyboard
    % VWord (2) - Virtual "word" (predicted multi-character)
    %
    % Currently, only `Keyboard (0)` is appreciably used. The other two are
    % basically "reserved for future use" if-needed.
    %
    % See also: typewriter.Prompter, typewriter.Prompter.handleIO
    
    enumeration
        Keyboard (0) % Standard keyboard
        VKeyboard (1) % Virtual keyboard
        VWord (2) % Virtual "word" (predicted multi-character)
    end
end
