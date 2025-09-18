%% -------- CSV EXPORT (HEAVE ONLY) --------
try
    outDir = pwd;

    % ---- time vector ----
    if isfield(output,'time') && ~isempty(output.time)
        t = output.time(:);
    elseif isfield(output,'bodies') && isfield(output.bodies(1),'time') && ~isempty(output.bodies(1).time)
        t = output.bodies(1).time(:);
    else
        Nt_est = floor((simu.endTime - simu.startTime)/simu.dt);
        t = (simu.startTime : simu.dt : simu.startTime + (Nt_est-1)*simu.dt).';
    end

    % ---- body indices ----
    names = string({output.bodies.name});
    iFloat = find(strcmpi(names,"float"),1);
    iSpar  = find(strcmpi(names,"spar"),1);
    if isempty(iFloat) || isempty(iSpar)
        error('Need both "float" and "spar" in output.bodies.');
    end

    % ---- pull heave (3rd DOF) and orient as column vectors ----
    posF = output.bodies(iFloat).position;   zF  = posF(:,3);   if size(posF,2) > size(posF,1), zF  = posF(3,:).'; end
    velF = output.bodies(iFloat).velocity;   dzF = velF(:,3);   if size(velF,2) > size(velF,1), dzF = velF(3,:).'; end
    accF = output.bodies(iFloat).acceleration; ddzF = accF(:,3); if size(accF,2) > size(accF,1), ddzF = accF(3,:).'; end

    posS = output.bodies(iSpar).position;    zS  = posS(:,3);   if size(posS,2) > size(posS,1), zS  = posS(3,:).'; end
    velS = output.bodies(iSpar).velocity;    dzS = velS(:,3);   if size(velS,2) > size(velS,1), dzS = velS(3,:).'; end
    accS = output.bodies(iSpar).acceleration; ddzS = accS(:,3); if size(accS,2) > size(accS,1), ddzS = accS(3,:).'; end

    % ---- equalize length with time ----
    Nt = min([numel(t), numel(zF), numel(dzF), numel(ddzF), numel(zS), numel(dzS), numel(ddzS)]);
    t    = t(1:Nt);
    zF   = zF(1:Nt);  dzF  = dzF(1:Nt);  ddzF = ddzF(1:Nt);
    zS   = zS(1:Nt);  dzS  = dzS(1:Nt);  ddzS = ddzS(1:Nt);

    % ---- relative heave (float - spar) ----
    Xrel  = zF  - zS;
    Xdrel = dzF - dzS;

    % ---- linear PTO in heave ----
    Kpto = 0; Cpto = 0;
    if isfield(output,'ptos') && ~isempty(output.ptos)
        P = output.ptos(1);
        if isfield(P,'k') && ~isempty(P.k), Kpto = P.k(min(end,3)); end
        if isfield(P,'c') && ~isempty(P.c), Cpto = P.c(min(end,3)); end
    end
    F_pto = -Kpto .* Xrel - Cpto .* Xdrel;
    P_pto = -F_pto .* Xdrel;

    % ---- consolidated CSV for linear PTO modelling ----
    Tlinear = table(t, zF, dzF, ddzF, zS, dzS, ddzS, Xrel, Xdrel, F_pto, P_pto, ...
        'VariableNames', {'Time','FloatHeave','FloatHeaveDot','FloatHeaveDDot', ...
        'SparHeave','SparHeaveDot','SparHeaveDDot','Xrel_heave','Xdrel_heave','F_pto','P_pto'});
    writetable(Tlinear, fullfile(outDir, 'linear_pto_heave.csv'));

    fprintf('Wrote linear PTO CSV:\n  linear_pto_heave.csv\n');
catch ME
    warning('CSV export (heave) failed: %s', ME.message);
end
