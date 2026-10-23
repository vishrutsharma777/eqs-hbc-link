# Characterisation Report — EQS-HBC Transceiver Link

**Pre-silicon validation of a Wi-R-class electro-quasistatic human body communication link**

| | |
| --- | --- |
| DUT | EQS-HBC transceiver link, behavioral model (`+dut/`) |
| Harness | `wi-r-validation`, MATLAB R2025b + C (MEX) |
| Test date | 2026-09-15 |
| Suite runtime | 2.9 min, `analysis.runAll`, exit 0 |
| Self-test | 23/23 passing, `runTests` |
| Seed | 12345 (`dut.linkConfig` default); all sweeps deterministic |

---

## 1. Scope — read this before any number below

**No measurement in this report was taken on an instrument.** There is no silicon, no bench, no probe. Every figure is produced by a behavioral model whose parameters are drawn from published EQS-HBC measurements and whose detection chain is validated against closed-form theory before any other result is generated.

What that means for how these numbers should be read:

- **Trustworthy:** relative comparisons, trends, and the *shape* of the operating box. The model reproduces published channel anchors it was not fitted to, so the physics it encodes is sound.
- **Indicative only:** absolute margins, sensitivities and yields. They inherit every assumption in §7 and are not a substitute for characterising a real part.
- **Not comparable to a datasheet:** the energy-per-bit figures in particular are a lower bound, for the reasons in §6.5.

`harness.VisaBackend` defines the interface a real bench would attach to and raises a clear error rather than returning plausible fabricated data. That choice is deliberate.

---

## 2. Device under test

An EQS-HBC link guides electric fields *along the body* rather than radiating them, which is the basis of Ixana's Wi-R (~0.2 nJ/bit against BLE's 10+ nJ/bit, up to 20 Mb/s, ~30x signal confinement).

Signal chain as modelled (`dut.linkSim`):

```
Manchester encode -> NRZ at Vdd -> TX driver LPF -> EQS body channel
  -> + interference -> + input-referred noise -> VGA (gain, bandwidth)
  -> integrate-and-dump -> comparator (offset, hysteresis) -> decode
```

**Channel** (`dut.eqsChannel`) is a lumped capacitive divider: a device ground-plane return path `C_return` in series, terminated by the receiver `R_in ∥ C_in`. It is high-pass — return-path impedance exceeds 1 MΩ below 1 MHz, which is exactly why sub-MHz operation is lossy.

**Calibration.** The lumped divider alone predicts only ~10 dB of plateau loss where capacitive HBC measures 40–50 dB. The gap is distributed electrode/body/air coupling that no lumped model represents, and it is folded into a single scalar `k`, calibrated **once** against the published high-Z plateau at 15 MHz. `k` is a property of body-electrode coupling, not of the termination or the ground plane, so it is held fixed while both are swept. This is what makes §6.2 a prediction rather than a fit.

Key parameters, each cited at its definition in `+dut/channelParams.m`:

| Parameter | Value | Note |
| --- | --- | --- |
| `C_return` | 0.35 / 0.5 / 1.5 pF | *device ground plane*, per scenario |
| `C_body_earth` | 150 pF | *whole body* — distinct; the literature conflates the two |
| `C_in` / `R_in` | 1 pF / 1 MΩ | BodyWire RX, ESD-diode dominated |
| Input noise floor | 2.5 µV rms | reported wearable floor 1–2.5 µV |
| Mains coupling | 50 pF → ~20 mV | 240 V through 64 MΩ into 5 kΩ contact |
| Worst appliance tone | −49 dBV ≈ 3.2 mV @ 48 kHz | CFL; **dBV not dBm** (high-Z RX) |

---

## 3. Test plan

| Test | Swept | Pass criterion |
| --- | --- | --- |
| Model check | Eb/N0 0–10 dB | theory within measured 95% CI |
| Channel | f 1 kHz–100 MHz, `R_in` 50 Ω–1 MΩ | termination gain in published 40–50 dB |
| Shmoo | Vdd 0.1–1.2 V × Rb 50 kb/s–20 Mb/s | BER < 1e-4 on 95% upper bound |
| Bathtub | sampling phase ±0.45 UI | contiguous window meeting target |
| Sensitivity | Vrx 1 µV–30 mV × 4 interference cases | first Vrx meeting target |
| Energy | Rb 50 kb/s–20 Mb/s | energy credited only where BER passes |
| Yield | 120 dies × SS/TT/FF, σ_os = 3 mV | fraction of dies meeting target |

### 3.1 Pass is decided on the confidence bound, not the point estimate

Zero errors in 10⁴ bits gives a point estimate of exactly zero, which would pass any target at all if taken at face value. Its true 95% upper bound is 3×10⁻⁴. Reporting the point estimate is how a validation run claims margin it never measured, so `harness.measureBER` decides pass on the **Clopper–Pearson upper bound**.

Clopper–Pearson rather than a normal approximation specifically because the interesting regime — few or zero errors in very many bits — is where the Wald interval fails hardest, collapsing to a degenerate [0, 0] at k = 0.

### 3.2 Stopping rule

A fixed bit count is wrong in both directions: it wastes time on cells failing obviously and under-runs cells that are clean. Each measurement exits on whichever comes first:

- `errors` — ≥30 errors accumulated (roughly ±36% at 95%), enough for a point estimate
- `clean` — enough error-free bits that the bound is already below target; running longer proves nothing
- `budget` — bit budget exhausted. **Reported as such and not silently treated as a pass.**

This is also what sets runtime. Demonstrating BER < 10⁻⁶ at 95% confidence requires ~3×10⁶ error-free bits (the rule of three, `harness.bitsRequired`), so a full shmoo at that confidence is tens of billions of bits — which is why the BER engine is C (280 Mb/s generate, 400 Mb/s check) and not MATLAB.

---

## 4. Model validation — `results/berVsTheory.mat`

**This gates everything else.** With the channel bypassed, interference off and receiver bandwidth opened, the link reduces to antipodal signalling in AWGN, whose exact error rate is Q(√(2Eb/N₀)).

**Result: agreement to 2.6% at every point accumulating ≥100 errors (8 of 11 points, 4×10⁵ bits each).**

Theory fell inside the measured 95% interval at 10 of 11 points. The single excursion, at 8 dB, was investigated rather than waved through: 47 errors observed against 76 expected, about 3.3σ low. Re-running that operating point across 8 independent seeds gave 66–85 errors per seed and, pooled over 3.2×10⁶ bits, **BER 1.894×10⁻⁴ against theory 1.909×10⁻⁴ — agreement to 0.8%, with theory inside the pooled CI.** The excursion is a single unlucky noise realisation, not a model defect.

This is the expected behaviour of 11 independent 95% intervals; roughly one excursion is what should happen, and a suite reporting 11/11 would itself be mildly suspicious.

---

## 5. Framework self-validation — `runTests`

23 tests, all passing, ~5 s. A validation framework that has not itself been validated is not evidence of anything.

- **Model** — plateau matches calibration; termination gain within published band; channel monotonically high-pass; H(0) = 0 exactly (no Inf leak from 1/jωC); conjugate symmetry, without which the frequency-domain filter would not return a real signal; loss improves monotonically with ground plane.
- **Engine** — PRBS7/9/15 maximal-length and correctly periodic; **bit-for-bit identical to an independent MATLAB LFSR over 2×10⁵ bits**, so a C indexing slip cannot hide behind plausible randomness; self-sync checker locks after deliberate bit-slip; error multiplication measured at exactly taps+1 = 3.
- **Method** — Clopper–Pearson against `betaincinv`; the k = 0 case bounded near 3/n; rule of three; each stopping reason fires for the right cause; a short clean run correctly **fails** a 1e-6 target; identical configs reproduce bit-identical results; `VisaBackend` refuses loudly instead of fabricating.

---

## 6. Results

### 6.1 Channel — `results/channel.mat`

High-Z plateau lands at −45.0 dB, matching the published −40…−50 dB band.

### 6.2 Termination impedance is the whole design story — **43.0 dB, predicted**

Sweeping `R_in` from 50 Ω to 1 MΩ lifts the channel by **43.0 dB** at 15 MHz, against a published 40–50 dB.

This is the most load-bearing result in the report, and its value is in *how* it was obtained: `k` is calibrated once at high-Z and held fixed, so the 50 Ω branch is an **output of the topology, not a fitted parameter**. The model was given the high-Z plateau and independently reproduced the termination advantage.

Two consequences:
- It is the dominant receiver design choice for this class of link.
- **It is a measurement trap.** Probing an EQS-HBC node with an ordinary 50 Ω scope input loads the channel by ~43 dB and destroys the signal being measured. Any future bench work needs a high-Z active probe; this is a precondition, not a refinement.

### 6.3 Operating box — `results/shmoo.csv`, `results/shmoo.mat`

12 × 12 grid, **95 of 144 cells passing (66%)**, worst-case interferer, TT corner.

The failing region is **not** a simple low-voltage corner. There are two distinct walls:

- **A low-data-rate wall** — the dominant feature. Lowest rate passing anywhere is **256 kb/s**.
- **A bandwidth corner** at low Vdd and the highest rate, where front-end bandwidth runs out.

Lowest Vdd passing anywhere is 0.10 V, at mid rates.

### 6.4 The low-rate wall, and why it is interesting

Manchester differential detection rejects an interferer only while that interferer sits well below the signalling rate. As the bit rate falls toward the 48 kHz CFL tone, rejection collapses. At Vdd = 1.0 V with the worst-case interferer:

| Rb | BER | |
| --- | --- | --- |
| 50 kb/s | 4.4e-01 | broken |
| 100 kb/s | 3.8e-01 | broken |
| 200 kb/s | 8.3e-02 | broken |
| 500 kb/s | 0 | clean ← the wall |
| 5 Mb/s | 0 | clean |

So the shmoo's left edge is an interference-rejection cliff rather than a noise floor. It suggests a reason a commercial EQS-HBC transceiver would specify a **minimum** data rate rather than only a maximum — the part is not slow-capable, regardless of how much power budget is available.

### 6.5 Sensitivity — `results/sensitivity.mat`

At Rb = 2 Mb/s, channel −45.0 dB:

| Environment | Sensitivity |
| --- | --- |
| thermal noise only | **1.93 µV** |
| + 50 Hz mains | 3.33 µV |
| + worst CFL tone | 255 µV |
| + all modelled appliances | **756 µV** |

**Degradation from quiet to realistic: 51.8 dB.**

This is the report's central practical finding. With a ~2 µV floor and ~2.8 mV of received signal, thermal SNR is enormous and a noise-limited sensitivity figure would overstate real margin by more than fifty decibels. **A sensitivity number quoted without a named interference environment is close to meaningless for this class of link.**

Note that mains alone costs only ~5 dB: at 2 Mb/s, Manchester differential detection rejects a 50 Hz term almost entirely. It is the 40–110 kHz switched-mode band that does the damage, because those tones are close enough to the signalling rate to survive the differential subtraction.

### 6.6 Timing margin — `results/bathtub.mat`

**0.450 UI** at 2 Mb/s, on the 95% upper bound.

Deliberately conservative twice over: measured on the bound rather than the point estimate, and taken as the contiguous window around the eye centre rather than the union of all passing phases, so an isolated lucky sample on the skirt cannot inflate it. This is the budget available *to* a CDR, not a result about any particular CDR.

### 6.7 Energy per bit — `results/energy.mat`

Best passing point: **21.0 pJ/bit at 20 Mb/s**.

Shape matters more than the value: the static bias term falls as 1/Rb while the switching term is a rate-independent floor, so energy per bit improves with rate until it flattens. **Running a link slowly is the most expensive way to move a bit** — which compounds the §6.4 finding, since the low-rate region is both unreliable *and* energetically worst.

**This number is a lower bound and is not comparable to a datasheet figure.** The power model (`P_tx = αC·Vdd²·2Rb + P_bias`) is the one place in this work where constants were chosen rather than derived or cited, and it excludes digital baseband, clocking and duty-cycling overhead. Published references, for scale only: Wi-R ~200 pJ/bit, BLE ~10 000 pJ/bit.

### 6.8 Yield — `results/yieldMC.mat`

120 dies per corner, random comparator offset σ_os = 3 mV, at 2 Mb/s:

| Corner | Yield | 95% CI |
| --- | --- | --- |
| SS | 72.5% | [63.6, 80.3] |
| TT | **91.7%** | [85.2, 95.9] |
| FF | 69.2% | [60.1, 77.3] |

Both skewed corners lose ~20 points against typical, because each carries ±3 mV of *systematic* offset that adds to the random draw. After 45 dB of channel loss the received amplitude is only a few mV, so an offset spread of a few mV is not a second-order effect — it is comparable to the entire signal. Offset trim, not gain, is where this design's yield is won.

The intervals are quoted because a yield estimated from 120 draws is itself a measurement with finite precision; SS and FF overlap and should not be read as distinguishable.

---

## 7. Limitations

Recorded because a model whose limits are not written down will eventually be trusted past them.

1. **The `machine` channel scenario is out of calibration.** Literature reports ~0.5 dB loss for mains-connected machine-to-machine links; this model predicts ~−36 dB. Such a link returns current through a galvanic earth path the topology does not represent. The three *wearable* scenarios are in-calibration; `machine` is trend-only.
2. **The 50 Ω branch is calibrated at 15 MHz.** It tracks the published 90–100 dB band there and over-predicts loss far below that point.
3. **The power model is assumed, not measured** (§6.5). Energy figures are a lower bound.
4. **Interference is modelled as stationary tones** at measured amplitudes. Real appliance coupling drifts in frequency and amplitude with load, and the 51.8 dB penalty would change with it.
5. **No AGC, no equaliser, ideal CDR.** Sampling phase and jitter are injected directly rather than recovered.
6. **Interference figures are dBV, not dBm** — the receiver is high-Z and the two are not interconvertible without an impedance assumption.
7. **Yield uses a Gaussian offset model only**; no systematic spatial correlation, no other mismatch mechanism.

---

## 8. Conclusions

1. The framework reproduces closed-form theory to 2.6% and reproduces a published channel result it was not fitted to (43.0 dB termination gain). The physics is sound enough to reason from.
2. **The link is interference-limited, not noise-limited.** 51.8 dB of sensitivity is lost between a quiet room and a modelled realistic one. This is the single most important thing the report has to say.
3. **There is a minimum usable data rate**, ~256 kb/s on this grid, set by interference rejection rather than by SNR or power.
4. Yield is set by comparator offset against a few-mV received signal; typical-corner yield is 91.7% at σ_os = 3 mV, and skewed corners lose ~20 points.
5. The harness is written against an instrument interface and is ready to be repointed at a bench without touching any sweep in `+analysis`.

## 9. Reproducing this report

```matlab
>> cd eqs-hbc-link
>> wirSetup          % adds paths, builds the MEX engine
>> runTests          % 23/23, ~5 s
>> analysis.runAll   % ~3 min, regenerates every figure and CSV
>> analysis.summary  % prints every number above, read back from results/
```

`analysis.summary` exists specifically so this document can be checked against its data rather than trusted. Every number in §6 should reproduce exactly; the suite is seeded.
