function cfg = linkConfig(varargin)
%LINKCONFIG Configuration for the EQS-HBC link model, with name/value overrides.
%
%   cfg = dut.linkConfig()                       nominal
%   cfg = dut.linkConfig('Rb',5e6,'Vdd',0.8)     overrides
%
%   Every non-ideality the harness sweeps is a field here. That is
%   deliberate: the test harness must never reach inside the DUT model, it
%   may only configure it -- the same discipline that lets the harness be
%   repointed at real silicon without rewriting the sweeps.
%
%   Defaults sit at the Wi-R YR23 operating point (100 kbps - 5 Mbps).
%
%   See also dut.linkSim, dut.channelParams, dut.corners.

    ip = inputParser;

    % --- Link -------------------------------------------------------------
    addParameter(ip, 'Rb',        1e6);      % bit rate [b/s]
    addParameter(ip, 'osr',       16);       % samples per Manchester half-bit
    addParameter(ip, 'Vdd',       1.0);      % TX supply / drive amplitude [V]
    addParameter(ip, 'txBW',      50e6);     % TX driver bandwidth [Hz]

    % --- Channel ----------------------------------------------------------
    addParameter(ip, 'scenario',  'wearable');
    addParameter(ip, 'R_in',      1e6);      % RX termination [ohm]
    addParameter(ip, 'bypassChannel', false);% flat channel (theory checks)

    % --- Receiver ---------------------------------------------------------
    addParameter(ip, 'corner',    'TT');
    addParameter(ip, 'vgaGain',   100);      % nominal VGA gain [V/V]
    addParameter(ip, 'vgaBW',     30e6);     % RX bandwidth [Hz], Inf = none
    addParameter(ip, 'compOffset', 0);       % extra comparator offset [V]
    addParameter(ip, 'compHyst',   0);       % comparator hysteresis [V]
    addParameter(ip, 'inputRefNoiseRms', 2.5e-6);  % measured floor 1-2.5 uV
    addParameter(ip, 'EbN0dB',    []);       % if set, overrides noise (theory)

    % --- Timing -----------------------------------------------------------
    addParameter(ip, 'samplePhase', 0);      % sampling phase offset [UI]
    addParameter(ip, 'jitterRmsUI', 0);      % RMS sampling jitter [UI]

    % --- Interference -----------------------------------------------------
    addParameter(ip, 'interferers', 'none'); % none | mains | worst | all
    addParameter(ip, 'mainsHz',    50);
    addParameter(ip, 'mainsVrms',  240);
    addParameter(ip, 'mainsPhase', 0);

    % --- Reproducibility --------------------------------------------------
    addParameter(ip, 'seed', 12345);

    parse(ip, varargin{:});
    cfg = ip.Results;

    cfg.chan = dut.channelParams(cfg.scenario);
    cfg.chan.R_in = cfg.R_in;
    cfg.fs  = 2 * cfg.Rb * cfg.osr;   % Manchester: 2 half-bits per bit
    cfg.spb = 2 * cfg.osr;            % samples per bit
end
