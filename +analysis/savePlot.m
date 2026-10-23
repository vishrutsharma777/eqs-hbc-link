function savePlot(f, name)
%SAVEPLOT Write a figure to results/ as PNG and close it.
%
%   analysis.savePlot(f, 'shmoo')  ->  results/shmoo.png
%
%   Figures are created with 'Visible','off' so the whole suite runs
%   unattended under matlab -batch, which is what makes analysis.runAll
%   usable from a build script or CI job.

    here = fileparts(fileparts(mfilename('fullpath')));
    outDir = fullfile(here, 'results');
    if ~exist(outDir, 'dir'), mkdir(outDir); end

    % BackgroundColor is explicit because exportgraphics otherwise emits a
    % transparent background, which renders as black in dark-theme viewers
    % and makes the axis labels unreadable.
    set(f, 'Color', 'w');
    exportgraphics(f, fullfile(outDir, [name '.png']), ...
                   'Resolution', 150, 'BackgroundColor', 'white');
    close(f);
    fprintf('  wrote results/%s.png\n', name);
end
