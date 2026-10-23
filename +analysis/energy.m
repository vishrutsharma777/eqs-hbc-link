function R = energy(varargin)
%ENERGY Energy per bit vs data rate, benchmarked against Wi-R and BLE.
%
%   R = analysis.energy()
%
%   Combines a transparent power model with the pass/fail result from the
%   link measurement, so the reported energy per bit is only credited at
%   operating points that actually meet the BER target. Energy numbers taken
%   from a link that does not close are not a result.
%
%   POWER MODEL -- these are ASSUMED DESIGN CONSTANTS, not measurements, and
%   are the one place in this framework where numbers were chosen rather than
%   derived or cited:
%
%     P_tx  = alpha * C_load * Vdd^2 * 2 * Rb    dynamic drive of the
%                                                electrode, 2*Rb because
%                                                Manchester has two
%                                                half-symbols per bit
%     P_rx  = P_bias                             static analog front-end bias
%     E_bit = (P_tx + P_rx) / Rb
%
%   which expands to  E_bit = P_bias/Rb + 2*alpha*C_load*Vdd^2.
%
%   The shape that falls out is the reason low-power radios care about this
%   plot: the static term dominates at low rate and falls as 1/Rb, while the
%   dynamic term is a floor independent of rate. Energy per bit therefore
%   improves with data rate until it flattens onto the switching floor.
%   Running a link slowly is not free -- it is the most expensive way to move
%   a bit.
%
%   REFERENCE POINTS (published, for scale):
%     Wi-R        ~0.2 nJ/bit, roadmap below 100 pJ/bit
%     BLE         ~10 nJ/bit
%
%   See also analysis.shmoo, harness.measureBER.

    ip = inputParser;
    addParameter(ip, 'Rb',          logspace(log10(50e3), log10(20e6), 16));
    addParameter(ip, 'Vdd',         1.0);
    addParameter(ip, 'corner',      'TT');
    addParameter(ip, 'interferers', 'worst');
    addParameter(ip, 'C_load',      20e-12);   % electrode + pad capacitance
    addParameter(ip, 'alpha',       0.5);      % switching activity factor
    addParameter(ip, 'P_bias',      20e-6);    % RX front-end static bias [W]
    addParameter(ip, 'targetBER',   1e-4);
    addParameter(ip, 'maxBits',     1e5);
    addParameter(ip, 'save',        true);
    parse(ip, varargin{:});
    a = ip.Results;

    b = harness.SimBackend();
    opts = struct('targetBER', a.targetBER, 'maxBits', a.maxBits, ...
                  'blockBits', 2e4, 'minErrors', 30);

    n     = numel(a.Rb);
    pass  = false(1, n);
    ber   = nan(1, n);
    Ebit  = nan(1, n);

    fprintf('energy: %d rates at Vdd = %.2f V\n', n, a.Vdd);
    for i = 1:n
        cfg = dut.linkConfig('Rb', a.Rb(i), 'Vdd', a.Vdd, ...
                             'corner', a.corner, 'interferers', a.interferers);
        r = harness.measureBER(b, cfg, opts);
        pass(i) = r.pass;
        ber(i)  = r.ber;

        P_tx    = a.alpha * a.C_load * a.Vdd^2 * 2 * a.Rb(i);
        Ebit(i) = (P_tx + a.P_bias) / a.Rb(i);
    end

    Epass = Ebit;  Epass(~pass) = nan;
    [best, bi] = min(Epass);

    if isnan(best)
        fprintf('  no operating point met the BER target\n');
    else
        fprintf('  best: %.1f pJ/bit at %.3g Mb/s (BER target met)\n', ...
                best*1e12, a.Rb(bi)/1e6);
        fprintf('  vs Wi-R published 200 pJ/bit, BLE ~10000 pJ/bit\n');
    end

    R = struct('Rb', a.Rb, 'Ebit', Ebit, 'EbitPass', Epass, 'pass', pass, ...
               'ber', ber, 'best_J', best, 'best_Rb', a.Rb(min(bi,n)), 'opts', a);

    if a.save
        plotEnergy(R);
        analysis.saveResult('energy', R);
    end
end

% ---------------------------------------------------------------------------
function plotEnergy(R)
    f = figure('Visible', 'off', 'Position', [100 100 820 520]);

    loglog(R.Rb/1e6, R.Ebit*1e12, '-', 'Color', [0.6 0.6 0.6], ...
           'LineWidth', 1.2); hold on;
    loglog(R.Rb/1e6, R.EbitPass*1e12, 'o-', 'LineWidth', 2, ...
           'Color', [0.20 0.40 0.70], 'MarkerFaceColor', [0.20 0.40 0.70], ...
           'MarkerSize', 5);

    yline(200,   '--', 'Wi-R  0.2 nJ/bit (published)', ...
          'Color', [0.20 0.55 0.35], 'LineWidth', 1.4, ...
          'LabelHorizontalAlignment', 'left');
    yline(100,   ':',  'Wi-R roadmap  <100 pJ/bit', ...
          'Color', [0.20 0.55 0.35], 'LineWidth', 1.2, ...
          'LabelHorizontalAlignment', 'left');
    yline(10000, '--', 'BLE  ~10 nJ/bit', ...
          'Color', [0.70 0.25 0.25], 'LineWidth', 1.4, ...
          'LabelHorizontalAlignment', 'left');

    if ~isnan(R.best_J)
        plot(R.best_Rb/1e6, R.best_J*1e12, 'p', 'MarkerSize', 16, ...
             'MarkerFaceColor', [0.95 0.75 0.20], 'MarkerEdgeColor', 'k');
    end

    grid on;
    xlabel('data rate  [Mb/s]');
    ylabel('energy per bit  [pJ/bit]');
    title(sprintf(['Energy per bit vs data rate  (V_{dd} = %.2f V, ' ...
                   'interferers: %s)\ngrey = link fails BER target, ' ...
                   'blue = passes'], R.opts.Vdd, R.opts.interferers));
    legend({'modelled (all rates)', 'meets BER target', ...
            'Wi-R published', 'Wi-R roadmap', 'BLE', 'best passing point'}, ...
           'Location', 'northeast', 'FontSize', 8);

    analysis.savePlot(f, 'energy');
end
