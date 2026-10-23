classdef (Abstract) Instrument < handle
%INSTRUMENT Abstract interface to a bit-error-rate test setup.
%
%   THIS CLASS IS THE POINT OF THE FRAMEWORK. Every sweep, every plot and
%   every statistical stopping rule in this repository is written against
%   this interface and never against the simulator directly. The DUT sits
%   behind it.
%
%   The consequence is that moving from pre-silicon to a real bench is a
%   backend swap, not a rewrite:
%
%       b = harness.SimBackend();       % behavioral model, today
%       b = harness.VisaBackend(rsrc);  % SCPI instruments, once silicon exists
%
%   and analysis.shmoo, analysis.bathtub and the rest are untouched. That
%   separation is ordinary practice in silicon validation, and it is the
%   reason a validation framework tends to outlive the chip it was first
%   written for.
%
%   Required methods:
%     configure(obj, cfg)      apply an operating point
%     res = runBurst(obj, n)   transmit n bits, return errors observed
%     v   = query(obj, name)   read back a measured quantity
%
%   See also harness.SimBackend, harness.VisaBackend, harness.measureBER.

    properties (SetAccess = protected)
        name = 'unnamed';
        lastConfig = struct();
    end

    methods (Abstract)
        configure(obj, cfg)
        res = runBurst(obj, nbits)
        v   = query(obj, name)
    end

    methods
        function describe(obj)
            fprintf('Instrument backend: %s\n', obj.name);
        end
    end
end
