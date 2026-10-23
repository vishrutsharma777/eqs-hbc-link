classdef VisaBackend < harness.Instrument
%VISABACKEND Bench backend for real silicon. DELIBERATELY UNIMPLEMENTED.
%
%   This class exists to pin down the interface contract, not to pretend to
%   drive hardware that was never connected. Every method raises a clear
%   error naming the SCPI exchange it would perform.
%
%   HONESTY NOTE, AND IT IS THE IMPORTANT ONE: no measurement anywhere in
%   this repository was taken on an instrument. All results are pre-silicon,
%   produced by the behavioral model behind harness.SimBackend. This file is
%   the migration path, written so that nothing in +analysis needs editing
%   when a bench does become available.
%
%   Intended wiring for an OOK/Manchester EQS-HBC link:
%     - Arbitrary waveform generator -> TX electrode, amplitude = Vdd
%     - Oscilloscope or BERT         -> RX electrode via a high-Z active probe
%     - Programmable supply          -> DUT rail, swept by analysis.shmoo
%
%   The high-impedance probe is not a refinement, it is a precondition:
%   probing an EQS-HBC node with a standard 50-ohm input loads the channel by
%   roughly 43 dB and destroys the signal being measured. That number is not
%   a rule of thumb here, it falls out of dut.eqsChannel, and it is the same
%   effect that makes high-Z termination the whole design story for this
%   class of link.
%
%   See also harness.Instrument, harness.SimBackend, dut.eqsChannel.

    properties
        resource = '';
        visaObj  = [];
    end

    methods
        function obj = VisaBackend(resource)
            if nargin < 1, resource = 'TCPIP0::0.0.0.0::inst0::INSTR'; end
            obj.name     = 'VisaBackend (STUB - no hardware attached)';
            obj.resource = resource;
        end

        function configure(obj, cfg)
            obj.notImplemented(sprintf( ...
                ':SOUR:FUNC ARB; :SOUR:VOLT %g; :SOUR:FREQ %g; :TRIG:SOUR EXT', ...
                cfg.Vdd, cfg.Rb));
        end

        function res = runBurst(obj, nbits)  %#ok<STOUT>
            obj.notImplemented(sprintf( ...
                [':MEAS:BER:STAR; (acquire %d bits); :MEAS:BER:ERR? ' ...
                 '-- score the captured stream with the self-synchronising ' ...
                 'checker, since the transmitted bits are not available on ' ...
                 'the receive side of a real link'], nbits));
        end

        function v = query(obj, name)  %#ok<STOUT>
            obj.notImplemented(sprintf(':MEAS:%s?', upper(name)));
        end
    end

    methods (Access = private)
        function notImplemented(obj, scpi)
            error('harness:VisaBackend:notImplemented', ...
                ['VisaBackend is a stub -- no instrument is attached.\n' ...
                 'Resource : %s\n' ...
                 'Would send: %s\n' ...
                 'Use harness.SimBackend for pre-silicon runs.'], ...
                 obj.resource, scpi);
        end
    end
end
