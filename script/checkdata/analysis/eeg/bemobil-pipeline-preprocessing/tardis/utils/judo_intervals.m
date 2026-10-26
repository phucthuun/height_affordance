function out = judo_intervals(action, varargin)
%JUDO_INTERVALS  Small helpers for sample intervals [start end] (inclusive, 1-based).
%
%   iv   = judo_intervals('from_mask', mask)        logical mask -> N x 2 intervals
%   mask = judo_intervals('to_mask', iv, n)         intervals -> 1 x n logical mask
%   iv   = judo_intervals('merge', iv, n)           round, clip to [1 n], sort, merge overlapping/adjacent
%   n    = judo_intervals('count', iv)              number of samples covered (after merging)

switch action
    case 'from_mask'
        mask = logical(varargin{1}(:)');
        d = diff([false, mask, false]);
        starts = find(d == 1);
        stops  = find(d == -1) - 1;
        out = [starts(:), stops(:)];

    case 'to_mask'
        iv = varargin{1};
        n  = varargin{2};
        out = false(1, n);
        for i = 1:size(iv, 1)
            a = max(1, round(iv(i, 1)));
            b = min(n, round(iv(i, 2)));
            if b >= a
                out(a:b) = true;
            end
        end

    case 'merge'
        iv = varargin{1};
        n  = varargin{2};
        if isempty(iv)
            out = zeros(0, 2);
            return
        end
        out = judo_intervals('from_mask', judo_intervals('to_mask', iv(:, 1:2), n));

    case 'count'
        iv = varargin{1};
        if isempty(iv)
            out = 0;
        else
            out = sum(iv(:, 2) - iv(:, 1) + 1);
        end

    otherwise
        error('judo:intervals', 'Unknown action "%s".', action);
end
end
