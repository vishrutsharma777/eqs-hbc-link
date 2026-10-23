function n = bitsRequired(targetBER, confidence)
%BITSREQUIRED Bits needed to demonstrate BER < target, observing zero errors.
%
%   n = harness.bitsRequired(1e-6)          95% confidence
%   n = harness.bitsRequired(1e-6, 0.99)
%
%   This is the question that sets the runtime of every BER measurement in
%   this framework: how long must the link run clean before the claim "the
%   error rate is below X" is actually earned?
%
%   With zero errors in n trials the one-sided exact upper bound on the error
%   probability is 1 - alpha^(1/n). Setting that equal to the target and
%   solving gives
%
%       n = log(alpha) / log(1 - targetBER)
%
%   which for small targets reduces to the familiar rule of three: about
%   3/target bits at 95% confidence, so 3e6 bits to claim BER < 1e-6 and
%   3e9 to claim BER < 1e-9.
%
%   The practical consequence, and the reason the BER engine is written in C:
%   a full shmoo at 1e-6 confidence is tens of billions of simulated bits.
%
%   See also harness.clopperPearson, harness.measureBER.

    if nargin < 2 || isempty(confidence), confidence = 0.95; end
    validateattributes(targetBER,  {'numeric'}, {'scalar','positive','<',1});
    validateattributes(confidence, {'numeric'}, {'scalar','positive','<',1});

    alpha = 1 - confidence;
    n = ceil(log(alpha) / log(1 - targetBER));
end
