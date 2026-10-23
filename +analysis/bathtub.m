function R = bathtub(varargin)
%BATHTUB BER vs sampling phase, plus the eye it came from -> timing margin.
%
%   R = analysis.bathtub()
%   R = analysis.bathtub('Rb',2e6,'jitterRmsUI',0.02)
%
%   Sweeps the sampling instant across one unit interval and measures BER at
%   each phase. The resulting curve is the bathtub: low in the middle where
%   sampling lands in the open eye, rising steeply at both edges as the
%   sampling point walks into the transitions.
%
%   The number that comes out is TIMING MARGIN: the width, in UI, of the
%   phase window over which the link still meets its BER target. That is the
%   budget a real CDR has to live inside, and it is the quantity a validation
%   engineer is actually asked for.
%
%   Reported margin is conservative in two specific ways, both deliberate:
%   it uses the upper confidence bound rather than the point estimate, and
%   it measures the contiguous window around the eye centre rather than the
%   union of every passing phase, so an isolated lucky point cannot inflate it.
%
%   See also analysis.shmoo, harness.measureBER, dut.linkSim.

    ip = inputParser;
    addParameter(ip, 'Rb',          2e6);
    addParameter(ip, 'Vdd',         1.0);
    addParameter(ip, 'corner',      'TT');
    addParameter(ip, 'interferers', 'worst');
    addParameter(ip, 'jitterRmsUI', 0.0);
    addParameter(ip, 'phases',      linspace(-0.45, 0.45, 37));
    addParameter(ip, 'targetBER',   1e-4);
    addParameter(ip, 'maxBits',     2e5);
    addParameter(ip, 'save',        true);
    parse(ip, varargin{:});
    a = ip.Results;

    b = harness.SimBackend();
    opts = struct('targetBER', a.targetBER, 'maxBits', a.maxBits, ...
                  'blockBits', 2e4, 'minErrors', 30);

    n    = numel(a.phases);
    ber  = nan(1, n);
    ciHi = nan(1, n);

    fprintf('bathtub: %d phases at Rb = %.3g Mb/s, jitter %.3g UI rms\n', ...
            n, a.Rb/1e6, a.jitterRmsUI);
    for i = 1:n
        cfg = dut.linkConfig('Rb', a.Rb, 'Vdd', a.Vdd, 'corner', a.corner, ...
                             'interferers', a.interferers, ...
                             'jitterRmsUI', a.jitterRmsUI, ...
                             'samplePhase', a.phases(i));
        r = harness.measureBER(b, cfg, opts);
        ber(i)  = r.ber;
        ciHi(i) = r.ciHi;
    end

    margin = contiguousMargin(a.phases, ciHi, a.targetBER);
    fprintf('  timing margin: %.3f UI at BER < %g (95%% bound)\n', ...
            margin, a.targetBER);

    % Capture one eye at the nominal phase for the companion panel.
    cfgEye = dut.linkConfig('Rb', a.Rb, 'Vdd', a.Vdd, 'corner', a.corner, ...
                            'interferers', a.interferers, ...
                            'jitterRmsUI', a.jitterRmsUI);
    tx = ber_core('gen', 9, 4000, 1);
    [~, d] = dut.linkSim(tx, cfgEye);

    R = struct('phases', a.phases, 'ber', ber, 'ciHi', ciHi, ...
               'margin_UI', margin, 'opts', a, ...
               'wave', d.wave, 'spb', cfgEye.spb, 'eye', d.eye);

    if a.save
        plotBathtub(R);
        analysis.saveResult('bathtub', R);
    end
end

% ---------------------------------------------------------------------------
function m = contiguousMargin(ph, ciHi, target)
%CONTIGUOUSMARGIN Width of the passing window containing the eye centre.
%   Taking the contiguous run around phase 0 rather than every passing phase
%   means a single fortunate sample far out on the skirt cannot be credited
%   as margin.
    ok = ciHi < target;
    if ~any(ok), m = 0; return; end

    [~, c] = min(abs(ph));          % index nearest the eye centre
    if ~ok(c)
        m = 0;
        return
    end
    lo = c; while lo > 1        && ok(lo-1), lo = lo - 1; end
    hi = c; while hi < numel(ok) && ok(hi+1), hi = hi + 1; end
    m = ph(hi) - ph(lo);
end

% ---------------------------------------------------------------------------
function plotBathtub(R)
    f = figure('Visible', 'off', 'Position', [100 100 1000 420]);

    % --- Panel 1: the bathtub -------------------------------------------
    subplot(1,2,1);
    floorVal = 1e-7;                 % plotting floor for zero-error points
    y  = max(R.ber,  floorVal);
    yb = max(R.ciHi, floorVal);
    semilogy(R.phases, yb, '-', 'LineWidth', 1.8, 'Color', [0.20 0.40 0.70]);
    hold on;
    semilogy(R.phases, y, 'o', 'MarkerSize', 4, ...
             'MarkerFaceColor', [0.20 0.40 0.70], 'MarkerEdgeColor', 'none');
    yline(R.opts.targetBER, '--', 'target', 'Color', [0.7 0.2 0.2], ...
          'LineWidth', 1.2);
    grid on;
    xlabel('sampling phase  [UI]');
    ylabel('BER');
    title(sprintf('Bathtub  --  margin %.3f UI', R.margin_UI));
    legend({'95% upper bound', 'point estimate', 'target'}, ...
           'Location', 'north', 'FontSize', 8);
    ylim([floorVal 1]);

    % Shade the earned margin window.
    if R.margin_UI > 0
        [~, c] = min(abs(R.phases));
        ok = R.ciHi < R.opts.targetBER;
        lo = c; while lo > 1          && ok(lo-1), lo = lo - 1; end
        hi = c; while hi < numel(ok)  && ok(hi+1), hi = hi + 1; end
        yl = ylim;
        patch([R.phases(lo) R.phases(hi) R.phases(hi) R.phases(lo)], ...
              [yl(1) yl(1) yl(2) yl(2)], [0.3 0.7 0.4], ...
              'FaceAlpha', 0.12, 'EdgeColor', 'none');
    end

    % --- Panel 2: the eye ------------------------------------------------
    subplot(1,2,2);
    spb = R.spb;
    w   = R.wave;
    nsym = floor(numel(w)/spb) - 2;
    seg  = reshape(w(spb+1 : spb+nsym*spb), spb, nsym);
    tUI  = (0:spb-1)/spb;
    plot(tUI, seg(:, 1:min(400,nsym)), 'Color', [0.20 0.40 0.70 0.06]);
    grid on;
    xlabel('time  [UI]');
    ylabel('RX output  [V]');
    title(sprintf('Eye at Rb = %.3g Mb/s (interferers: %s)', ...
                  R.opts.Rb/1e6, R.opts.interferers));

    analysis.savePlot(f, 'bathtub');
end
