function R = sensitivity(varargin)
%SENSITIVITY BER vs received signal amplitude -> minimum detectable signal.
%
%   R = analysis.sensitivity()
%   R = analysis.sensitivity('Rb',2e6,'interferers','all')
%
%   Sweeps the transmit drive and reports BER against the amplitude actually
%   arriving at the receiver input, Vrx = (Vdd/2) * |H(Rb)|. The sensitivity
%   is the smallest Vrx that still meets the BER target on the 95% bound.
%
%   The sweep spans 1 uV to 30 mV, chosen from measured hardware: 1-2.5 uV is
%   the reported wearable noise floor and ~30 mV is the received amplitude a
%   1 V transmitter produces across 40 dB of body-channel loss.
%
%   THE POINT OF RUNNING THIS WITH AND WITHOUT INTERFERENCE: against thermal
%   noise alone the sensitivity lands near the microvolt floor, implying tens
%   of dB of link margin that does not exist in a real room. Add the measured
%   CFL and mains interferers and the sensitivity degrades by orders of
%   magnitude. An EQS-HBC link is interference-limited, not noise-limited,
%   and a sensitivity number quoted without a named interference environment
%   is close to meaningless.
%
%   See also analysis.shmoo, dut.interference, dut.eqsChannel.

    ip = inputParser;
    addParameter(ip, 'Rb',        2e6);
    addParameter(ip, 'corner',    'TT');
    addParameter(ip, 'cases',     {'none', 'mains', 'worst', 'all'});
    addParameter(ip, 'Vdd',       logspace(log10(4e-4), log10(12), 22));
    addParameter(ip, 'targetBER', 1e-4);
    addParameter(ip, 'maxBits',   1e5);
    addParameter(ip, 'save',      true);
    parse(ip, varargin{:});
    a = ip.Results;

    b = harness.SimBackend();
    opts = struct('targetBER', a.targetBER, 'maxBits', a.maxBits, ...
                  'blockBits', 2e4, 'minErrors', 30);

    % Received amplitude for each transmit drive, through the channel.
    cRef  = dut.linkConfig('Rb', a.Rb);
    Hmag  = abs(dut.eqsChannel(a.Rb, cRef.chan));
    Vrx   = (a.Vdd/2) * Hmag;

    nC   = numel(a.cases);
    nV   = numel(a.Vdd);
    ber  = nan(nC, nV);
    ciHi = nan(nC, nV);
    sens = nan(1, nC);

    fprintf('sensitivity: Rb = %.3g Mb/s, channel %.1f dB\n', ...
            a.Rb/1e6, 20*log10(Hmag));
    for ci = 1:nC
        for vi = 1:nV
            cfg = dut.linkConfig('Rb', a.Rb, 'Vdd', a.Vdd(vi), ...
                                 'corner', a.corner, ...
                                 'interferers', a.cases{ci});
            r = harness.measureBER(b, cfg, opts);
            ber(ci,vi)  = r.ber;
            ciHi(ci,vi) = r.ciHi;
        end
        ok = ciHi(ci,:) < a.targetBER;
        if any(ok), sens(ci) = Vrx(find(ok, 1, 'first')); end
        fprintf('  %-6s sensitivity = %s\n', a.cases{ci}, fmtV(sens(ci)));
    end

    R = struct('Vdd', a.Vdd, 'Vrx', Vrx, 'cases', {a.cases}, 'ber', ber, ...
               'ciHi', ciHi, 'sensitivity_V', sens, 'chanLoss_dB', ...
               20*log10(Hmag), 'opts', a);

    if a.save
        plotSensitivity(R);
        analysis.saveResult('sensitivity', R);
    end
end

% ---------------------------------------------------------------------------
function s = fmtV(v)
    if isnan(v),        s = 'not reached';
    elseif v < 1e-3,    s = sprintf('%.2f uV', v*1e6);
    else,               s = sprintf('%.2f mV', v*1e3);
    end
end

% ---------------------------------------------------------------------------
function plotSensitivity(R)
    f = figure('Visible', 'off', 'Position', [100 100 780 500]);
    cols = lines(numel(R.cases));
    floorVal = 1e-7;

    for ci = 1:numel(R.cases)
        loglog(R.Vrx*1e3, max(R.ciHi(ci,:), floorVal), '-o', ...
               'LineWidth', 1.6, 'MarkerSize', 4, 'Color', cols(ci,:), ...
               'MarkerFaceColor', cols(ci,:));
        hold on;
    end
    yline(R.opts.targetBER, '--', 'target', 'Color', [0.7 0.2 0.2]);

    for ci = 1:numel(R.cases)
        if ~isnan(R.sensitivity_V(ci))
            xline(R.sensitivity_V(ci)*1e3, ':', 'Color', cols(ci,:), ...
                  'LineWidth', 1.2);
        end
    end

    grid on;
    xlabel('received amplitude V_{rx}  [mV]');
    ylabel('BER  (95% upper bound)');
    title(sprintf(['Sensitivity at R_b = %.3g Mb/s, channel %.1f dB\n' ...
                   'dotted lines: minimum detectable signal per environment'], ...
                   R.opts.Rb/1e6, R.chanLoss_dB));
    legend(R.cases, 'Location', 'southwest');
    ylim([floorVal 1]);

    analysis.savePlot(f, 'sensitivity');
end
