function R = shmoo(varargin)
%SHMOO Supply voltage vs data rate pass/fail map -- the signature validation plot.
%
%   R = analysis.shmoo()
%   R = analysis.shmoo('interferers','worst','corner','SS')
%
%   Sweeps Vdd against bit rate, running a statistically-terminated BER
%   measurement at every cell, and renders the pass/fail region. A shmoo is
%   the first thing a validation engineer produces for a new part because it
%   answers the only question that matters at bring-up: over what operating
%   box does this thing actually work?
%
%   Each cell is a pass only if the UPPER 95% confidence bound on its BER
%   sits below the target. Cells that merely ran out of bit budget without
%   accumulating errors are not passes, and are marked separately.
%
%   WHAT TO LOOK FOR: with interference enabled the failing region is not a
%   simple low-voltage corner. There is also a low-DATA-RATE wall, because
%   Manchester differential detection rejects an interferer only while the
%   interferer sits well below the signalling rate. As the bit rate falls
%   toward the 48 kHz CFL tone the rejection collapses. That wall, not
%   thermal noise, is what sets the minimum usable rate of an EQS-HBC link.
%
%   See also analysis.bathtub, analysis.sensitivity, harness.measureBER.

    ip = inputParser;
    addParameter(ip, 'Vdd',  linspace(0.1, 1.2, 12));
    addParameter(ip, 'Rb',   logspace(log10(50e3), log10(20e6), 12));
    addParameter(ip, 'corner',      'TT');
    addParameter(ip, 'interferers', 'worst');
    addParameter(ip, 'targetBER',   1e-4);
    addParameter(ip, 'maxBits',     1e5);
    addParameter(ip, 'save',        true);
    parse(ip, varargin{:});
    a = ip.Results;

    b  = harness.SimBackend();
    nV = numel(a.Vdd);
    nR = numel(a.Rb);

    pass  = false(nV, nR);
    ber   = nan(nV, nR);
    ciHi  = nan(nV, nR);
    stopR = strings(nV, nR);

    opts = struct('targetBER', a.targetBER, 'maxBits', a.maxBits, ...
                  'blockBits', 2e4, 'minErrors', 30);

    fprintf('shmoo: %d x %d cells, corner %s, interferers %s\n', ...
            nV, nR, a.corner, a.interferers);
    for i = 1:nV
        for j = 1:nR
            cfg = dut.linkConfig('Vdd', a.Vdd(i), 'Rb', a.Rb(j), ...
                                 'corner', a.corner, ...
                                 'interferers', a.interferers);
            r = harness.measureBER(b, cfg, opts);
            pass(i,j)  = r.pass;
            ber(i,j)   = r.ber;
            ciHi(i,j)  = r.ciHi;
            stopR(i,j) = r.stopReason;
        end
        fprintf('  Vdd = %.2f V : %s\n', a.Vdd(i), ...
                strjoin(cellstr(char(pass(i,:)*('P'-'.') + '.')), ''));
    end

    R = struct('Vdd', a.Vdd, 'Rb', a.Rb, 'pass', pass, 'ber', ber, ...
               'ciHi', ciHi, 'stopReason', stopR, 'opts', a);

    if a.save
        plotShmoo(R);
        analysis.saveResult('shmoo', R);
    end
end

% ---------------------------------------------------------------------------
function plotShmoo(R)
    f = figure('Visible', 'off', 'Position', [100 100 860 520]);

    % Three states, because "did not fail" is not the same as "passed":
    %   2 = pass, 1 = ran clean but budget-limited, 0 = fail
    state = double(R.pass) * 2;
    state(~R.pass & R.ber == 0) = 1;

    imagesc(1:numel(R.Rb), 1:numel(R.Vdd), state);
    set(gca, 'YDir', 'normal');
    colormap([0.76 0.24 0.24; 0.93 0.80 0.38; 0.22 0.56 0.33]);
    clim([0 2]);

    set(gca, 'XTick', 1:numel(R.Rb), ...
             'XTickLabel', compose('%.3g', R.Rb/1e6), ...
             'YTick', 1:numel(R.Vdd), ...
             'YTickLabel', compose('%.2f', R.Vdd));
    xlabel('bit rate  [Mb/s]');
    ylabel('V_{dd}  [V]');
    title(sprintf(['Shmoo: BER < %g at 95%% confidence   ' ...
                   '(corner %s, interferers: %s)'], ...
                   R.opts.targetBER, R.opts.corner, R.opts.interferers));

    % Cell annotation: log10 of the measured BER, dash where clean. One
    % decimal, not zero: %.0f renders every BER above 0.1 as a meaningless
    % "-0", which is exactly the badly-broken region worth reading.
    for i = 1:numel(R.Vdd)
        for j = 1:numel(R.Rb)
            if R.ber(i,j) > 0
                txt = sprintf('%.1f', log10(R.ber(i,j)));
            else
                txt = '-';
            end
            text(j, i, txt, 'HorizontalAlignment', 'center', ...
                 'FontSize', 7, 'Color', [1 1 1]*0.95);
        end
    end

    hold on;
    h(1) = patch(nan, nan, [0.22 0.56 0.33]);
    h(2) = patch(nan, nan, [0.93 0.80 0.38]);
    h(3) = patch(nan, nan, [0.76 0.24 0.24]);
    legend(h, {'pass (CI bound below target)', ...
               'clean but budget-limited', ...
               'fail'}, 'Location', 'southoutside', 'Orientation', 'horizontal');

    analysis.savePlot(f, 'shmoo');
end
