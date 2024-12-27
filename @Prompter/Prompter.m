classdef Prompter < handle
    %PROMPTER Main typewriter package class. This is the actual GUI and handles remote communication using a UDP deserialization protocol.
    %
    % Example: Create prompter instance and listener handle to automate
    %           advancing after each prompt.
    %   prompter = typewriter.Prompter();
    %   lh = addlistener(prompter,'PromptComplete',@(src,~)src.loadNext());
    %
    % See also: typewriter.example_auto_prompter
    events
        PromptComplete
    end
    properties
        Figure
        advanceOnComplete (1,1) logical = false;
    end

    properties (GetAccess = public, SetAccess = protected)
        lastInput (1,1) uint8 = 0;
        udpObj_  % UDP port object
        prompt_   % Current prompt
        phrases_  % List of phrases_
        wordInformation_ (1,1) double = 0.0; % Average information per word in phrases_default.txt (or other list of phrases)
        phraseIndex_ (1,1) double = 0 % Current phrase index.
        promptLength_ (1,1) double = 1 % Current prompt length.
        promptWords_ (1,1) double = 0;
        startTic_ (1,1) uint64 = tic;
        mainTic_ (1,1) uint64 = tic;
        wpm (:,1) = [];
    end

    properties (Constant, Access = private)
        DEFAULT_PHRASES_FILE {mustBeTextScalar} = "config/phrases_default.txt";
        BINARY_LOGFILE_EXTENSION = "typewriterdata";
    end
    
    properties (Hidden, Access = public)
        mainGridLayout_  % UI container for UI text elements
        rightSideGridLayout_  % UI container for HUD on the right side
        wpmLabel_ % HUD indicator for words per minute
        nPhrasesLabel_ % HUD indicator total phrases counted
        startStopButton_ % UI Button
        promptAxes_  % UI axes container for promptText_ and promptBackground_
        promptText_  % Text on uiaxes indicating prompt to type
        promptBackground_ % Color behind each letter, displayed on promptAxes_
        inputBox_    % UI element for text input
        remote_ (:,1) string = strings(0,1);
        logFileID_ double = [];
    end

    methods
        % Constructor
        function obj = Prompter(options)
            %PROMPTER Construct an instance of typewriter.Prompter interface.
            arguments
                options.RandomSeed = []; % Set non-empty to force random seed
                options.Port (1,1) {mustBeInteger} = 7053;
                options.PhrasesFile {mustBeTextScalar} = "";
                options.AutoAdvanceOnComplete (1,1) logical = false;
                options.MainTick (1,1) double = tic();
            end

            obj.mainTic_ = options.MainTick;

            % Initialize UDP
            obj.initializeUDP_(options.Port);

            % Initialize optional flags
            obj.advanceOnComplete = options.AutoAdvanceOnComplete;
            
            % Load default phrases
            folderPath = fileparts(mfilename('fullpath'));
            if strlength(options.PhrasesFile) < 1
                defaultPhrasesFile = fullfile(folderPath, obj.DEFAULT_PHRASES_FILE);
            else
                defaultPhrasesFile = fullfile(folderPath, options.PhrasesFile);
            end
            if isfile(defaultPhrasesFile)
                obj.loadPhrases_(defaultPhrasesFile);
            else
                warning("Default phrases file not found: %s", defaultPhrasesFile);
                obj.phrases_ = {};
            end

            if ~isempty(options.RandomSeed)
                rng(options.RandomSeed); % Force the random stream
            end
            
            % Initialize Figure
            obj.phraseIndex_ = randi(numel(obj.phrases_), 1, 1);
            obj.initializeFigure_(folderPath);
            obj.loadNext();
            drawnow();
            obj.updatePrompt(obj.prompt_);
            obj.startTic_ = tic;
        end

        function delete(obj)
            try %#ok<TRYNC>
                obj.stopLogging();
            end
        end

        function clearInputBox(obj, src)
            try
                obj.Figure.CurrentObject = obj.promptAxes_;
                drawnow();

                % Set the Value to an empty cell array (uitable expects a cell array of strings)
                obj.recreateInputBox();
                pause(0.005);
                drawnow(); % Ensure the UI updates immediately
                
                obj.Figure.CurrentObject = obj.inputBox_;
                drawnow();
                if nargin > 1
                    stop(src);
                    delete(src);
                end
            catch ME
                warning(ME.identifier, "Failed to clear input box: %s", ME.message);
            end
        end

        function deferClearInputBox(obj)
            t = timer('ExecutionMode', 'singleShot', ...
                      'BusyMode', 'queue', ...
                      'TasksToExecute', 1, ...
                      'Name', 'Deferred Input Box Clearing Timer', ...
                      'StartDelay', 0.010, ... % Delay slightly to let UI settle
                      'Period', 0.010, ...
                      'TimerFcn', @(src,~)obj.clearInputBox(src));
            obj.lastInput = uint8(0);
            start(t);
        end

        function prompt = getPrompt(obj)
            %GETPROMPT Returns the current prompt.
            %
            % Syntax:
            %   prompt = obj.getPrompt();
            prompt = char(obj.prompt_);
        end

        function port = getPort(obj)
            %GETPORT Returns the port which should be used for UDP JSON control.
            %
            % Syntax:
            %   port = obj.getPort();
            port = obj.udpObj_.LocalPort;
        end

        function maxIndex = getNumPhrases(obj)
            %GETNUMPHRASES Returns the maximum allowed index for `loadSpecific`.
            %
            % Syntax:
            %   maxIndex = obj.getNumPhrases();
            maxIndex = numel(obj.phrases_);
        end

        % Load the next phrase
        function loadNext(obj)
            %LOADNEXT Updates prompt text with next loaded phrase.
            if obj.phraseIndex_ <= numel(obj.phrases_)
                obj.phraseIndex_ = mod(obj.phraseIndex_, numel(obj.phrases_)) + 1;
                phrase = obj.phrases_{obj.phraseIndex_};
                obj.updatePrompt(phrase);
                obj.startTic_ = tic;
            else
                warning('No phrases available to load.');
            end
        end

        % Load a specific phrase
        function loadSpecific(obj, index)
            %LOADSPECIFIC Update prompt with phrase by indexing into obj.phrases_ directly.
            if index >= 1 && index <= numel(obj.phrases_)
                phrase = obj.phrases_{index};
                obj.phraseIndex_ = index;
                obj.updatePrompt(phrase);
                obj.startTic_ = tic;
            else
                warning('Index out of bounds.');
            end
        end

        % Begin logging to file
        function startLogging(obj, logFile)
            %STARTLOGGING Tries to open binary file for logging.
            arguments
                obj
                logFile {mustBeTextScalar}
            end
            if ~isempty(obj.logFileID_)
                warning("Already logging to file. Did not start new logging session.");
                return;
            end
            validFilename = obj.ensureValidLogFilename(logFile);
            obj.logFileID_ = fopen(validFilename, 'wb');
            % Make sure to update the callback now that we have changed
            % property of this object.
            obj.udpObj_.configureCallback("off");
            pause(0.001);
            obj.udpObj_.configureCallback("terminator", @(src, event)onMessageReceived(obj, src, event));
            pause(0.001);
        end

        function stopLogging(obj)
            %STOPLOGGING Tries to stop logging and close log file if it is open.
            arguments
                obj
            end
            if isempty(obj.logFileID_)
                return;
            end
            fclose(obj.logFileID_);
            obj.logFileID_ = [];
        end

        function pause(obj)
            %PAUSE Public method to behave like pause button click.
            if strcmp(obj.startStopButton_.Text, "Pause")
                obj.onPauseButtonClick();
            end
        end

        function resume(obj)
            %RESUME Public method to behave like start (resume) button click.
            if strcmp(obj.startStopButton_.Text, "Start")
                obj.onStartButtonClick();
            end
        end
        
    end

    % Hidden methods which are public so they can be accessed by e.g.
    % timers or udpport objects.
    methods (Hidden, Access = public)
        function closeRemoteConnection(obj, ip, port)
            %CLOSEREMOTECONNECTION Ensures we are no longer sending UDP messages to registered remote port by removing it from list.
            addr = string(sprintf("%s:%d", ip, port));
            if ismember(addr, obj.remote_)
                obj.remote_ = setdiff(obj.remote_, addr);
                fprintf(1,'Removed remote address %s from list.\n', addr);
            else
                warning('Tried removing %s from list of remotes, but it was not a registered remote to begin with!\n', addr);
            end
        end

        % Handle e.g. emulated keyboard i/o
        function handleIO(obj, msg)
            %HANDLEIO JSON-UDP interface to update input text.
            %
            % Inputs:
            %   obj - Prompter object instance.
            %   msg - JSON deserialized struct with fields:
            %           + 'device' (int8 enumerated device) 
            %           + 'in' (input character(s))
            switch typewriter.PrompterDevice(msg.device)
                case typewriter.PrompterDevice.Keyboard
                    obj.handleKeyboardInput(char(msg.in));
                case typewriter.PrompterDevice.VKeyboard
                    obj.handleKeyboardInput(char(msg.in));
                case typewriter.PrompterDevice.VWord
                    in = char(msg.in);
                    for ii = 1:numel(in)
                        obj.handleKeyboardInput(in(ii));
                    end
            end
        end
        
        % Emulates keyboard interaction for `onInputChange` callback.
        function handleKeyboardInput(obj, in)
            %HANDLEKEYBOARDINPUT Emulates keyboard interaction for `onInputChange` callback.
            %
            % Syntax:
            %   obj - Prompter object instance
            %   in  - (1,1) char; the new/updated character to add to text.

            val = [char(obj.inputBox_.Value), in];
            obj.inputBox_.java.setValue(val);
            evtData = struct('Value', val);
            obj.onInputChange(obj.inputBox_, evtData);
        end

        % Handle methods
        function value = handleMethod(obj, msg)
            %HANDLEMETHOD Handler when JSON message 'type' field is typewriter.PrompterMethod.Method
            value = [];
            switch typewriter.PrompterMethod(msg.method)
                case typewriter.PrompterMethod.LoadNext
                    obj.loadNext();
                case typewriter.PrompterMethod.LoadSpecific
                    obj.loadSpecific(msg.index);
                case typewriter.PrompterMethod.LoadPhrases
                    obj.loadPhrases_(msg.filepath);
                case typewriter.PrompterMethod.GetPrompt
                    value = obj.getPrompt();
                case typewriter.PrompterMethod.GetNumPhrases
                    value = obj.getNumPhrases();
                case typewriter.PrompterMethod.CloseConnection
                    obj.closeRemoteConnection(msg.ip, msg.port);
                otherwise
                    warning("Unhandled method: %s", msg.method);
            end
        end

        function onWindowClose(obj, src, ~)
            %ONWINDOWCLOSE Ensure destruction of Prompter if GUI is closed.
            src.DeleteFcn = [];
            try %#ok<TRYNC>
                delete(src);
            end
            delete(obj);
            disp("Prompter deleted.");
        end

        % % % MAJOR CALLBACK FOR INPUT TEXTBOX % % %
        function onInputChange(obj, src, evt)
            %ONINPUTCHANGE Handles changes of text in input text area.
            %
            % Inputs:
            %   src - obj.inputBox_ (uitextarea)
            %   evt - Minimum is a struct with 'Value' field, which should
            %           equal the incoming updated value of the input text
            %           area.
            input = char(evt.Value);
            if strlength(input) == 0
                src.Value = evt.Value;
                return;
            elseif src.Editable == matlab.lang.OnOffSwitchState.off
                return;
            end
            ts = single(toc(obj.mainTic_));

            correct = 0;
            for i = 1:min(strlength(input), obj.promptLength_)
                if strcmpi(input(i),obj.prompt_(i))
                    obj.promptBackground_.CData(i) = 1; % Correct: Blue
                    correct = correct + 1;
                else
                    obj.promptBackground_.CData(i) = 0; % Incorrect: Red
                end
            end
            obj.lastInput = uint8(input(end));
            if ~isempty(obj.logFileID_)
                typewriter.Prompter.write(obj.logFileID_, ts, obj.lastInput);
            end
            if correct == obj.promptLength_
                % disp("Complete!");
                notify(obj, 'PromptComplete');
                if obj.advanceOnComplete
                    obj.updateStats();
                    obj.loadNext();
                    obj.deferClearInputBox();
                end
            end
        end
        % % % END: MAJOR CALLBACK FOR INPUT TEXTBOX % % %

        function onPauseButtonClick(obj)
            %ONPAUSEBUTTONCLICK  ButtonPushedFcn callback for startStopButton_ when it is "Pause" button.
            if ~isempty(obj.remote_)
                msg = jsonencode(struct('paused', true));
                obj.notifyRemote(msg);
            end
            pause(0.250); % To effectively debounce the button
            obj.startStopButton_.Text = "Start";
            obj.startStopButton_.ButtonPushedFcn = @(src,evt)obj.onStartButtonClick();
            obj.updatePrompt("");
            obj.deferClearInputBox();
            pause(0.15);
            obj.inputBox_.Editable = matlab.lang.OnOffSwitchState.off;
            pause(0.15);
        end

        function onStartButtonClick(obj)
            %ONSTARTBUTTONCLICK ButtonPushedFcn callback for startStopButton_ when it is "Start" button.
            if ~isempty(obj.remote_)
                msg = jsonencode(struct('paused', false));
                obj.notifyRemote(msg);
            end
            pause(0.250); % To effectively debounce the button
            obj.startStopButton_.Text = "Pause";
            obj.startStopButton_.ButtonPushedFcn = @(src,evt)obj.onPauseButtonClick();
            obj.inputBox_.Editable = matlab.lang.OnOffSwitchState.on;
            obj.deferClearInputBox();
            pause(0.15); % Just in case
            obj.loadSpecific(randi(numel(obj.phrases_),1,1));
            obj.inputBox_.java.focus();
        end

        function notifyRemote(obj, msg)
            %NOTIFYREMOTE Sends the JSON-encoded message to any remotes we "heard" from in this session.
            arguments
                obj
                msg {mustBeTextScalar} % JSON-encoded message
            end
            for ii = 1:numel(obj.remote_)
                ipinfo = strsplit(obj.remote_(ii),":");
                obj.udpObj_.writeline(msg, ipinfo{1}, str2double(ipinfo{2}));
            end
        end
        
        % JSON-Serialized UDP received callback (for newline-terminated byte messages)
        function onMessageReceived(obj, src, ~)
            %ONMESSAGERECEIVED Terminator-callback of obj.udpObj_.
            try
                rcv = jsondecode(readline(src));
                if isfield(rcv, 'type') 
                    switch typewriter.PrompterMessageType(rcv.type)
                        case typewriter.PrompterMessageType.Method
                            value = obj.handleMethod(rcv);
                            if ~isempty(value)
                                ret = jsonencode(struct('value', value));
                                src.writeline(ret, rcv.ip, rcv.port);
                                addr = string(sprintf("%s:%d",rcv.ip,rcv.port));
                                if ~ismember(addr, obj.remote_)
                                    obj.remote_(end+1) = addr;
                                end
                            end
                        case typewriter.PrompterMessageType.IO
                            obj.handleIO(rcv);
                        otherwise
                            warning("Unhandled message type: %s", rcv.type);
                    end
                else
                    warning("Unknown message type received.");
                end
            catch ME
                warning(ME.identifier, "Failed to process incoming message: %s", ME.message);
            end
        end

        function recreateInputBox(obj)
            %RECREATEINPUTBOX Kluj workaround for wiping out textarea input and returning focus to newly "blanked" box.
            delete(obj.inputBox_);
            obj.inputBox_ = uitextarea(obj.mainGridLayout_, ...
                'FontName', 'Consolas', ...
                'HorizontalAlignment', 'center', ...
                'Placeholder', "Enter Prompted Text", ...
                'BusyAction', 'cancel', ...
                'FontSize', 18, ...
                'Value', '', ...
                'ValueChangingFcn', @(src,evt)obj.onInputChange(src,evt));
            obj.inputBox_.Layout.Row = 2;
            obj.inputBox_.Layout.Column = 1;
            drawnow();
            obj.inputBox_.java.focus();
        end
        
        % Update the prompt text
        function updatePrompt(obj, phrase)
            %UPDATEPROMPT Update the prompt text and set the background color behind each letter to neutral grey color.
            obj.prompt_ = char(phrase);
            obj.promptText_.String = obj.prompt_;
            obj.promptLength_ = strlength(phrase);
            obj.promptWords_ = numel(strsplit(phrase, ' '));
            drawnow();

            % Determine the size of the phrase
            p = obj.promptText_.Extent;
            m = obj.promptText_.Margin;
            xData = linspace(p(1)+m, p(1)+p(3)-m, obj.promptLength_ + 1); % One block per character

            % Update the background extents
            set(obj.promptBackground_, ...
                'XData', xData, ...
                'CData', -1 * ones(1,obj.promptLength_)); 
        end

        function updateStats(obj)
            %UPDATESTATS Update the phrase word-rate and bits-per-second rate stats in HUD (as well as phrase counter).
            ttrial = toc(obj.startTic_) / 60;
            obj.wpm(end+1) = obj.promptWords_ / ttrial;
            cur_wpm = mean(obj.wpm);
            cur_bps = cur_wpm * obj.wordInformation_ / 60;
            nPhrases = numel(obj.wpm);
            obj.wpmLabel_.Text = sprintf("\\fontname{tahoma}%.1f \\color{red}(%.1f)", ...
                round(cur_wpm,1), round(cur_bps,1));
            if nPhrases == 1
                obj.nPhrasesLabel_.Text = sprintf("%d Phrase", nPhrases);
            else
                obj.nPhrasesLabel_.Text = sprintf("%d Phrases", nPhrases);
            end
            fprintf(1,"Averaging %.1f words/minute (N = %d).\n",round(cur_wpm,1),nPhrases);
        end
    end

    methods (Access = protected)
        function validFilename = ensureValidLogFilename(obj, filename)
            %ENSUREVALIDLOGFILENAME Ensures that the log-file binary has correct file-extension and that the folder it is to be saved in actually exists.
            [p,f,~] = fileparts(filename);
            % Make sure folder containing new file exists:
            if strlength(p) < 1
                p = pwd;
            elseif exist(p, 'dir') == 0
                mkdir(p);
            end
            % Make sure that file extension is correct
            validFilename = string(fullfile(p, sprintf("%s.%s", f, obj.BINARY_LOGFILE_EXTENSION)));
        end

        function loadPhrases_(obj, filepath)
            % Load phrases from the specified file
            if isfile(filepath)
                obj.phrases_ = strtrim(readlines(filepath));
                obj.phrases_ = obj.phrases_(cellfun(@(c)strlength(c)>0,obj.phrases_));
                obj.phraseIndex_ = 1; % Reset phrase index
                obj.wordInformation_ = (typewriter.Prompter.estimateWordInformation(obj.phrases_) + typewriter.Prompter.estimateInformationPerToken(obj.phrases_)) / 2;
                fprintf(1,'Using phrases in %s (average information per word: %.1f bits).\n', filepath, round(obj.wordInformation_,1));
            else
                error("File not found: %s", filepath);
            end
        end

        % Initialize the GUI Figure
        function initializeFigure_(obj, rootFolder)
            obj.Figure = uifigure('Name', 'Prompter', ...
                'Position', [225, 450, 820, 200], ...
                'Color', 'w', ...
                'Icon', fullfile(rootFolder, 'TypeWriterIcon.png'), ...
                'DeleteFcn', @(src,evt)obj.onWindowClose, ...
                'WindowStyle', 'alwaysontop');

            obj.mainGridLayout_ = uigridlayout(obj.Figure, ...
                'ColumnWidth', {'3x', '1x'}, ...
                'RowHeight', {'3x', '1x'}, ...
                'BackgroundColor', 'w');

            obj.rightSideGridLayout_ = uigridlayout(obj.mainGridLayout_, ...
                'ColumnWidth', {'1x'}, ...
                'RowHeight',{'3x', '2x', '1x', '2x'}, ...
                'BackgroundColor', [0.65 0.65 0.65]);
            obj.rightSideGridLayout_.Layout.Column = 2;
            obj.rightSideGridLayout_.Layout.Row = [1 2];
            h = uilabel(obj.rightSideGridLayout_, ...
                'Text', "\fontname{tahoma}words/min \color{red}(bits/sec)", ...
                'FontName','Tahoma','FontSize', 12,...
                'Interpreter', 'tex', 'HorizontalAlignment','center');
            h.Layout.Row = 3;
            h.Layout.Column = 1;
            obj.wpmLabel_ = uilabel(obj.rightSideGridLayout_, ...
                'Text', "\fontname{tahoma}0.0 (0.0)", ...
                'FontName','Tahoma','FontSize',18,'FontWeight','bold',...
                'Interpreter', 'tex', ...
                'FontColor','k','HorizontalAlignment','center');
            obj.wpmLabel_.Layout.Row = 2;
            obj.wpmLabel_.Layout.Column = 1;

            obj.nPhrasesLabel_ = uilabel(obj.rightSideGridLayout_, ...
                'Text', "0 Phrases", ...
                'FontName','Tahoma','FontSize',16,...
                'FontWeight','normal','FontAngle','italic', ...
                'FontColor','b','FontWeight','bold',...
                'HorizontalAlignment','center');
            obj.nPhrasesLabel_.Layout.Row = 4;
            obj.nPhrasesLabel_.Layout.Column = 1;

            obj.startStopButton_ = uibutton(obj.rightSideGridLayout_, ...
                'Text', "Pause", ...
                'FontName', 'Tahoma', ...
                'FontSize', 14, ...
                'BusyAction', 'cancel', ...
                'ButtonPushedFcn', @(src,evt)obj.onPauseButtonClick());
            obj.startStopButton_.Layout.Row = 1;
            obj.startStopButton_.Layout.Column = 1;

            % Prompt uiaxes on top
            obj.promptAxes_ = uiaxes(obj.mainGridLayout_, ...
                'Color', 'none', ...
                'Colormap', [0.45, 0.45, 0.45; 0.8 0.2 0.2; 0.2 0.2 0.8], ...
                'CLim', [-1, 1], ...
                'YLim', [-1, 1], ...
                'XLim', [-1, 1], ...
                'YDir', 'normal', ...
                'YColor', 'none', ...
                'XColor', 'none');
            obj.promptAxes_.Layout.Row = 1;
            obj.promptAxes_.Layout.Column = 1;

            % Prompt background
            obj.promptBackground_ = imagesc(obj.promptAxes_, ...
                linspace(-1, 1, obj.promptLength_+1), [-1, 1], -1); 

            % Prompt text
            obj.promptText_ = text(obj.promptAxes_, 0, 0, "", ...
                'FontSize', 18, ...
                'Margin', 0.01, ...
                'FontWeight', 'bold', ...
                'FontName', 'Consolas', ...
                'VerticalAlignment','middle', ...
                'HorizontalAlignment', 'center', ...
                'Color', 'white');
            
            % Input text area
            obj.inputBox_ = uitextarea(obj.mainGridLayout_, ...
                'FontName', 'Consolas', ...
                'HorizontalAlignment', 'center', ...
                'Placeholder', "Enter Prompted Text", ...
                'BusyAction', 'cancel', ...
                'FontSize', 18, ...
                'ValueChangingFcn', @(src,evt)obj.onInputChange(src,evt));
            obj.inputBox_.Layout.Row = 2;
            obj.inputBox_.Layout.Column = 1;
            drawnow();
            obj.inputBox_.java.focus();
        end

        function initializeUDP_(obj, port)
            
            obj.udpObj_ = udpport("IPV4", ...
                                  "LocalPort", port, ...
                                  "EnablePortSharing", true);
            obj.udpObj_.UserData = struct("NumErrors", 0);
            obj.udpObj_.Tag = "Prompter UDP Receiver";
            obj.udpObj_.configureCallback("terminator", @(src, event)onMessageReceived(obj, src, event));
            % obj.udpObj_.ErrorOccurredFcn = @(src,evt)typewriter.Prompter.handleJsonError(src, evt);
        end
    end

    methods (Static)
        function handleJsonError(src, evt)
            me = evt.Error;
            warning(me.identifier, "Error during JSON UDP-handling: %s", me.message);
            src.NumErrors = src.NumErrors + 1;
        end

        function write(fid, ts, datum)
            %WRITE Logs a single record to the binary file.
            % Input:
            %   fid - File ID to write to
            %   ts - A single-precision relative timestamp (seconds since
            %           some main alignment timestamp).
            %   datum - A single character from an input keystroke.
        
            % Write the relative timestamp and uint8 value to the binary file
            fwrite(fid, ts, 'single');
            fwrite(fid, datum, 'uint8');
        end

        function dataTable = read(fileName)
            %READ Reads a binary log file and returns a table of records.
            % Input:
            %   fileName - Name of the binary file to read.
            % Output:
            %   dataTable - A table with columns:
            %               - .Time: Relative timestamps (single precision).
            %               - .Keystroke: Characters corresponding to uint8 values.
    
            % Open the file for reading
            fileID = fopen(fileName, 'rb');
            assert(fileID > 0, 'Failed to open file.');
    
            % Initialize arrays to store data
            timestamps = [];
            keystrokes = [];
    
            try
                % Read the file until the end
                while ~feof(fileID)
                    % Read a single-precision timestamp
                    timestamp = fread(fileID, 1, 'single');
                    if isempty(timestamp)
                        break;
                    end
                    timestamps = [timestamps; timestamp]; %#ok<AGROW>
    
                    % Read the corresponding uint8 value and convert to char
                    datum = fread(fileID, 1, 'uint8');
                    if isempty(datum)
                        break;
                    end
                    keystrokes = [keystrokes; char(datum)]; %#ok<AGROW>
                end
            catch ME
                fclose(fileID);
                rethrow(ME);
            end
    
            % Close the file
            fclose(fileID);
    
            % Return the data as a table
            dataTable = table(timestamps, keystrokes, ...
                              'VariableNames', {'Time', 'Keystroke'});
        end

        infoContent = estimateWordInformation(phrases);
        infoPerToken = estimateInformationPerToken(phrases);
    end
end
