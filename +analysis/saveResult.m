function saveResult(name, R)
%SAVERESULT Persist a sweep result as .mat and, where 2-D, as CSV.
%
%   analysis.saveResult('shmoo', R)
%     -> results/shmoo.mat   full struct, for re-plotting without re-running
%     -> results/shmoo.csv   flat table, for anything that is not MATLAB
%
%   Raw numbers are kept alongside every figure deliberately. A plot that
%   cannot be traced back to the measurement behind it is not a result, and
%   a validation report that cannot be re-derived from its data is not
%   auditable.

    here = fileparts(fileparts(mfilename('fullpath')));
    outDir = fullfile(here, 'results');
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    save(fullfile(outDir, [name '.mat']), 'R');
    fprintf('  wrote results/%s.mat\n', name);

    if isfield(R, 'ber') && ismatrix(R.ber) && isfield(R, 'Vdd') && isfield(R, 'Rb')
        [nV, nR] = size(R.ber);
        rows = cell(nV*nR, 1);
        k = 0;
        for i = 1:nV
            for j = 1:nR
                k = k + 1;
                rows{k} = sprintf('%.4g,%.6g,%.6e,%.6e,%d,%s', ...
                    R.Vdd(i), R.Rb(j), R.ber(i,j), R.ciHi(i,j), ...
                    R.pass(i,j), R.stopReason(i,j));
            end
        end
        fid = fopen(fullfile(outDir, [name '.csv']), 'w');
        fprintf(fid, 'Vdd_V,Rb_bps,ber,ci_hi_95,pass,stop_reason\n');
        fprintf(fid, '%s\n', rows{:});
        fclose(fid);
        fprintf('  wrote results/%s.csv\n', name);
    end
end
