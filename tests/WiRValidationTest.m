classdef WiRValidationTest < matlab.unittest.TestCase
%WIRVALIDATIONTEST Test suite for the EQS-HBC validation framework.
%
%   Run with:   >> runTests
%
%   The suite is organised around one idea: a validation framework that has
%   not itself been validated is not evidence of anything. Three groups:
%
%     MODEL     the channel and link reproduce published anchors and closed
%               form theory
%     ENGINE    the C BER core agrees bit-for-bit with a reference and
%               behaves correctly under bit-slip and injected errors
%     METHOD    the statistics are right, the stopping rules fire for the
%               stated reasons, and runs are reproducible

    properties (Constant)
        TOL_DB = 0.5;
    end

    methods (TestClassSetup)
        function setupPath(~)
            here = fileparts(fileparts(mfilename('fullpath')));
            addpath(here);
            addpath(fullfile(here, 'ber'));
        end
    end

    methods (Test)

        % ---------------- MODEL ------------------------------------------

        function testChannelPlateauMatchesPublished(tc)
            % The high-Z plateau is calibrated to -45 dB; verify the
            % calibration actually lands where it claims to.
            p = dut.channelParams('wearable');
            h = 20*log10(abs(dut.eqsChannel(p.F_REF, p)));
            tc.verifyEqual(h, p.PLATEAU_DB, 'AbsTol', tc.TOL_DB, ...
                'High-Z plateau does not match its calibration target.');
        end

        function testTerminationGainIsPredicted(tc)
            % The 40-50 dB advantage of high-Z over 50 ohm termination is an
            % OUTPUT of the topology: k is calibrated once at high-Z and held
            % fixed. This is the single most load-bearing claim in the model.
            p  = dut.channelParams('wearable');
            hi = 20*log10(abs(dut.eqsChannel(p.F_REF, setRin(p, 1e6))));
            lo = 20*log10(abs(dut.eqsChannel(p.F_REF, setRin(p, 50))));
            gain = hi - lo;
            tc.verifyGreaterThan(gain, 40, ...
                'Termination gain below the published 40-50 dB band.');
            tc.verifyLessThan(gain, 50, ...
                'Termination gain above the published 40-50 dB band.');
        end

        function testChannelIsHighPass(tc)
            % Return-path impedance exceeds 1 Mohm below 1 MHz, so loss must
            % increase monotonically as frequency falls.
            p = dut.channelParams('wearable');
            f = [1e4 1e5 1e6 1e7];
            h = 20*log10(abs(dut.eqsChannel(f, p)));
            tc.verifyTrue(all(diff(h) > 0), ...
                'Channel is not monotonically high-pass.');
        end

        function testChannelDCIsZero(tc)
            % A purely capacitive return path passes nothing at DC. Guards
            % against an Inf/NaN leaking out of the 1/(jwC) term.
            p = dut.channelParams('wearable');
            h = dut.eqsChannel(0, p);
            tc.verifyEqual(h, 0);
            tc.verifyFalse(any(isnan(dut.eqsChannel([0 1e6], p))));
        end

        function testChannelConjugateSymmetry(tc)
            % Required for the frequency-domain filter in dut.linkSim to
            % produce a real output.
            p = dut.channelParams('wearable');
            f = [1e4 1e5 1e6 1e7];
            tc.verifyEqual(dut.eqsChannel(-f, p), conj(dut.eqsChannel(f, p)), ...
                'RelTol', 1e-12);
        end

        function testLossScalesWithGroundPlane(tc)
            % Loss falls monotonically as the device ground plane grows.
            s = {'wearable-worst','wearable','wearable-large-gnd'};
            h = zeros(1,3);
            for i = 1:3
                p = dut.channelParams(s{i});
                h(i) = 20*log10(abs(dut.eqsChannel(p.F_REF, p)));
            end
            tc.verifyTrue(all(diff(h) > 0), ...
                'Path loss does not improve with a larger ground plane.');
        end

        function testBerMatchesTheoryWithinCI(tc)
            % THE LOAD-BEARING TEST. With the channel bypassed and only AWGN
            % present, the link is antipodal signalling and its exact BER is
            % Q(sqrt(2.Eb/N0)). The assertion is that theory falls inside the
            % measured 95% interval -- comparing point estimates would fail
            % or pass on counting noise rather than on correctness.
            nBits = 3e5;
            for ebn0 = [0 2 4 6]
                cfg = dut.linkConfig('bypassChannel', true, 'vgaBW', Inf, ...
                                     'interferers', 'none', ...
                                     'EbN0dB', ebn0, 'seed', 4242);
                tx = ber_core('gen', 15, nBits, 3);
                rx = dut.linkSim(tx, cfg);
                k  = ber_core('compare', tx, uint8(rx));
                [lo, hi] = harness.clopperPearson(k, nBits);
                th = 0.5*erfc(sqrt(10^(ebn0/10)));
                tc.verifyGreaterThanOrEqual(th, lo, ...
                    sprintf('Theory below CI at Eb/N0 = %d dB.', ebn0));
                tc.verifyLessThanOrEqual(th, hi, ...
                    sprintf('Theory above CI at Eb/N0 = %d dB.', ebn0));
            end
        end

        function testInterferenceWallAtLowRate(tc)
            % The physical finding the shmoo rests on: Manchester differential
            % detection rejects an interferer only while that interferer sits
            % well below the signalling rate. At 100 kb/s a 48 kHz CFL tone
            % breaks the link; at 5 Mb/s the same tone is rejected.
            b = harness.SimBackend();
            o = struct('maxBits', 6e4);
            slow = harness.measureBER(b, ...
                dut.linkConfig('Rb', 100e3, 'interferers', 'worst'), o);
            fast = harness.measureBER(b, ...
                dut.linkConfig('Rb', 5e6,   'interferers', 'worst'), o);
            tc.verifyGreaterThan(slow.ber, 1e-2, ...
                'Low-rate link should be broken by the CFL interferer.');
            tc.verifyTrue(fast.pass, ...
                'High-rate link should reject the CFL interferer.');
        end

        % ---------------- ENGINE -----------------------------------------

        function testPrbsMaximalLength(tc)
            for ord = [7 9 15]
                per = 2^ord - 1;
                b = ber_core('gen', ord, 2*per, 1);
                tc.verifyEqual(b(1:per), b(per+1:2*per), ...
                    sprintf('PRBS%d is not periodic in 2^n-1.', ord));
                tc.verifyEqual(double(sum(b(1:per))), 2^(ord-1), ...
                    sprintf('PRBS%d is not maximal length.', ord));
            end
        end

        function testPrbsAgainstMatlabReference(tc)
            % Independent MATLAB LFSR, bit for bit, so a C indexing slip
            % cannot hide behind plausible-looking randomness.
            ord = 9; n = 2e5; taps = [9 5];
            mask = uint32(2^ord - 1);
            reg = uint32(1);
            ref = zeros(1, n, 'uint8');
            for i = 1:n
                fb = bitand(bitxor(bitshift(reg, -(taps(1)-1)), ...
                                   bitshift(reg, -(taps(2)-1))), uint32(1));
                reg = bitand(bitshift(reg, 1) + fb, mask);
                ref(i) = uint8(fb);
            end
            tc.verifyEqual(ber_core('gen', ord, n, 1), ref);
        end

        function testCheckerCleanStream(tc)
            b = ber_core('gen', 9, 1e5, 1);
            [nerr, nchk] = ber_core('check', 9, b);
            tc.verifyEqual(nerr, 0);
            tc.verifyEqual(nchk, 1e5 - 9);
        end

        function testCheckerErrorMultiplication(tc)
            % A self-synchronising checker counts each isolated error
            % (taps+1) = 3 times. Asserted rather than assumed, because
            % berCount corrections depend on the factor being exactly this.
            b = ber_core('gen', 9, 1e4, 1);
            d = b; d(5000) = 1 - d(5000);
            tc.verifyEqual(ber_core('check', 9, d), 3);
        end

        function testCheckerSelfSynchronises(tc)
            % Starting mid-sequence must still score zero errors after lock.
            b = ber_core('gen', 9, 1e5, 1);
            tc.verifyEqual(ber_core('check', 9, b(1234:end)), 0);
        end

        function testCompareOp(tc)
            a = ber_core('gen', 9, 1e4, 1);
            c = a; c([10 20 30 40]) = 1 - c([10 20 30 40]);
            tc.verifyEqual(ber_core('compare', a, c), 4);
            tc.verifyEqual(ber_core('compare', a, a), 0);
        end

        function testEngineRejectsBadInput(tc)
            tc.verifyError(@() ber_core('gen', 8, 100, 1), 'ber_core:order');
            tc.verifyError(@() ber_core('bogus'),          'ber_core:usage');
        end

        % ---------------- METHOD -----------------------------------------

        function testClopperPearsonZeroErrors(tc)
            % The case the normal approximation gets catastrophically wrong.
            % Zero errors in n trials does NOT mean BER = 0; the upper bound
            % is about 3/n.
            [lo, hi] = harness.clopperPearson(0, 1e4);
            tc.verifyEqual(lo, 0);
            tc.verifyEqual(hi, 3e-4, 'RelTol', 0.25);
        end

        function testClopperPearsonAgainstBeta(tc)
            [lo, hi] = harness.clopperPearson(30, 1e6, 0.05);
            tc.verifyEqual(lo, betaincinv(0.025, 30, 1e6-30+1), 'RelTol', 1e-9);
            tc.verifyEqual(hi, betaincinv(0.975, 31, 1e6-30),   'RelTol', 1e-9);
            tc.verifyLessThan(lo, 3e-5);
            tc.verifyGreaterThan(hi, 3e-5);
        end

        function testBitsRequiredRuleOfThree(tc)
            tc.verifyEqual(harness.bitsRequired(1e-6, 0.95), 3e6, 'RelTol', 0.01);
            tc.verifyEqual(harness.bitsRequired(1e-3, 0.95), 3e3, 'RelTol', 0.01);
            tc.verifyGreaterThan(harness.bitsRequired(1e-6, 0.99), ...
                                 harness.bitsRequired(1e-6, 0.95));
        end

        function testMeasureBERStopsClean(tc)
            b = harness.SimBackend();
            r = harness.measureBER(b, dut.linkConfig('Rb', 2e6), ...
                    struct('targetBER', 1e-3, 'maxBits', 1e5));
            tc.verifyEqual(r.stopReason, 'clean');
            tc.verifyTrue(r.pass);
            tc.verifyEqual(r.nerr, 0);
        end

        function testMeasureBERStopsOnErrors(tc)
            b = harness.SimBackend();
            r = harness.measureBER(b, ...
                    dut.linkConfig('Rb', 2e6, 'Vdd', 0.01, 'interferers', 'all'), ...
                    struct('maxBits', 1e5));
            tc.verifyEqual(r.stopReason, 'errors');
            tc.verifyFalse(r.pass);
        end

        function testPassUsesUpperBoundNotPointEstimate(tc)
            % A short clean run has a point estimate of exactly zero but has
            % not earned a 1e-6 claim. It must not pass.
            b = harness.SimBackend();
            r = harness.measureBER(b, dut.linkConfig('Rb', 2e6), ...
                    struct('targetBER', 1e-6, 'maxBits', 2e4));
            tc.verifyEqual(r.ber, 0);
            tc.verifyFalse(r.pass, ...
                'Zero errors in a short run must not pass a 1e-6 target.');
            tc.verifyEqual(r.stopReason, 'budget');
        end

        function testReproducibleAcrossRuns(tc)
            cfg = dut.linkConfig('Rb', 2e6, 'Vdd', 0.2, 'interferers', 'all');
            b1 = harness.SimBackend(); r1 = harness.measureBER(b1, cfg, struct('maxBits',6e4));
            b2 = harness.SimBackend(); r2 = harness.measureBER(b2, cfg, struct('maxBits',6e4));
            tc.verifyEqual(r1.ber, r2.ber, ...
                'Identical configuration produced different results.');
        end

        function testVisaBackendRefusesLoudly(tc)
            v = harness.VisaBackend();
            tc.verifyError(@() v.configure(dut.linkConfig()), ...
                'harness:VisaBackend:notImplemented');
            tc.verifyError(@() v.runBurst(100), ...
                'harness:VisaBackend:notImplemented');
        end
    end
end

% ---------------------------------------------------------------------------
function q = setRin(p, R)
    q = p; q.R_in = R;
end
