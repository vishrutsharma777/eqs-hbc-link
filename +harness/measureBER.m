function res = measureBER(backend, cfg, opts)
%MEASUREBER Accumulate bursts until the BER claim is statistically earned.
%
%   res = harness.measureBER(backend, cfg)
%   res = harness.measureBER(backend, cfg, opts)
%
%   opts fields (all optional):
%     targetBER   pass threshold                        default 1e-4
%     confidence  confidence level for the interval     default 0.95
%     minErrors   errors sufficient for a point estimate default 30
%     maxBits     hard budget per measurement            default 3e5
%     blockBits   bits per burst                         default 2e4
%
%   Returns a struct with ber, nerr, nbits, ciLo, ciHi, pass, stopReason.
%
%   THE STOPPING RULE IS THE INTERESTING PART. A fixed bit count is the wrong
%   thing to do in both directions: it wastes time in cells that are failing
%   obviously, and it under-runs cells that are clean. So the loop exits on
%   whichever of three conditions arrives first:
%
%     'errors'  enough errors accumulated for a point estimate of useful
%               relative precision (30 errors gives roughly +/-36% at 95%)
%     'clean'   enough error-free bits that the upper confidence bound has
%               already dropped below the target -- the claim is earned and
%               running longer proves nothing further
%     'budget'  the bit budget ran out; the result is reported with whatever
%               interval it earned, and is NOT silently treated as a pass
%
%   PASS IS DECIDED ON THE UPPER CONFIDENCE BOUND, NOT THE POINT ESTIMATE.
%   Zero errors in 1e4 bits gives a point estimate of exactly 0, which would
%   pass any target at all if taken at face value; its true 95% upper bound
%   is only 3e-4. Reporting the point estimate is how a validation run claims
%   margin it never measured. The bound is the honest number.
%
%   See also harness.clopperPearson, harness.bitsRequired, harness.Instrument.

    if nargin < 3, opts = struct(); end
    opts = defaults(opts, 'targetBER',  1e-4);
    opts = defaults(opts, 'confidence', 0.95);
    opts = defaults(opts, 'minErrors',  30);
    opts = defaults(opts, 'maxBits',    3e5);
    opts = defaults(opts, 'blockBits',  2e4);

    backend.configure(cfg);

    nErr = 0;
    nBit = 0;
    eyeAcc = [];
    needClean = harness.bitsRequired(opts.targetBER, opts.confidence);
    stopReason = 'budget';

    while nBit < opts.maxBits
        blk = min(opts.blockBits, opts.maxBits - nBit);
        r   = backend.runBurst(blk);

        nErr = nErr + r.nerr;
        nBit = nBit + r.nbits;
        if isempty(eyeAcc) && isfield(r, 'eye'), eyeAcc = r.eye; end

        if nErr >= opts.minErrors
            stopReason = 'errors';
            break
        end
        if nErr == 0 && nBit >= needClean
            stopReason = 'clean';
            break
        end
    end

    [lo, hi] = harness.clopperPearson(nErr, nBit, 1 - opts.confidence);

    res.ber        = nErr / nBit;
    res.nerr       = nErr;
    res.nbits      = nBit;
    res.ciLo       = lo;
    res.ciHi       = hi;
    res.pass       = hi < opts.targetBER;
    res.targetBER  = opts.targetBER;
    res.stopReason = stopReason;
    res.eye        = eyeAcc;
end

% ---------------------------------------------------------------------------
function s = defaults(s, field, value)
    if ~isfield(s, field) || isempty(s.(field))
        s.(field) = value;
    end
end
