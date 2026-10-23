function R = channelPlot(varargin)
%CHANNELPLOT Body-channel transfer function: termination and ground plane.
%
%   R = analysis.channelPlot()
%
%   Two panels, both of which exist to make one point each.
%
%   LEFT -- termination impedance. Sweeping the receiver termination from
%   50 ohm to 1 Mohm lifts the channel by roughly 43 dB at the 15 MHz
%   operating point, which reproduces the published 40-50 dB improvement that
%   capacitive termination gives over a 50 ohm load. This is the single most
%   consequential design choice in an EQS-HBC receiver, and it is worth being
%   clear that the model PREDICTS it rather than being fitted to it: the
%   coupling constant k in dut.channelParams is calibrated once against the
%   high-Z plateau and then held fixed while the termination is swept. The
%   50 ohm curve is an output of the topology, not an input.
%
%   It also explains a practical trap: measuring one of these nodes with an
%   ordinary 50 ohm scope input destroys the signal you came to measure.
%
%   RIGHT -- device ground plane. Path loss scales monotonically with the
%   return-path capacitance, so a small wearable ground plane is lossier than
%   a large one. This is the axis along which a body-area link gets harder as
%   the device gets smaller.
%
%   See also dut.eqsChannel, dut.channelParams.

    ip = inputParser;
    addParameter(ip, 'f',    logspace(3, 8, 400));
    addParameter(ip, 'save', true);
    parse(ip, varargin{:});
    a = ip.Results;

    f = a.f;
    p = dut.channelParams('wearable');

    % --- Termination sweep ------------------------------------------------
    Rterm = [50, 1e3, 10e3, 100e3, 1e6];
    Hterm = zeros(numel(Rterm), numel(f));
    for i = 1:numel(Rterm)
        q = p; q.R_in = Rterm(i);
        Hterm(i,:) = dut.eqsChannel(f, q);
    end

    % --- Scenario sweep ---------------------------------------------------
    scen = {'wearable-worst','wearable','wearable-large-gnd'};
    Hscen = zeros(numel(scen), numel(f));
    for i = 1:numel(scen)
        Hscen(i,:) = dut.eqsChannel(f, dut.channelParams(scen{i}));
    end

    fRef  = p.F_REF;
    gain  = 20*log10(abs(dut.eqsChannel(fRef, setR(p,1e6)))) - ...
            20*log10(abs(dut.eqsChannel(fRef, setR(p,50))));
    fprintf('channelPlot: termination gain at %.0f MHz = %.1f dB ', fRef/1e6, gain);
    fprintf('(published 40-50 dB)\n');

    R = struct('f', f, 'Rterm', Rterm, 'Hterm', Hterm, ...
               'scenarios', {scen}, 'Hscen', Hscen, ...
               'terminationGain_dB', gain, 'fRef', fRef);

    if a.save
        plotChan(R);
        analysis.saveResult('channel', R);
    end
end

% ---------------------------------------------------------------------------
function q = setR(p, R)
    q = p; q.R_in = R;
end

% ---------------------------------------------------------------------------
function plotChan(R)
    f = figure('Visible', 'off', 'Position', [100 100 1020 440]);

    subplot(1,2,1);
    cols = parula(numel(R.Rterm)+1);
    for i = 1:numel(R.Rterm)
        semilogx(R.f, 20*log10(abs(R.Hterm(i,:))), 'LineWidth', 1.8, ...
                 'Color', cols(i,:)); hold on;
    end
    xline(R.fRef, ':k', sprintf('%.0f MHz', R.fRef/1e6));
    yline(-45, '--', 'published high-Z plateau  -40..-50 dB', ...
          'Color', [0.2 0.55 0.35]);
    grid on;
    xlabel('frequency  [Hz]'); ylabel('|H|  [dB]');
    title(sprintf('Termination impedance  (%.0f dB spread at %.0f MHz)', ...
                  R.terminationGain_dB, R.fRef/1e6));
    legend(compose('R_{in} = %g \\Omega', R.Rterm), 'Location', 'southeast', ...
           'FontSize', 8);
    ylim([-160 0]);

    subplot(1,2,2);
    cols2 = lines(numel(R.scenarios));
    for i = 1:numel(R.scenarios)
        semilogx(R.f, 20*log10(abs(R.Hscen(i,:))), 'LineWidth', 1.8, ...
                 'Color', cols2(i,:)); hold on;
    end
    grid on;
    xlabel('frequency  [Hz]'); ylabel('|H|  [dB]');
    title('Device ground plane (return-path capacitance)');
    legend(strrep(R.scenarios,'_','\_'), 'Location', 'southeast', 'FontSize', 8);
    ylim([-100 -20]);

    analysis.savePlot(f, 'channel');
end
