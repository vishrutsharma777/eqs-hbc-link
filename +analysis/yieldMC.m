function R = yieldMC(varargin)
%YIELDMC Monte Carlo over comparator offset mismatch -> yield across corners.
%
%   R = analysis.yieldMC()
%   R = analysis.yieldMC('sigmaOffset',4e-3,'nSamples',200)
%
%   The corners in dut.corners carry SYSTEMATIC process skew. Real parts also
%   carry RANDOM device mismatch, which for a comparator shows up as an input
%   offset that differs die to die. This sweep draws that offset from
%   N(corner_systematic, sigmaOffset) and measures the fraction of dies that
%   still meet the BER target -- that fraction is the yield.
%
%   Why it matters here: comparator offset competes directly with the
%   received amplitude, and after 45 dB of body-channel loss that amplitude
%   is only a few millivolts. An offset spread of a few mV is therefore not a
%   second-order effect, it is comparable to the whole signal. This analysis
%   is what turns "the link works" into "the link works on enough parts to
%   ship", which is the question a validation report has to answer.
%
%   Yield is reported with a Clopper-Pearson interval too, because a yield
%   estimated from a few hundred Monte Carlo draws is itself a measurement
%   with finite precision, and quoting it bare would overstate what was run.
%
%   See also dut.corners, analysis.shmoo, harness.clopperPearson.

    ip = inputParser;
    addParameter(ip, 'sigmaOffset', 3e-3);     % 1-sigma random offset [V]
    addParameter(ip, 'nSamples',    120);
    addParameter(ip, 'corners',     {'SS','TT','FF'});
    addParameter(ip, 'Rb',          2e6);
    addParameter(ip, 'Vdd',         1.0);
    addParameter(ip, 'interferers', 'worst');
    addParameter(ip, 'targetBER',   1e-4);
    addParameter(ip, 'maxBits',     6e4);
    addParameter(ip, 'seed',        7);
    addParameter(ip, 'save',        true);
    parse(ip, varargin{:});
    a = ip.Results;

    b = harness.SimBackend();
    opts = struct('targetBER', a.targetBER, 'maxBits', a.maxBits, ...
                  'blockBits', 2e4, 'minErrors', 30);

    nC = numel(a.corners);
    yieldPct = nan(1, nC);
    yLo = nan(1, nC); yHi = nan(1, nC);
    offsets = nan(nC, a.nSamples);
    passed  = false(nC, a.nSamples);

    rng(a.seed);
    fprintf('yieldMC: %d dies x %d corners, sigma_offset = %.1f mV\n', ...
            a.nSamples, nC, a.sigmaOffset*1e3);

    for ci = 1:nC
        vos = a.sigmaOffset * randn(1, a.nSamples);
        offsets(ci,:) = vos;
        for k = 1:a.nSamples
            cfg = dut.linkConfig('Rb', a.Rb, 'Vdd', a.Vdd, ...
                                 'corner', a.corners{ci}, ...
                                 'interferers', a.interferers, ...
                                 'compOffset', vos(k));
            r = harness.measureBER(b, cfg, opts);
            passed(ci,k) = r.pass;
        end
        k = sum(passed(ci,:));
        [yLo(ci), yHi(ci)] = harness.clopperPearson(k, a.nSamples);
        yieldPct(ci) = 100 * k / a.nSamples;
        fprintf('  %s: yield %.1f%%  95%% CI [%.1f %.1f]\n', ...
                a.corners{ci}, yieldPct(ci), yLo(ci)*100, yHi(ci)*100);
    end

    R = struct('corners', {a.corners}, 'yieldPct', yieldPct, ...
               'ciLo', yLo*100, 'ciHi', yHi*100, 'offsets', offsets, ...
               'passed', passed, 'opts', a);

    if a.save
        plotYield(R);
        analysis.saveResult('yieldMC', R);
    end
end

% ---------------------------------------------------------------------------
function plotYield(R)
    f = figure('Visible', 'off', 'Position', [100 100 960 430]);

    % --- Panel 1: yield with confidence intervals ------------------------
    subplot(1,2,1);
    x = 1:numel(R.corners);
    bar(x, R.yieldPct, 0.55, 'FaceColor', [0.35 0.55 0.75]); hold on;
    errorbar(x, R.yieldPct, R.yieldPct - R.ciLo, R.ciHi - R.yieldPct, ...
             'k', 'LineStyle', 'none', 'LineWidth', 1.4, 'CapSize', 12);
    set(gca, 'XTick', x, 'XTickLabel', R.corners);
    ylabel('yield  [%]');
    xlabel('process corner');
    ylim([0 105]); grid on;
    title(sprintf('Yield vs corner  (\\sigma_{os} = %.1f mV, n = %d dies)', ...
                  R.opts.sigmaOffset*1e3, R.opts.nSamples));

    % --- Panel 2: which dies failed, against their offset -----------------
    subplot(1,2,2);
    cols = lines(numel(R.corners));
    for ci = 1:numel(R.corners)
        o = R.offsets(ci,:)*1e3;
        p = R.passed(ci,:);
        scatter(o(p),  ci + 0.10*randn(1,sum(p)),  18, cols(ci,:), 'filled', ...
                'MarkerFaceAlpha', 0.55); hold on;
        scatter(o(~p), ci + 0.10*randn(1,sum(~p)), 26, [0.75 0.2 0.2], 'x', ...
                'LineWidth', 1.1);
    end
    set(gca, 'YTick', 1:numel(R.corners), 'YTickLabel', R.corners);
    xlabel('random comparator offset  [mV]');
    ylabel('corner');
    grid on;
    title('per-die outcome   (x = failed)');

    analysis.savePlot(f, 'yieldMC');
end
