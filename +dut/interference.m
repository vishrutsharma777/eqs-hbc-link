function [v, meta] = interference(t, cfg)
%INTERFERENCE EQS interference picked up by a floating-ground wearable.
%
%   v = dut.interference(t, cfg) returns the additive interference voltage
%   at the receiver input over time vector t.
%
%   THIS IS THE DOMINANT IMPAIRMENT, NOT THERMAL NOISE. With a measured
%   wearable noise floor of 1-2.5 uV and ~30 mV of received signal, an
%   EQS-HBC link at nominal path loss has enormous SNR headroom. What
%   actually closes the eye is environmental EQS coupling:
%
%     - 50 Hz mains. Body-to-mains coupling ~50 pF (64 Mohm at 50 Hz);
%       240 V through that into a 5 kohm electrode contact puts ~20 mV at
%       the amplifier input. For scale, an ECG R-wave is ~1 mV.
%
%     - Switched-mode appliances, 40-110 kHz. Measured on a floating-ground
%       wearable (all figures dBV, NOT dBm -- the receiver is high-Z and
%       these are not convertible to power without an impedance assumption):
%
%         CFL bedroom          47-49 kHz   -49 dBV   <- worst case, 3.2 mV
%         lab fluorescent      40-53 kHz   -50/-56 dBV
%         CFL living room      54-61 kHz   -61 dBV
%         laptop adaptor      90-110 kHz   -60 dBV
%         flush CFL / tube     42-47 kHz   -71 dBV
%
%   cfg.interferers selects which are active: 'none', 'mains', 'worst', or
%   'all'. See also dut.linkConfig.

    t = t(:).';
    v = zeros(size(t));
    meta = struct('sources', {{}}, 'totalRms', 0);

    mode = lower(cfg.interferers);
    if strcmp(mode, 'none'), return; end

    % --- 50 Hz mains ------------------------------------------------------
    % Derived, not assumed: V_mains across the body-to-mains capacitance in
    % series with the electrode contact resistance.
    p = cfg.chan;
    Zc      = 1 / (2*pi*cfg.mainsHz * p.C_body_mains);
    A_mains = cfg.mainsVrms * sqrt(2) * p.R_contact / sqrt(p.R_contact^2 + Zc^2);
    v = v + A_mains * sin(2*pi*cfg.mainsHz*t + cfg.mainsPhase);
    meta.sources{end+1} = sprintf('mains %gHz %.1f mVpk', cfg.mainsHz, A_mains*1e3);

    % --- Switched-mode appliance tones ------------------------------------
    if any(strcmp(mode, {'worst','all'}))
        if strcmp(mode, 'worst')
            tones = [48e3, -49];                       % CFL bedroom only
        else
            tones = [48e3 -49; 44e3 -50; 57e3 -61; 100e3 -60; 45e3 -71];
        end
        for i = 1:size(tones,1)
            A = 10^(tones(i,2)/20) * sqrt(2);          % dBV(rms) -> peak
            ph = 2*pi*mod(i*0.37, 1);                  % decorrelate phases
            v = v + A * sin(2*pi*tones(i,1)*t + ph);
            meta.sources{end+1} = sprintf('%.0f kHz %.1f dBV (%.2f mVpk)', ...
                                          tones(i,1)/1e3, tones(i,2), A*1e3);
        end
    end

    meta.totalRms = sqrt(mean(v.^2));
end
