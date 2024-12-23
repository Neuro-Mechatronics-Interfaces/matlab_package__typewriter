classdef PrompterMessageType < int8
    enumeration
        Method (1) % "Method" Message type (invokes a method of Prompter class).
        IO (2)     % "Input/Output" Message type (e.g. Keyboard emulation).
    end
end
