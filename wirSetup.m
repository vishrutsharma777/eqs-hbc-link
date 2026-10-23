function wirSetup()
%WIRSETUP Put the framework on the MATLAB path. Run once per session.
%
%   >> cd eqs-hbc-link
%   >> wirSetup
%   >> analysis.runAll          % regenerates every result and figure
%
%   The +dut, +harness and +analysis packages resolve from this directory,
%   so only the compiled BER engine in ber/ needs adding explicitly. If
%   ber_core has not been built yet this builds it.

    here = fileparts(mfilename('fullpath'));
    addpath(here);
    addpath(fullfile(here, 'ber'));

    if isempty(which('ber_core'))
        fprintf('Building ber_core MEX...\n');
        old = cd(fullfile(here, 'ber'));
        c = onCleanup(@() cd(old));
        mex -O ber_core.c
    end

    if ~exist(fullfile(here, 'results'), 'dir')
        mkdir(fullfile(here, 'results'));
    end
end
