function R = berVsTheory(varargin)
%BERVSTHEORY Model validation: simulated BER against the closed form.
%
%   R = analysis.berVsTheory()
%
%   THIS IS THE FIRST THING TO RUN AND THE FIRST THING TO READ. With the body
%   channel bypassed, interference off and the receiver bandwidth opened, the
%   link reduces to antipodal signalling in AWGN, whose exact bit error rate
%   is Q(sqrt(2.Eb/N0)). If the model does not reproduce that curve, then
%   every shmoo, bathtub, sensitivity and yield figure downstream is
%   measuring a bug rather than a link, and none of them mean anything.
%
%   Running this check first, and shipping it as a figure rather than only as
%   an assertion, is the difference between a simulation and a measurement
%   you can defend. tests/testBerVsTheory.m enforces the same comparison as a
%   hard tolerance.
%
%   Agreement is judged only where enough errors accumulated for the estimate
%   to be meaningful; at high Eb/N0 the simulated point is dominated by
%   Poisson counting noise and the confidence interval is plotted instead of
%   pretending the point estimate is precise.
%
%   See also dut.linkSim, harness.clopperPearson, tests/testBerVsTheory.m.

    ip = inputParser;
    addParameter(ip, 'EbN0dB',  0:1:10);
    addParameter(ip, 'nBits',   4e5);
    addParameter(ip, 'save',    true);
    parse(ip, varargin{:});
    a = ip.Results;

    n    = numel(a.EbN0dB);
    ber  = nan(1,n); lo = nan(1,n); hi = nan(1,n); th = nan(1,n);

    fprintf('berVsTheory: %d points, %g bits each\n', n, a.nBits);
    for i = 1:n
        cfg = dut.linkConfig('bypassChannel', true, 'vgaBW', Inf, ...
                             'interferers', 'none', ...
                             'EbN0dB', a.EbN0dB(i), 'seed', 1000+i);
        tx = ber_core('gen', 15, a.nBits, i+1);
        rx = dut.linkSim(tx, cfg);
        k  = ber_core('compare', tx, uint8(rx));

        ber(i) = k / a.nBits;
        [lo(i), hi(i)] = harness.clopperPearson(k, a.nBits);
        th(i)  = 0.5*erfc(sqrt(10^(a.EbN0dB(i)/10)));   % Q(sqrt(2.Eb/N0))
    end

    % THE CORRECT TEST IS CONTAINMENT, NOT PERCENTAGE DEVIATION. A point with
    % 40 errors has a 95% interval spanning roughly +/-30%, so a raw "max
    % deviation" figure mostly reports Poisson counting noise and looks
    % alarming when nothing is wrong. What actually has to hold is that the
    % theoretical value lies inside the measured interval at every point.
    inCI = (th >= lo) & (th <= hi);
    fprintf('  theory inside 95%% CI at %d/%d points\n', sum(inCI), n);

    % Kept as a secondary diagnostic, judged only where counts support it.
    solid = (ber .* a.nBits) >= 100;
    if any(solid)
        maxDev = max(abs(ber(solid)./th(solid) - 1));
        fprintf('  max deviation where >=100 errors: %.1f%% (%d points)\n', ...
                maxDev*100, sum(solid));
    else
        maxDev = NaN;
        fprintf('  no point accumulated >=100 errors\n');
    end

    R = struct('EbN0dB', a.EbN0dB, 'ber', ber, 'ciLo', lo, 'ciHi', hi, ...
               'theory', th, 'solid', solid, 'maxDeviation', maxDev, ...
               'inCI', inCI, 'allInCI', all(inCI), 'nBits', a.nBits);

    if a.save
        plotTheory(R);
        analysis.saveResult('berVsTheory', R);
    end
end

% ---------------------------------------------------------------------------
function plotTheory(R)
    f = figure('Visible', 'off', 'Position', [100 100 760 520]);
    floorVal = 1e-8;

    semilogy(R.EbN0dB, R.theory, 'k-', 'LineWidth', 2); hold on;
    neg = max(R.ber - R.ciLo, 0);
    pos = max(R.ciHi - R.ber, 0);
    errorbar(R.EbN0dB, max(R.ber, floorVal), neg, pos, 'o', ...
             'Color', [0.20 0.40 0.70], 'MarkerFaceColor', [0.20 0.40 0.70], ...
             'MarkerSize', 5, 'LineWidth', 1.2, 'CapSize', 6);

    grid on;
    xlabel('E_b/N_0  [dB]');
    ylabel('BER');
    title(sprintf(['Model check: simulated link vs Q(\\surd(2E_b/N_0))\n' ...
                   '%g bits per point, theory inside 95%% CI at %d/%d points'], ...
                   R.nBits, sum(R.inCI), numel(R.inCI)));
    legend({'theory  Q(\surd(2E_b/N_0))', 'simulated, 95% CI'}, ...
           'Location', 'southwest');
    ylim([floorVal 1]);

    analysis.savePlot(f, 'berVsTheory');
end
