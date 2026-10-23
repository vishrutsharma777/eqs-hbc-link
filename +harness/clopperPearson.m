function [lo, hi] = clopperPearson(k, n, alpha)
%CLOPPERPEARSON Exact binomial confidence interval for a measured BER.
%
%   [lo, hi] = harness.clopperPearson(k, n)          95% two-sided
%   [lo, hi] = harness.clopperPearson(k, n, alpha)
%
%   k errors observed in n trials. Returns the exact (Clopper-Pearson)
%   interval on the underlying error probability.
%
%   WHY EXACT AND NOT NORMAL-APPROXIMATE: a validation measurement lives in
%   the regime where the normal approximation fails hardest -- few or zero
%   errors out of very many bits. With k = 0 the Wald interval collapses to
%   the degenerate [0, 0], which would license reporting "BER = 0" from a run
%   that in truth only bounds BER below about 3/n. Clopper-Pearson is
%   conservative and stays correct at k = 0, which is the case that matters
%   most, because a passing validation run is precisely the one with no
%   errors in it.
%
%   Uses core MATLAB betaincinv, so this carries no toolbox dependency.
%
%   See also harness.bitsRequired, harness.measureBER.

    if nargin < 3 || isempty(alpha), alpha = 0.05; end
    validateattributes(k, {'numeric'}, {'scalar','nonnegative','integer'});
    validateattributes(n, {'numeric'}, {'scalar','positive','integer'});
    if k > n
        error('harness:clopperPearson:kGtN', 'k (%d) cannot exceed n (%d).', k, n);
    end

    if k == 0
        lo = 0;
    else
        lo = betaincinv(alpha/2, k, n-k+1);
    end

    if k == n
        hi = 1;
    else
        hi = betaincinv(1-alpha/2, k+1, n-k);
    end
end
