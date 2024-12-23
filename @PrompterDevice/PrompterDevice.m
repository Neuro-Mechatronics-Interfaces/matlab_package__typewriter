classdef PrompterDevice < int8
    enumeration
        Keyboard (0) % Standard keyboard
        VKeyboard (1) % Virtual keyboard
        VWord (2) % Virtual "word" (predicted multi-character)
    end
end
