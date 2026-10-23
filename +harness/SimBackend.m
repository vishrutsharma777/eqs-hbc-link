classdef SimBackend < harness.Instrument
%SIMBACKEND Pre-silicon backend: the behavioral EQS-HBC link model.
%
%   b = harness.SimBackend();
%   b.configure(dut.linkConfig('Rb', 2e6, 'Vdd', 0.9));
%   r = b.runBurst(1e5);      % -> struct with nerr, nbits, eye
%
%   Bursts are generated as PRBS by the C engine and scored with the C
%   'compare' op, which carries no self-synchronising error multiplication
%   because the transmitted stream is known on this side. On real silicon it
%   will not be, which is what the 'check' path in VisaBackend is for.
%
%   Each burst advances the seed, so accumulating blocks in
%   harness.measureBER are independent draws rather than a repeat of the
%   same noise realisation. Runs remain reproducible because the sequence of
%   seeds is a deterministic function of cfg.seed.
%
%   See also harness.Instrument, harness.VisaBackend, dut.linkSim.

    properties
        cfg
        prbsOrder = 9;
        burstSeed = 0;
    end

    methods
        function obj = SimBackend(cfg)
            if nargin < 1 || isempty(cfg), cfg = dut.linkConfig(); end
            obj.name = 'SimBackend (behavioral EQS-HBC model)';
            obj.cfg  = cfg;
        end

        function configure(obj, cfg)
            obj.cfg = cfg;
            obj.lastConfig = cfg;
            obj.burstSeed = 0;
        end

        function res = runBurst(obj, nbits)
            obj.burstSeed = obj.burstSeed + 1;
            seed = obj.cfg.seed + obj.burstSeed;

            tx = ber_core('gen', obj.prbsOrder, nbits, ...
                          mod(seed, 2^obj.prbsOrder - 1) + 1);
            [rx, diag] = dut.linkSim(tx, obj.cfg, seed);

            res.nerr  = ber_core('compare', tx, uint8(rx));
            res.nbits = nbits;
            res.eye   = diag.eye;
            res.diag  = diag;
        end

        function v = query(obj, name)
            switch lower(name)
                case 'channelloss_db'
                    v = 20*log10(abs(dut.eqsChannel(obj.cfg.Rb, obj.cfg.chan)));
                case 'samplerate'
                    v = obj.cfg.fs;
                case 'bitrate'
                    v = obj.cfg.Rb;
                case 'vdd'
                    v = obj.cfg.Vdd;
                otherwise
                    error('harness:SimBackend:query', ...
                          'Unknown quantity "%s".', name);
            end
        end
    end
end
