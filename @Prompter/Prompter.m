classdef Prompter < handle
    events
        PromptComplete
    end
    properties
        Figure
        advanceOnComplete (1,1) logical = false;
    end

    properties (GetAccess = public, SetAccess = protected)
        udpObj_  % UDP port object
        prompt_   % Current prompt
        phrases_  % List of phrases_
        phraseIndex_ (1,1) double = 0 % Current phrase index.
        promptLength_ (1,1) double = 1 % Current prompt length.
        promptWords_ (1,1) double = 0;
        startTic_ (1,1) uint64 = tic;
        wpm (:,1) = [];
    end

    properties (Constant, Access = private)
        DEFAULT_PHRASES_FILE {mustBeTextScalar} = "config/phrases.txt";
    end
    
    properties (Hidden, Access = public)
        mainGridLayout_  % UI container for UI text elements
        rightSideGridLayout_  % UI container for HUD on the right side
        wpmLabel_ % HUD indicator for words per minute
        startStopButton_ % UI Button
        promptAxes_  % UI axes container for promptText_ and promptBackground_
        promptText_  % Text on uiaxes indicating prompt to type
        promptBackground_ % Color behind each letter, displayed on promptAxes_
        inputBox_    % UI element for text input
    end

    methods
        % Constructor
        function obj = Prompter(options)
            arguments
                options.Port (1,1) {mustBeInteger} = 7053;
                options.PhrasesFile {mustBeTextScalar} = "";
                options.AutoAdvanceOnComplete (1,1) logical = false;
            end

            % Initialize UDP
            obj.udpObj_ = udpport("datagram", "IPV4", ...
                                  "LocalPort", options.Port, ...
                                  "EnablePortSharing", true);
            obj.udpObj_.DatagramReceivedFcn = @(src, event) obj.onDatagramReceived(src, event);

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
                obj.loadphrases_(defaultPhrasesFile);
            else
                warning("Default phrases file not found: %s", defaultPhrasesFile);
                obj.phrases_ = {};
            end
            
            % Initialize Figure
            obj.phraseIndex_ = randi(numel(obj.phrases_), 1, 1);
            obj.initializeFigure(folderPath);
            obj.loadNext();
            drawnow();
            obj.updatePrompt(obj.prompt_);
            obj.startTic_ = tic;
        end
        
        % Initialize the GUI Figure
        function initializeFigure(obj, rootFolder)
            obj.Figure = uifigure('Name', 'Prompter', ...
                'Position', [100, 100, 600, 200], ...
                'Color', 'w', ...
                'Icon', fullfile(rootFolder, 'TypeWriterIcon.png'), ...
                'DeleteFcn', @(src,evt)obj.handleWindowClosing, ...
                'WindowStyle', 'alwaysontop');

            obj.mainGridLayout_ = uigridlayout(obj.Figure, ...
                'ColumnWidth', {'3x', '1x'}, ...
                'RowHeight', {'3x', '1x'}, ...
                'BackgroundColor', 'w');

            obj.rightSideGridLayout_ = uigridlayout(obj.mainGridLayout_, ...
                'ColumnWidth', {'1x'}, ...
                'RowHeight',{'3x', '3x', '1x'}, ...
                'BackgroundColor', [0.65 0.65 0.65]);
            obj.rightSideGridLayout_.Layout.Column = 2;
            obj.rightSideGridLayout_.Layout.Row = [1 2];
            h = uilabel(obj.rightSideGridLayout_, 'Text', "Words/Minute", ...
                'FontName','Tahoma','FontSize', 12,'HorizontalAlignment','center');
            h.Layout.Row = 3;
            h.Layout.Column = 1;
            obj.wpmLabel_ = uilabel(obj.rightSideGridLayout_, 'Text', "0.0", ...
                'FontName','Tahoma','FontSize',18,'FontWeight','bold','FontColor','k','HorizontalAlignment','center');
            obj.wpmLabel_.Layout.Row = 2;
            obj.wpmLabel_.Layout.Column = 1;

            obj.startStopButton_ = uibutton(obj.rightSideGridLayout_, ...
                'Text', "Pause", ...
                'FontName', 'Tahoma', ...
                'FontSize', 14, ...
                'ButtonPushedFcn', @(src,evt)obj.handlePause());
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
        
        
        
        function handlePause(obj)
            obj.startStopButton_.Text = "Start";
            obj.startStopButton_.ButtonPushedFcn = @(src,evt)obj.handleStart();
            obj.updatePrompt("");
            obj.deferClearInputBox();
            pause(0.15);
            obj.inputBox_.Editable = matlab.lang.OnOffSwitchState.off;
        end

        function handleStart(obj)
            obj.startStopButton_.Text = "Pause";
            obj.startStopButton_.ButtonPushedFcn = @(src,evt)obj.handlePause();
            obj.inputBox_.Editable = matlab.lang.OnOffSwitchState.on;
            obj.loadSpecific(randi(numel(obj.phrases_),1,1));
            obj.inputBox_.java.focus();
        end

        function handleWindowClosing(obj, src, ~)
            src.DeleteFcn = [];
            try %#ok<TRYNC>
                delete(src);
            end
            delete(obj);
            disp("Prompter deleted.");
        end

        % Load the next phrase
        function loadNext(obj)
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
            if index >= 1 && index <= numel(obj.phrases_)
                phrase = obj.phrases_{index};
                obj.phraseIndex_ = index;
                obj.updatePrompt(phrase);
                obj.startTic_ = tic;
            else
                warning('Index out of bounds.');
            end
        end
        
        % Update the prompt text
        function updatePrompt(obj, phrase)
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

        function clearInputBox(obj, src)
            try
                obj.Figure.CurrentObject = obj.promptAxes_;
                drawnow();

                % Set the Value to an empty cell array (uitable expects a cell array of strings)
                obj.recreateInputBox();
                pause(0.01);
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
                      'StartDelay', 0.05, ... % Delay slightly to let UI settle
                      'Period', 0.05, ...
                      'TimerFcn', @(src,~)obj.clearInputBox(src));
            start(t);
        end

        function recreateInputBox(obj)
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

        function onInputChange(obj, src, evt)
            input = char(evt.Value);
            if strlength(input) == 0
                src.Value = evt.Value;
                return;
            end
            correct = 0;
            for i = 1:min(strlength(input), obj.promptLength_)
                if strcmpi(input(i),obj.prompt_(i))
                    obj.promptBackground_.CData(i) = 1; % Correct: Blue
                    correct = correct + 1;
                else
                    obj.promptBackground_.CData(i) = 0; % Incorrect: Red
                end
            end
            % disp(correct);
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

        function updateStats(obj)
            ttrial = toc(obj.startTic_) / 60;
            obj.wpm(end+1) = obj.promptWords_ / ttrial;
            cur_wpm = round(mean(obj.wpm),1);
            obj.wpmLabel_.Text = sprintf("%.1f", cur_wpm);
            fprintf(1,"Averaging %.1f words/minute (N = %d).\n",cur_wpm,numel(obj.wpm));
        end

        
        % Datagram received callback
        function onDatagramReceived(obj, src, event)
            data = char(read(src, event.DatagramLength));
            try
                msg = jsondecode(data);
                if isfield(msg, 'type') && strcmp(msg.type, 'Method')
                    obj.handleMethod(msg);
                else
                    warning("Unknown message type received.");
                end
            catch ME
                warning(ME.identifier, "Failed to process incoming message: %s", ME.message);
            end
        end

        % Handle methods
        function handleMethod(obj, msg)
            if isfield(msg, 'method') % Use less handling here to speed up by allowing message to be sent as int8 field.
                switch typewriter.PrompterMethod(msg.method)
                    case typewriter.PrompterMethod.LoadNext
                        obj.loadNext();
                    case typewriter.PrompterMethod.LoadSpecific
                        obj.loadSpecific(msg.index);
                    case typewriter.PrompterMethod.Loadphrases_
                        obj.loadphrases_(msg.filepath);
                    case typewriter.PrompterMethod.AddPhrase
                        obj.addPhrase(msg.phrase);
                    case typewriter.PrompterMethod.RemovePhrase
                        obj.removePhrase(msg.index);
                    case typewriter.PrompterMethod.Savephrases_
                        obj.savephrases_(msg.filepath);
                    otherwise
                        warning("Unhandled method: %s", msg.method);
                end
            else
                warning("Invalid or missing method field in message.");
            end
        end
        
        function loadphrases_(obj, filepath)
            % Load phrases from the specified file
            if isfile(filepath)
                obj.phrases_ = strtrim(readlines(filepath));
                obj.phrases_ = obj.phrases_(cellfun(@(c)strlength(c)>0,obj.phrases_));
                obj.phraseIndex_ = 1; % Reset phrase index
            else
                error("File not found: %s", filepath);
            end
        end
        
        function addPhrase(obj, phrase)
            % Logic to add a phrase
            obj.phrases_{end+1} = phrase;
        end
        
        function removePhrase(obj, index)
            % Logic to remove a phrase by index
            obj.phrases_(index) = [];
        end
        
        function savephrases_(obj, filepath)
            % Logic to save phrases_ to a file
            writelines(obj.phrases_, filepath);
        end
    end
end
