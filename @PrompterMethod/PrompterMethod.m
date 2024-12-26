classdef PrompterMethod < int8
    %PROMPTERMETHOD Enumeration class encoding "UDP API" from JSON message requests using the UDP interface.
    %
    % Each enumeration corresponds to a specific method within the
    % typewriter.Prompter class. The struct field 'method' should have the
    % corresponding integer value attached to it for JSON-serialized
    % messages with 'type' field value set to 1
    % (typewriter.PrompterMessageType.Method). 
    %
    % See also: typewriter.Prompter, typewriter.PrompterMessageType,
    %           typewriter.Prompter.handleMethod
    enumeration
        LoadNext (1)        % Advances to the next phrase from pre-queued string array of phrases. No additional JSON-fields required.
        LoadSpecific (2)    % Advances (or goes backward) to specific index within pre-queued string array of phrases. Requires 'index' (integer 1-indexed prompt phrase index) JSON-field in serialized UDP message.
        LoadPhrases (3)     % Queues up a string array of phrases from a .txt file. Requires 'filepath' (string full-filename of .txt to load, using '/' for path-separator) JSON-field in serialized UDP message.
        GetPrompt (4)       % Requests the current prompt that is displayed on the GUI. Requires 'address' (sender IPv4 address) and 'port' (sender local UDP port number) JSON-fields in serialized UDP message.
        GetNumPhrases (5)   % Requests the total number of phrases in the pre-queued string array. Requires 'address' (sender IPv4 address) and 'port' (sender local UDP port number) JSON-fields in serialized UDP message.
        CloseConnection (6) % Close connection from UDP port so it is no longer listed in obj.remote_. Requires 'address' (sender IPv4 address) and 'port' (sender local UDP port number) JSON-fields in serialized UDP message.
    end
end
