function p = channelParams(scenario)
%CHANNELPARAMS Lumped-element parameters for the EQS-HBC body channel.
%
%   p = dut.channelParams()            reference (wearable, nominal)
%   p = dut.channelParams(scenario)    named scenario
%
%   Scenarios scale the device ground-plane return capacitance C_return,
%   which the literature identifies as the dominant driver of path loss
%   (loss scales monotonically with ground-plane size).
%
%   Scenario                 C_return    published loss anchor
%   -----------------------  ----------  ------------------------------
%   'wearable-worst'         0.35 pF     up to -50 dB  (arXiv 1805.02492)
%   'wearable'  (reference)  0.50 pF     -40..-50 dB   (BodyWire JSSC)
%   'wearable-large-gnd'     1.50 pF     device gnd plane upper bound
%   'machine'                50   pF     mains-connected (SEE CAVEAT)
%
%   CAVEAT ON 'machine': the literature reports ~0.5 dB minimum loss for
%   mains-connected machine-to-machine links; this model predicts ~-36 dB.
%   The discrepancy is real and is a MODEL LIMITATION, not a tuning error:
%   a mains-connected link returns current through a galvanic earth path
%   that this topology does not represent, and the coupling constant k is
%   calibrated for body-electrode coupling only. Use 'machine' for trend
%   only. The three wearable scenarios are in-calibration and are the ones
%   that matter for a body-area network.
%
%   NOTE ON C_return vs C_body_earth: these are distinct and are routinely
%   conflated in the literature. C_return (~1-1.5 pF) is a *device ground
%   plane* property and is the one that sets the return-path impedance seen
%   by the transceiver. C_body_earth (~150 pF, feet-to-ground 10-20 pF) is a
%   *whole body* property and is carried here only for the interference model.
%
%   See also dut.eqsChannel, dut.interference.

    if nargin < 1 || isempty(scenario)
        scenario = 'wearable';
    end

    % --- Receiver front end (BodyWire JSSC measured values) ---------------
    p.C_in   = 1e-12;    % RX input capacitance, ESD-diode dominated [F]
    p.R_in   = 1e6;      % RX input resistance, high-Z termination    [ohm]
    p.R_body = 1e3;      % body series resistance                     [ohm]

    % --- Whole-body electrostatics (interference model only) --------------
    p.C_body_earth = 150e-12;   % body-to-earth capacitance           [F]
    p.C_body_mains = 50e-12;    % body-to-mains coupling              [F]
    p.R_contact    = 5e3;       % electrode contact resistance        [ohm]

    % --- Scenario: device ground-plane return capacitance -----------------
    switch lower(scenario)
        case 'wearable-worst',     p.C_return = 0.35e-12;
        case 'wearable',           p.C_return = 0.50e-12;
        case 'wearable-large-gnd', p.C_return = 1.50e-12;
        case 'machine',            p.C_return = 50e-12;
        otherwise
            error('dut:channelParams:badScenario', ...
                  'Unknown scenario "%s".', scenario);
    end
    p.scenario = lower(scenario);

    % --- Coupling calibration ---------------------------------------------
    % The lumped divider alone predicts only ~-10 dB of plateau loss, whereas
    % capacitive HBC is measured at -40..-50 dB with high-Z termination. The
    % gap is the distributed electrode/body/air coupling loss that a lumped
    % model cannot represent. We fold it into a single scalar k, calibrated
    % ONCE against the reference scenario so that |H| = PLATEAU_DB at F_REF.
    %
    % k is a property of the body-electrode coupling, NOT of the receiver
    % termination or the ground plane -- so it stays fixed while scenarios
    % vary C_return and while the harness sweeps R_in. That is what lets the
    % model *predict* the 50-ohm branch rather than having it fitted in.
    p.F_REF      = 15e6;    % calibration frequency [Hz] (BodyWire op. point)
    p.PLATEAU_DB = -45;     % measured high-Z plateau  [dB] (mid of -40..-50)
    p.k = calibrate(p);
end

function k = calibrate(p)
    ref = p;
    ref.C_return = 0.50e-12;   % reference ground plane
    ref.R_in     = 1e6;        % reference high-Z termination
    ref.k        = 1;
    Hraw = dut.eqsChannel(p.F_REF, ref);
    k = 10^(p.PLATEAU_DB/20) / abs(Hraw);
end
