classdef PrompterMethod < int8
    enumeration
        LoadNext (1)
        LoadSpecific (2)
        LoadPhrases (3)
        AddPhrase (4)
        RemovePhrase (5)
        SavePhrases (6)
        GetPrompt (7)
        GetNumPhrases (8)
        CloseConnection (9) % Close connection from UDP port so it is no longer listed in obj.remote_
    end
end
