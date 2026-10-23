function S = summary()
%SUMMARY Print every headline number, read from results/ rather than memory.
%
%   >> analysis.summary
%
%   Exists because the README and the characterisation report quote figures
%   that must match what the suite actually produced. Retyping numbers from a
%   previous run is how a report drifts away from its data, and a report whose
%   numbers cannot be traced to a saved result is not evidence of anything.
%   Run this after analysis.runAll and reconcile the documents against it.
%
%   Returns the same values as a struct for programmatic checking.
%
%   See also analysis.runAll, analysis.saveResult.

    here   = fileparts(fileparts(mfilename('fullpath')));
    outDir = fullfile(here, 'results');
    S = struct();

    fprintf('\n===============================================================\n');
    fprintf(' Headline numbers, read from results/\n');
    fprintf('===============================================================\n');

    % --- model check -------------------------------------------------------
    R = tryLoad(outDir, 'berVsTheory');
    if ~isempty(R)
        S.theory_maxDeviation = R.maxDeviation;
        S.theory_nBits = R.nBits;
        fprintf('\nMODEL CHECK (berVsTheory)\n');
        fprintf('  bits per point          : %g\n', R.nBits);
        fprintf('  max deviation vs theory : %.1f%%  (where >=30 errors)\n', ...
                R.maxDeviation*100);
    end

    % --- channel -----------------------------------------------------------
    R = tryLoad(outDir, 'channel');
    if ~isempty(R)
        S.terminationGain_dB = R.terminationGain_dB;
        fprintf('\nCHANNEL (channel)\n');
        fprintf('  termination gain @%.0f MHz : %.1f dB   (published 40-50)\n', ...
                R.fRef/1e6, R.terminationGain_dB);
    end

    % --- shmoo -------------------------------------------------------------
    R = tryLoad(outDir, 'shmoo');
    if ~isempty(R)
        S.shmoo_passFrac = mean(R.pass(:));
        fprintf('\nSHMOO (shmoo)\n');
        fprintf('  grid                    : %d Vdd x %d rates\n', ...
                numel(R.Vdd), numel(R.Rb));
        fprintf('  cells passing           : %d / %d  (%.0f%%)\n', ...
                sum(R.pass(:)), numel(R.pass), 100*mean(R.pass(:)));
        % Lowest rate that passes anywhere -- the interference wall.
        anyPass = any(R.pass, 1);
        if any(anyPass)
            S.minUsableRate = R.Rb(find(anyPass, 1, 'first'));
            fprintf('  lowest passing rate     : %.3g kb/s  (interference wall)\n', ...
                    S.minUsableRate/1e3);
        end
        % Lowest Vdd that passes anywhere.
        anyPassV = any(R.pass, 2);
        if any(anyPassV)
            S.minVdd = R.Vdd(find(anyPassV, 1, 'first'));
            fprintf('  lowest passing Vdd      : %.2f V\n', S.minVdd);
        end
    end

    % --- bathtub -----------------------------------------------------------
    R = tryLoad(outDir, 'bathtub');
    if ~isempty(R)
        S.margin_UI = R.margin_UI;
        S.bathtub_Rb = R.opts.Rb;
        fprintf('\nTIMING MARGIN (bathtub)\n');
        fprintf('  at Rb                   : %.3g Mb/s\n', R.opts.Rb/1e6);
        fprintf('  margin                  : %.3f UI  (95%% bound, contiguous)\n', ...
                R.margin_UI);
    end

    % --- sensitivity -------------------------------------------------------
    R = tryLoad(outDir, 'sensitivity');
    if ~isempty(R)
        S.sensitivity_V = R.sensitivity_V;
        S.sensitivity_cases = R.cases;
        fprintf('\nSENSITIVITY (sensitivity)  at Rb = %.3g Mb/s, channel %.1f dB\n', ...
                R.opts.Rb/1e6, R.chanLoss_dB);
        for i = 1:numel(R.cases)
            fprintf('  %-8s : %s\n', R.cases{i}, fmtV(R.sensitivity_V(i)));
        end
        v = R.sensitivity_V;
        if numel(v) >= 4 && all(isfinite(v([1 end])))
            S.interferencePenalty_dB = 20*log10(v(end)/v(1));
            fprintf('  degradation none -> all : %.1f dB\n', ...
                    S.interferencePenalty_dB);
        end
    end

    % --- energy ------------------------------------------------------------
    R = tryLoad(outDir, 'energy');
    if ~isempty(R)
        S.bestEnergy_J  = R.best_J;
        S.bestEnergy_Rb = R.best_Rb;
        fprintf('\nENERGY (energy)\n');
        if isnan(R.best_J)
            fprintf('  no passing operating point\n');
        else
            fprintf('  best passing point      : %.1f pJ/bit at %.3g Mb/s\n', ...
                    R.best_J*1e12, R.best_Rb/1e6);
            fprintf('  reference               : Wi-R 200 pJ/bit, BLE ~10000 pJ/bit\n');
            fprintf('  NOTE: lower bound -- model excludes baseband, clocking,\n');
            fprintf('        duty-cycling. Not comparable to a datasheet number.\n');
        end
    end

    % --- yield -------------------------------------------------------------
    R = tryLoad(outDir, 'yieldMC');
    if ~isempty(R)
        S.yieldPct  = R.yieldPct;
        S.yieldCorners = R.corners;
        fprintf('\nYIELD (yieldMC)  sigma_os = %.1f mV, n = %d dies\n', ...
                R.opts.sigmaOffset*1e3, R.opts.nSamples);
        for i = 1:numel(R.corners)
            fprintf('  %-3s : %5.1f%%   95%% CI [%.1f %.1f]\n', ...
                    R.corners{i}, R.yieldPct(i), R.ciLo(i), R.ciHi(i));
        end
    end

    fprintf('\n===============================================================\n\n');
end

% ---------------------------------------------------------------------------
function R = tryLoad(outDir, name)
    f = fullfile(outDir, [name '.mat']);
    if ~exist(f, 'file')
        fprintf('\n  (results/%s.mat missing -- run analysis.runAll)\n', name);
        R = [];
        return
    end
    d = load(f, 'R');
    R = d.R;
end

% ---------------------------------------------------------------------------
function s = fmtV(v)
    if isnan(v),     s = 'not reached';
    elseif v < 1e-3, s = sprintf('%7.2f uV', v*1e6);
    else,            s = sprintf('%7.2f mV', v*1e3);
    end
end
