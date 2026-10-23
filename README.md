# eqs-hbc-link

**A pre-silicon validation and characterisation framework for an EQS-HBC (Wi-R class) transceiver link.**

MATLAB · C (MEX) · reproducible from a single command

---

> **Scope, stated up front.** No measurement in this repository was taken on an instrument. Every result is **pre-silicon**, produced by a behavioral link model whose parameters are drawn from published EQS-HBC measurements and whose detection chain is checked against closed-form theory before any other figure is generated. `harness.VisaBackend` is the migration path to a real bench, and it is deliberately unimplemented rather than faked.

---

## What this is

Electro-Quasistatic Human Body Communication (EQS-HBC) guides tiny electric fields *along the body* instead of radiating them. It is the basis of Ixana's Wi-R, and it reports roughly **0.2 nJ/bit against BLE's 10+ nJ/bit**, up to **20 Mb/s**, and ~30x better signal confinement.

This repository asks the validation question about that link: **over what operating box does it actually work, and how would you prove it?**

It builds the four things a silicon validation engineer would build to answer that — a parameterised DUT model, a fast BER engine, an instrument-abstracted test harness, and the standard characterisation sweeps — and it reports margins with confidence bounds rather than point estimates.

## Headline results

| Result | Value | Cross-check |
| --- | --- | --- |
| Channel gain from high-Z vs 50 Ω termination | **43.0 dB** | published 40–50 dB — **predicted, not fitted** |
| Sensitivity, thermal-noise-limited | **1.93 µV** | measured wearable floor is 1–2.5 µV |
| Sensitivity, real interference environment | **756 µV** | a **51.8 dB** penalty a quiet-room number would have hidden |
| Timing margin at 2 Mb/s | **0.450 UI** | on the 95% upper bound, contiguous window only |
| Lowest passing data rate | **256 kb/s** | set by interference rejection, not by SNR |
| Yield, σ_offset = 3 mV | **91.7% TT, 72.5% SS, 69.2% FF** | with Clopper–Pearson intervals |
| Best energy per bit (passing) | **21 pJ/bit at 20 Mb/s** | lower bound — see limitations |

Reproduce this table with `analysis.summary`, which reads every figure back out of `results/*.mat` rather than from this file.

### Three findings worth the space

**1. Termination impedance is the whole design story, and the model predicts it.**
The coupling constant is calibrated *once* against the measured high-Z plateau and then held fixed while the termination is swept. The 43 dB advantage of a high-Z capacitive termination over 50 Ω falls out of the topology as an output. It also implies something practical: probing one of these nodes with an ordinary 50 Ω scope input destroys the signal you came to measure.

**2. The link is interference-limited, not noise-limited.**
With a ~2 µV noise floor and ~2.8 mV of received signal, thermal SNR is enormous. Sensitivity against thermal noise alone is **1.93 µV**; in a modelled real interference environment it degrades to **756 µV**, a penalty of **51.8 dB**. Quoting the quiet-room number would claim margin that does not exist in any room with a light fitting in it. What actually closes the eye is environmental EQS coupling — mains at ~20 mV and switched-mode appliance tones at 40–110 kHz, worst case a CFL at −49 dBV ≈ 3.2 mV.

**3. There is a low-data-rate wall, and it explains a product decision.**
Manchester differential detection rejects an interferer only while that interferer sits well below the signalling rate. As the bit rate falls toward the 48 kHz CFL tone, rejection collapses. Measured at Vdd = 1.0 V with the worst-case interferer:

```
Rb = 50 kb/s   BER 4.4e-01     broken
Rb = 100 kb/s  BER 3.8e-01     broken
Rb = 200 kb/s  BER 8.3e-02     broken
Rb = 500 kb/s  BER 0           clean      <- the wall
Rb = 5 Mb/s    BER 0           clean
```

Across the full shmoo the lowest rate that passes anywhere is **256 kb/s**. So the shmoo's left edge is not a noise floor, it is an interference-rejection cliff — and it is a plausible reason a commercial EQS-HBC transceiver would specify a *minimum* data rate rather than only a maximum.

## Figures

| | |
| --- | --- |
| `results/berVsTheory.png` | **Read this first.** Simulated BER against Q(√(2Eb/N0)) — agrees to **2.6%** wherever ≥100 errors accumulated. If this did not agree, nothing else here would mean anything. |
| `results/channel.png` | Body-channel transfer function vs termination impedance and ground-plane size |
| `results/shmoo.png` | Vdd × data-rate pass/fail map — the signature validation artifact |
| `results/bathtub.png` | BER vs sampling phase → timing margin, with the eye it came from |
| `results/sensitivity.png` | Minimum detectable signal in four named interference environments |
| `results/energy.png` | Energy per bit vs data rate, against Wi-R and BLE reference lines |
| `results/yieldMC.png` | Monte Carlo comparator-offset yield across PVT corners |

Every figure has a `.mat` beside it, and the 2-D sweeps also emit `.csv`. A plot that cannot be traced back to its measurement is not a result.

## Running it

```matlab
>> cd eqs-hbc-link
>> wirSetup          % adds paths, builds the MEX engine if needed
>> runTests          % 23 tests, ~5 s
>> analysis.runAll   % regenerates every figure and CSV in results/
```

`analysis.runAll('quick', true)` uses coarser grids for a smoke test. Everything runs under `matlab -batch`, so the suite is usable from a build script.

Requires MATLAB (developed on R2025b) and a C compiler for `mex`. No toolboxes: `betaincinv` and `erfc` are core MATLAB, which is deliberate — a validation framework that needs four licences to run is one that does not get run.

## Layout

```
+dut/          the device under test, as a behavioral model
  channelParams.m   lumped parameters + the one-time coupling calibration
  eqsChannel.m      complex channel transfer function
  interference.m    mains and switched-mode appliance coupling
  corners.m         SS/TT/FF process skew
  linkConfig.m      every swept non-ideality, in one struct
  linkSim.m         TX -> channel -> RX -> decision

ber/           ber_core.c   PRBS gen, self-sync check, fast compare (MEX)

+harness/      the test equipment, abstracted
  Instrument.m      abstract interface -- the reason this survives to silicon
  SimBackend.m      pre-silicon backend
  VisaBackend.m     bench backend, deliberately unimplemented
  clopperPearson.m  exact binomial CI
  bitsRequired.m    how long must a link run clean to earn its claim
  measureBER.m      statistically-terminated measurement

+analysis/     the sweeps    tests/   the suite    results/   outputs
```

## Two design decisions worth explaining

**Why the instrument abstraction exists.** Every sweep is written against `harness.Instrument`, never against the simulator. Moving to a bench is a backend swap, not a rewrite:

```matlab
b = harness.SimBackend();        % today
b = harness.VisaBackend(rsrc);   % when silicon exists
```

`+analysis` does not change. That separation is ordinary practice in validation and is why a harness tends to outlive the chip it was written for.

**Why pass is decided on the confidence bound.** Zero errors in 10⁴ bits gives a point estimate of exactly zero, which would pass any target at all if taken at face value. Its true 95% upper bound is 3×10⁻⁴. Reporting the point estimate is how a validation run claims margin it never measured, so `harness.measureBER` decides pass on the bound and reports *why* it stopped — `clean`, `errors`, or `budget`. A run that merely ran out of budget without failing is **not** recorded as a pass.

This is also what sets runtime: demonstrating BER < 10⁻⁶ at 95% confidence needs ~3×10⁶ error-free bits (the rule of three), and a full shmoo at that confidence is tens of billions of bits. That is why the BER engine is C and not MATLAB — it runs at ~280 Mb/s generate, ~400 Mb/s check.

## Model limitations

Recorded because a model whose limits are not written down will eventually be trusted past them.

- **The `machine` channel scenario is out of calibration.** Literature reports ~0.5 dB loss for mains-connected machine-to-machine links; this model predicts ~−36 dB. A mains-connected link returns current through a galvanic earth path that this topology does not represent. The three *wearable* scenarios are in-calibration; `machine` is trend-only.
- **The 50 Ω branch is calibrated at 15 MHz** and tracks the published 90–100 dB band there. Far below the calibration point it over-predicts loss.
- **The power model is assumed, not measured.** `P_tx = αC·Vdd²·2Rb` plus a static `P_bias` is the one place numbers were chosen rather than derived or cited. It excludes digital baseband, clocking and duty-cycling overhead, so the energy-per-bit figures are a **lower bound** and are not comparable to a silicon datasheet number.
- **Interference is modelled as stationary tones** at measured amplitudes. Real appliance coupling drifts in frequency and amplitude with load.
- **The receiver has no AGC, no equaliser and an ideal CDR**; sampling phase and jitter are injected directly rather than recovered. Timing margin is therefore the budget available *to* a CDR, not a result about any particular one.
- Interference figures are **dBV, not dBm** — the receiver is high-Z and the two are not interconvertible without an impedance assumption.

## Sources for the parameters

Channel and interference constants are taken from the Purdue/Sen EQS-HBC literature that Wi-R derives from, principally the biophysical channel modelling and BodyWire transceiver work, plus published Wi-R figures. Each constant is cited at its definition in `+dut/channelParams.m` and `+dut/interference.m`. Two receiver noise figures in circulation (8.69 nV/√Hz, 0.25 µVrms) were traced only to abstract summaries and are deliberately **not** used.
