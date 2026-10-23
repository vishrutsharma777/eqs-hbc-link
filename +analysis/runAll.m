function runAll(varargin)
%RUNALL Regenerate every result and figure in results/ from scratch.
%
%   analysis.runAll            full run
%   analysis.runAll('quick',true)   coarser grids, for a smoke test
%
%   Order is deliberate. The model check runs FIRST, because if the link
%   model does not reproduce the closed-form BER curve then nothing after it
%   is worth generating.
%
%   Every figure is produced from a fixed seed, so the suite is reproducible:
%   a reader who runs this gets the numbers in the report, not numbers like
%   the ones in the report.
%
%   See also analysis.berVsTheory, analysis.shmoo, analysis.bathtub.

    ip = inputParser;
    addParameter(ip, 'quick', false);
    parse(ip, varargin{:});
    quick = ip.Results.quick;

    t0 = tic;
    fprintf('==============================================================\n');
    fprintf(' Wi-R pre-silicon validation suite\n');
    fprintf(' started %s\n', datetime('now','Format','yyyy-MM-dd HH:mm:ss'));
    fprintf('==============================================================\n\n');

    if quick
        nShmoo = 8;  nPhase = 13; nSens = 12; nRate = 10; nDie = 40;
        maxBits = 6e4; nTheoryBits = 2e5;
    else
        nShmoo = 12; nPhase = 25; nSens = 20; nRate = 16; nDie = 120;
        maxBits = 1e5; nTheoryBits = 4e5;
    end

    step(1, 'model check: BER vs theory');
    analysis.berVsTheory('nBits', nTheoryBits);

    step(2, 'body channel: termination and ground plane');
    analysis.channelPlot();

    step(3, 'shmoo: Vdd vs data rate');
    analysis.shmoo('Vdd', linspace(0.1, 1.2, nShmoo), ...
                   'Rb',  logspace(log10(50e3), log10(20e6), nShmoo), ...
                   'maxBits', maxBits);

    step(4, 'bathtub and eye: timing margin');
    analysis.bathtub('phases', linspace(-0.45, 0.45, nPhase), ...
                     'maxBits', maxBits);

    step(5, 'sensitivity vs interference environment');
    analysis.sensitivity('Vdd', logspace(log10(4e-4), log10(12), nSens), ...
                         'maxBits', maxBits);

    step(6, 'energy per bit vs data rate');
    analysis.energy('Rb', logspace(log10(50e3), log10(20e6), nRate), ...
                    'maxBits', maxBits);

    step(7, 'Monte Carlo yield across corners');
    analysis.yieldMC('nSamples', nDie, 'maxBits', maxBits);

    fprintf('\n==============================================================\n');
    fprintf(' complete in %.1f min -- see results/\n', toc(t0)/60);
    fprintf('==============================================================\n');
end

% ---------------------------------------------------------------------------
function step(n, what)
    fprintf('\n--- [%d/7] %s %s\n', n, what, repmat('-', 1, max(0, 46-numel(what))));
end
