function c = corners(name)
%CORNERS PVT corner definitions for the receiver front end.
%
%   c = dut.corners(name)  with name in {'SS','TT','FF'}
%   dut.corners()          returns a struct array of all three
%
%   Corners are expressed as multipliers on the nominal RX front-end
%   parameters plus an additive comparator offset, which is how a behavioral
%   model represents process skew without a transistor-level netlist:
%
%     slow  -> less gain, less bandwidth, positive offset skew
%     fast  -> more gain, more bandwidth, negative offset skew
%
%   Offset magnitudes (+/-3 mV systematic) are the 3-sigma systematic skew;
%   random mismatch is layered on top by the Monte Carlo yield analysis,
%   which draws offset from N(c.offsetV, sigma) rather than using it fixed.
%
%   See also dut.linkConfig, analysis.yieldMC.

    all_c = struct( ...
        'name',     {'SS',  'TT',  'FF'}, ...
        'gainMult', {0.80,  1.00,  1.20}, ...
        'bwMult',   {0.70,  1.00,  1.35}, ...
        'offsetV',  {+3e-3, 0,    -3e-3}, ...
        'tempC',    {85,    27,   -20});

    if nargin < 1 || isempty(name)
        c = all_c;
        return
    end
    idx = find(strcmpi({all_c.name}, name), 1);
    if isempty(idx)
        error('dut:corners:badName', 'Unknown corner "%s".', name);
    end
    c = all_c(idx);
end
