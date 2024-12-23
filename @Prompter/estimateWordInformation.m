function infoPerWord = estimateWordInformation(phrases)
% Estimate the average information content per word for a set of phrases.
%
% Syntax:
%   infoPerWord = typewriter.Prompter.estimateWordInformation(phrases);
%
% Input:
%   phrases - Cell array of strings (e.g., obj.phrases_)
%
% Output:
%   infoPerWord - Estimated information content per word in bits
%
% Example:
%   phrases = {
%       'hello world', 
%       'this is a typing prompt', 
%       'welcome to the typing interface'
%   };
%   infoContent = typewriter.Prompter.estimateWordInformation(phrases);

if isstring(phrases)
    phrases = cellstr(phrases);
end

% Concatenate all phrases into a single string
fullText = strjoin(phrases, ' ');

% Calculate the frequency of each character
chars = unique(fullText);
charCounts = arrayfun(@(c) sum(fullText == c), chars);
totalChars = sum(charCounts);

% Probability of each character
charProbs = charCounts / totalChars;

% Calculate Shannon entropy (in bits) for the character distribution
entropyBits = -sum(charProbs .* log2(charProbs));

% Calculate the average word length
words = split(fullText);
avgWordLength = mean(strlength(words));

% Estimate information per word
infoPerWord = entropyBits * avgWordLength;
end
