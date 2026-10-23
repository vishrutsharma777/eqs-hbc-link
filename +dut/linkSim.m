function [rxBits, diag] = linkSim(txBits, cfg, rngState)
%LINKSIM End-to-end EQS-HBC link: TX -> body channel -> interference -> RX.
%
%   [rxBits, diag] = dut.linkSim(txBits, cfg)
%   [rxBits, diag] = dut.linkSim(txBits, cfg, rngState)
%
%   Signal chain:
%     Manchester encode -> NRZ at Vdd -> TX driver LPF -> EQS body channel
%       -> + interference -> + input-referred noise -> VGA (gain, LPF)
%       -> integrate-and-dump -> differential comparator -> Manchester decode
%
%   Manchester is antipodal per bit (1 -> [+A -A], 0 -> [-A +A]), so with a
%   flat channel and AWGN only the exact BER is Q(sqrt(2.Eb/N0)). That closed
%   form is what tests/testBerVsTheory.m checks the model against before any
%   margin result is trusted. If that check fails, every shmoo and bathtub
%   downstream is meaningless.
%
%   diag returns the per-bit decision statistic (the eye) and the post-VGA
%   waveform, which the eye and bathtub analyses consume.
%
%   See also dut.linkConfig, dut.eqsChannel, dut.interference.

    if nargin >= 3 && ~isempty(rngState)
        rng(rngState);
    else
        rng(cfg.seed);
    end

    txBits = logical(txBits(:)');
    nBits  = numel(txBits);
    osr    = cfg.osr;
    spb    = cfg.spb;

    c = dut.corners(cfg.corner);

    % --- Manchester encode -------------------------------------------------
    A = cfg.Vdd/2;
    half = zeros(2, nBits);
    half(1, :) =  A*(2*txBits-1);
    half(2, :) = -A*(2*txBits-1);
    sym = reshape(half, 1, []);              % 2 half-bits per bit
    x   = repelem(sym, osr);                 % NRZ upsample

    % --- TX driver bandwidth ------------------------------------------------
    x = onePoleLPF(x, cfg.txBW, cfg.fs);

    % --- Body channel -------------------------------------------------------
    if cfg.bypassChannel
        y = x;
        diag.chanLoss_dB = 0;
    else
        y = applyChannel(x, cfg);
        diag.chanLoss_dB = 20*log10(abs(dut.eqsChannel(cfg.Rb, cfg.chan)));
    end

    % --- Interference --------------------------------------------------------
    N = numel(y);
    t = (0:N-1)/cfg.fs;
    [vInt, diag.interf] = dut.interference(t, cfg);
    y = y + vInt;

    % --- Input-referred noise ------------------------------------------------
    if ~isempty(cfg.EbN0dB)
        % Theory mode: derive sigma from Eb/N0 so the model can be checked
        % against the closed form. Eb = A^2 * Tb for antipodal signalling.
        Eb    = A^2 / cfg.Rb;
        N0    = Eb / 10^(cfg.EbN0dB/10);
        sigma = sqrt(N0 * cfg.fs / 2);
    else
        sigma = cfg.inputRefNoiseRms;
    end
    y = y + sigma*randn(1, N);
    diag.sigma = sigma;

    % --- VGA: gain then bandwidth --------------------------------------------
    G = cfg.vgaGain * c.gainMult;
    y = G * y;
    if isfinite(cfg.vgaBW)
        y = onePoleLPF(y, cfg.vgaBW * c.bwMult, cfg.fs);
    end

    % --- Sampling: phase offset + jitter, then integrate and dump ------------
    jit  = cfg.jitterRmsUI * randn(1, nBits);
    off  = round((cfg.samplePhase + jit) * spb);
    base = (0:nBits-1)*spb;

    yp   = [y, zeros(1, 2*spb)];             % pad so shifted windows stay valid
    idx1 = (base + 1)       + (0:osr-1)';
    idx2 = (base + osr + 1) + (0:osr-1)';
    idx1 = min(max(idx1 + off, 1), numel(yp));
    idx2 = min(max(idx2 + off, 1), numel(yp));

    s1 = sum(yp(idx1), 1);
    s2 = sum(yp(idx2), 1);
    d  = (s1 - s2) / osr;                    % differential decision statistic

    % --- Comparator: offset (corner systematic + explicit) + hysteresis ------
    vos    = (c.offsetV + cfg.compOffset) * G;
    rxBits = comparatorDecide(d, vos, cfg.compHyst * G);

    diag.eye  = d;
    diag.wave = y;
    diag.gain = G;
    diag.vos  = vos;
end

% ---------------------------------------------------------------------------
function y = applyChannel(x, cfg)
%APPLYCHANNEL Frequency-domain application of the EQS body channel.
%   H is evaluated on signed FFT frequencies. H(-f) = conj(H(f)) follows from
%   the topology, so the filtered output is real to numerical precision.
    N = numel(x);
    f = (0:N-1) * (cfg.fs/N);
    f(f > cfg.fs/2) = f(f > cfg.fs/2) - cfg.fs;    % signed frequencies
    H = dut.eqsChannel(f, cfg.chan);
    y = real(ifft(fft(x) .* H));
end

% ---------------------------------------------------------------------------
function y = onePoleLPF(x, fc, fs)
%ONEPOLELPF First-order lowpass, impulse-invariant. Models TX driver and VGA
%   bandwidth without pulling in a filter-design toolbox dependency.
    if ~isfinite(fc) || fc >= fs/2
        y = x;
        return
    end
    a = exp(-2*pi*fc/fs);
    y = filter(1-a, [1 -a], x);
end

% ---------------------------------------------------------------------------
function b = comparatorDecide(d, vos, hyst)
%COMPARATORDECIDE Threshold with input offset and hysteresis.
%   With hyst = 0 this is a memoryless sign decision, which keeps the theory
%   check exact. With hyst > 0 the threshold depends on the previous decision,
%   so the sequential loop is required.
    if hyst == 0
        b = d > vos;
        return
    end
    n    = numel(d);
    b    = false(1, n);
    prev = false;
    for i = 1:n
        thr  = vos - (prev*2-1)*(hyst/2);
        prev = d(i) > thr;
        b(i) = prev;
    end
end
