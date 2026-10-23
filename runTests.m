function result = runTests()
%RUNTESTS Run the validation framework's own test suite.
%
%   >> runTests
%
%   Exits non-zero on failure under matlab -batch, so this is usable as a CI
%   gate.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, 'ber'));

    if isempty(which('ber_core'))
        old = cd(fullfile(here, 'ber'));
        c = onCleanup(@() cd(old));
        mex -O ber_core.c
        clear c
    end

    result = runtests(fullfile(here, 'tests'));
    disp(table(result));

    if any([result.Failed])
        error('runTests:failed', '%d of %d tests failed.', ...
              sum([result.Failed]), numel(result));
    end
    fprintf('\nAll %d tests passed in %.1f s.\n', ...
            numel(result), sum([result.Duration]));
end
