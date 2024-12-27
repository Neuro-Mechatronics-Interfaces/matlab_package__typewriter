function infoPerToken = estimateInformationPerToken(phrases)
    % Estimates the average information content per token (word) for a set of phrases.
    %
    % Input:
    %   phrases - A string array or cell array of character vectors
    %
    % Output:
    %   infoPerToken - Average information content per token (bits)

    % Ensure phrases is a string array
    if iscell(phrases)
        phrases = string(phrases);
    end

    % Concatenate all phrases into a single string
    fullText = strjoin(phrases, ' ');

    % Split the text into tokens (words)
    tokens = split(fullText);

    % Remove empty tokens
    tokens = tokens(tokens ~= "");

    % Calculate word frequencies
    [uniqueTokens, ~, tokenIdx] = unique(tokens);
    tokenCounts = accumarray(tokenIdx, 1);
    totalTokens = sum(tokenCounts);

    % Probability of each token
    tokenProbs = tokenCounts / totalTokens;

    % Calculate Shannon entropy (in bits) for the token distribution
    entropyBits = -sum(tokenProbs .* log2(tokenProbs));

    % Return the entropy as information per token
    infoPerToken = entropyBits;
end
