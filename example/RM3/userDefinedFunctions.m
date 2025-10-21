%% -------------------------------------------------------------------------
%  RM3 Linear PTO Export Helper
%
%  Captures the heave (3rd DOF) response of the RM3 example after a WEC-Sim
%  run and serialises it to `linear_pto_heave.json`. The JSON file carries:
%    * relative heave displacement/velocity between float and spar
%    * PTO reaction force and mechanical power reported by WEC-Sim
%    * incident wave elevation history
%    * metadata describing the simulation, wave setup, and PTO constants
%
%  Linear PTO formulation follows the WEC-Sim documentation
%  ("Linear PTO", https://wec-sim.github.io/WEC-Sim/main/index.html) where
%      F_pto = -K_pto * X_rel - C_pto * Xdot_rel
%      P_pto = -F_pto * Xdot_rel
%
%  This script runs inside the WEC-Sim workspace; keep it function-free so the
%  engine can execute it via `userDefinedFunctions.m` convention.
%% -------------------------------------------------------------------------
%% JSON EXPORT (HEAVE ONLY)
try
    outDir = pwd;

    % ---- Construct simulation time vector (fallback uses simu.dt) ----
    if isfield(output,'time') && ~isempty(output.time)
        t = output.time(:);
    elseif isfield(output,'bodies') && isfield(output.bodies(1),'time') && ~isempty(output.bodies(1).time)
        t = output.bodies(1).time(:);
    else
        Nt_est = floor((simu.endTime - simu.startTime)/simu.dt);
        t = (simu.startTime : simu.dt : simu.startTime + (Nt_est-1)*simu.dt).';
    end

    % ---- Locate float and spar bodies (RM3 naming convention) ----
    names = string({output.bodies.name});
    iFloat = find(strcmpi(names,"float"),1);
    iSpar  = find(strcmpi(names,"spar"),1);
    if isempty(iFloat) || isempty(iSpar)
        error('Need both "float" and "spar" in output.bodies.');
    end

    % ---- Extract heave (3rd DOF) motion for each body ----
    posF = output.bodies(iFloat).position;   zF  = posF(:,3);   if size(posF,2) > size(posF,1), zF  = posF(3,:).'; end
    velF = output.bodies(iFloat).velocity;   dzF = velF(:,3);   if size(velF,2) > size(velF,1), dzF = velF(3,:).'; end
    accF = output.bodies(iFloat).acceleration; ddzF = accF(:,3); if size(accF,2) > size(accF,1), ddzF = accF(3,:).'; end

    posS = output.bodies(iSpar).position;    zS  = posS(:,3);   if size(posS,2) > size(posS,1), zS  = posS(3,:).'; end
    velS = output.bodies(iSpar).velocity;    dzS = velS(:,3);   if size(velS,2) > size(velS,1), dzS = velS(3,:).'; end
    accS = output.bodies(iSpar).acceleration; ddzS = accS(:,3); if size(accS,2) > size(accS,1), ddzS = accS(3,:).'; end

    % ---- Trim arrays to the common sample count ----
    Nt = min([numel(t), numel(zF), numel(dzF), numel(ddzF), numel(zS), numel(dzS), numel(ddzS)]);
    t    = t(1:Nt);
    zF   = zF(1:Nt);  dzF  = dzF(1:Nt);  ddzF = ddzF(1:Nt);
    zS   = zS(1:Nt);  dzS  = dzS(1:Nt);  ddzS = ddzS(1:Nt);

    % ---- Relative heave signal needed by the linear PTO ----
    Xrel   = zF  - zS;
    Xdrel  = dzF - dzS;

    % ---- Prepare export paths and remove legacy CSV artefacts ----
    exportFile = fullfile(outDir, 'linear_pto_heave.json');
    legacyCsv = fullfile(outDir, 'linear_pto_heave.csv');
    if exist(legacyCsv, 'file') == 2
        try
            delete(legacyCsv);
        catch
            % ignore inability to delete legacy CSV
        end
    end

    % ---- linear PTO configuration (heave DOF) ----
    Kpto = 0; Cpto = 0; P = [];
    if isfield(output,'ptos') && ~isempty(output.ptos)
        P = output.ptos(1);
        if isfield(P,'k') && ~isempty(P.k)
            Kpto = pickHeaveComponent(P.k);
        end
        if isfield(P,'c') && ~isempty(P.c)
            Cpto = pickHeaveComponent(P.c);
        end
        if isfield(P,'stiffness') && ~isempty(P.stiffness)
            Kpto = pickHeaveComponent(P.stiffness);
        end
        if isfield(P,'damping') && ~isempty(P.damping)
            Cpto = pickHeaveComponent(P.damping);
        end
    end
    if (Kpto == 0 || Cpto == 0)
        try
            if evalin('base','exist(''pto'',''var'')')
                Pbase = evalin('base','pto(1)');
                if isprop(Pbase,'stiffness')
                    Kpto = pickHeaveComponent(Pbase.stiffness);
                end
                if isprop(Pbase,'damping')
                    Cpto = pickHeaveComponent(Pbase.damping);
                end
            end
        catch
            % ignore base workspace lookup errors
        end
    end
    F_pto_model = -Kpto .* Xrel - Cpto .* Xdrel;
    P_pto_model = -F_pto_model .* Xdrel;

    % ---- Capture WEC-Sim PTO force/power for validation ----
    F_pto_wec = nan(Nt,1);
    P_pto_wec = nan(Nt,1);
    forceSource = 'model';
    powerSource = 'model';
    if ~isempty(P)
        forceFields = {'forceTotal','forceApplied','force','forceActuation'};
        for iField = 1:numel(forceFields)
            fld = forceFields{iField};
            if isfield(P, fld) && ~isempty(P.(fld))
                rawForce = P.(fld);
                if ~isnumeric(rawForce), continue; end
                if isvector(rawForce)
                    if numel(rawForce) >= Nt
                        rawForce = rawForce(:);
                    else
                        continue;
                    end
                else
                    if size(rawForce,2) >= 3
                        rawForce = rawForce(:,3);
                    elseif size(rawForce,1) >= 3
                        rawForce = rawForce(3,:).';
                    else
                        rawForce = rawForce(:);
                    end
                end
                Nf = min(Nt, numel(rawForce));
                F_pto_wec(1:Nf) = rawForce(1:Nf);
                forceSource = ['output.ptos.' fld];
                break;
            end
        end

        powerFields = {'powerInternalMechanics','powerInternal','power','powerMechanics','P'};
        for iField = 1:numel(powerFields)
            fld = powerFields{iField};
            if isfield(P, fld) && ~isempty(P.(fld))
                rawPower = P.(fld);
                if ~isnumeric(rawPower), continue; end
                if isvector(rawPower)
                    rawPower = rawPower(:);
                else
                    if size(rawPower,2) >= 3
                        rawPower = rawPower(:,3);
                    elseif size(rawPower,1) >= 3
                        rawPower = rawPower(3,:).';
                    else
                        rawPower = rawPower(:);
                    end
                end
                Np = min(Nt, numel(rawPower));
                P_pto_wec(1:Np) = rawPower(1:Np);
                powerSource = ['output.ptos.' fld];
                break;
            end
        end
    end
    if all(isnan(F_pto_wec))
        F_pto_wec = F_pto_model;
        forceSource = 'model (fallback)';
    end
    if all(isnan(P_pto_wec))
        P_pto_wec = P_pto_model;
        powerSource = 'model (fallback)';
    end

    % Fill any remaining NaNs with analytically reconstructed values.
    nanForceIdx = isnan(F_pto_wec);
    if any(nanForceIdx)
        F_pto_wec(nanForceIdx) = F_pto_model(nanForceIdx);
        if ~contains(forceSource,'model','IgnoreCase',true)
            forceSource = [forceSource ' (NaNs->model)'];
        end
    end
    nanPowerIdx = isnan(P_pto_wec);
    if any(nanPowerIdx)
        P_pto_wec(nanPowerIdx) = P_pto_model(nanPowerIdx);
        if ~contains(powerSource,'model','IgnoreCase',true)
            powerSource = [powerSource ' (NaNs->model)'];
        end
    end

    % ---- wave elevation (first gauge/point) ----
    waveElevation = nan(Nt,1);
    waveSource = 'unavailable';
    if isfield(output,'wave') && ~isempty(output.wave)
        W = output.wave;
        waveFields = {'elevation','waveElevation','eta','wavegaugeElevation'};
        for iField = 1:numel(waveFields)
            fld = waveFields{iField};
            if isfield(W, fld) && ~isempty(W.(fld))
                rawWave = W.(fld);
                if isnumeric(rawWave)
                    if isvector(rawWave)
                        rawWave = rawWave(:);
                    else
                        if size(rawWave,2) > size(rawWave,1)
                            rawWave = rawWave(1,:).';
                        else
                            rawWave = rawWave(:,1);
                        end
                    end
                    Nw = min(Nt, numel(rawWave));
                    waveElevation(1:Nw) = rawWave(1:Nw);
                    waveSource = ['output.wave.' fld];
                    break;
                end
            end
        end
    end
    % Fall back to the global `waves` definition if simulation output lacks elevation.
    if all(isnan(waveElevation))
        try
            if evalin('base','exist(''waves'',''var'')')
                Wbase = evalin('base','waves');
                candidate = [];
                candidateLabel = '';
                if isprop(Wbase,'waveAmpTime') && ~isempty(Wbase.waveAmpTime)
                    candidate = Wbase.waveAmpTime;
                    candidateLabel = 'waves.waveAmpTime';
                elseif isprop(Wbase,'elevation') && ~isempty(Wbase.elevation)
                    candidate = Wbase.elevation;
                    candidateLabel = 'waves.elevation';
                elseif isprop(Wbase,'waveElevation') && ~isempty(Wbase.waveElevation)
                    candidate = Wbase.waveElevation;
                    candidateLabel = 'waves.waveElevation';
                end
                if ~isempty(candidate) && isnumeric(candidate)
                    if size(candidate,2) == 2
                        waveElevation = interp1(candidate(:,1), candidate(:,2), t, 'linear', 'extrap');
                    else
                        data = candidate(:);
                        Nw = min(Nt, numel(data));
                        waveElevation(1:Nw) = data(1:Nw);
                    end
                    waveSource = candidateLabel;
                end
            end
        catch
            % ignore base workspace lookup errors
        end
    end
    % Final guard: note missing wave data and zero-fill to keep JSON numeric.
    if all(isnan(waveElevation))
        waveSource = 'unavailable';
    end
    if any(isnan(waveElevation))
        waveElevation(isnan(waveElevation)) = 0;
        if strcmpi(waveSource,'unavailable')
            waveSource = 'unavailable (zeros)';
        else
            waveSource = [waveSource ' (NaNs->0)'];
        end
    end

    % ---- Package JSON payload (metadata + time series) ----
    meta = struct();
    meta.exportVersion = 1;
    meta.generatedAt = datestr(now, 'yyyy-mm-ddTHH:MM:SS');
    meta.samples = Nt;
    meta.relativeDOF = 'heave';
    meta.Kpto = double(Kpto);
    meta.Cpto = double(Cpto);
    meta.forceSource = forceSource;
    meta.powerSource = powerSource;
    meta.waveSource = waveSource;
    meta.startTime = double(simu.startTime);
    meta.endTime = double(simu.endTime);
    meta.timeStep = double(simu.dt);

    meta.simulation = struct();
    meta.simulation.modelFile = toCharScalar(getPropOrDefault(simu,'simMechanicsFile',''));
    meta.simulation.mode = toCharScalar(getPropOrDefault(simu,'mode',''));
    meta.simulation.solver = toCharScalar(getPropOrDefault(simu,'solver',''));
    meta.simulation.stateSpace = toDoubleScalar(getPropOrDefault(simu,'stateSpace',NaN), NaN);
    meta.simulation.rampTime = toDoubleScalar(getPropOrDefault(simu,'rampTime',NaN), NaN);

    meta.wave = struct('type','', 'spectrum','', 'height',NaN, 'period',NaN, 'phaseSeed',NaN, 'direction',[]);
    try
        Wmeta = evalin('base','waves');
        meta.wave.type = toCharScalar(getPropOrDefault(Wmeta,'type',''));
        meta.wave.spectrum = toCharScalar(getPropOrDefault(Wmeta,'spectrumType',''));
        meta.wave.height = toDoubleScalar(getPropOrDefault(Wmeta,'height',NaN), NaN);
        meta.wave.period = toDoubleScalar(getPropOrDefault(Wmeta,'period',NaN), NaN);
        meta.wave.phaseSeed = toDoubleScalar(getPropOrDefault(Wmeta,'phaseSeed',NaN), NaN);
        dirVal = getPropOrDefault(Wmeta,'direction',[]);
        meta.wave.direction = toRowVector(dirVal);
    catch
        % ignore missing wave metadata
    end

    meta.bodies = struct('names', {{}});
    try
        Bmeta = evalin('base','body');
        names = cell(1, numel(Bmeta));
        for ib = 1:numel(Bmeta)
            names{ib} = toCharScalar(getPropOrDefault(Bmeta(ib),'name',''));
        end
        meta.bodies.names = names;
    catch
        % ignore missing body metadata
    end

    meta.constraints = struct('names', {{}});
    try
        Cmeta = evalin('base','constraint');
        names = cell(1, numel(Cmeta));
        for ic = 1:numel(Cmeta)
            names{ic} = toCharScalar(getPropOrDefault(Cmeta(ic),'name',''));
        end
        meta.constraints.names = names;
    catch
        % ignore missing constraint metadata
    end

    meta.ptoName = '';
    meta.pto = struct('name','', 'stiffness', double(Kpto), 'damping', double(Cpto), 'location', []);
    try
        if ~isempty(P) && isfield(P,'name')
            meta.ptoName = toCharScalar(P.name);
        elseif evalin('base','exist(''pto'',''var'')')
            Ptmp = evalin('base','pto(1)');
            if isprop(Ptmp,'name')
                meta.ptoName = toCharScalar(Ptmp.name);
            end
            meta.pto.location = toRowVector(getPropOrDefault(Ptmp,'location',[]));
        end
        if isempty(meta.pto.location) && ~isempty(P) && isfield(P,'location')
            meta.pto.location = toRowVector(P.location);
        end
    catch
        % ignore base workspace lookup errors
    end
    meta.pto.name = meta.ptoName;
    meta.pto.forceField = forceSource;
    meta.pto.powerField = powerSource;

    data = struct();
    data.time = t;
    data.relativeDisplacement = Xrel;
    data.relativeVelocity = Xdrel;
    data.ptoForceWEC = F_pto_wec;
    data.ptoPowerWEC = P_pto_wec;
    data.waveElevation = waveElevation;

    exportStruct = struct('meta', meta, 'data', data);

    try
        jsonText = jsonencode(exportStruct, 'PrettyPrint', true, 'ConvertInfAndNaN', true);
    catch
        jsonText = jsonencode(exportStruct, 'ConvertInfAndNaN', true);
    end

    fid = fopen(exportFile, 'w');
    if fid < 0
        error('Could not open %s for writing.', exportFile);
    end
    try
        fprintf(fid, '%s\n', jsonText);
    catch fileME
        fclose(fid);
        rethrow(fileME);
    end
    fclose(fid);

    fprintf('Wrote linear PTO JSON with relative motion, PTO force/power, and wave elevation.\n');
catch ME
    warning('JSON export (heave) failed: %s', ME.message);
end

function val = getPropOrDefault(obj, name, defaultVal)
% Safely extract a property/field from structs or WEC-Sim objects.
    val = defaultVal;
    try
        if isstruct(obj)
            if isfield(obj, name) && ~isempty(obj.(name))
                val = obj.(name);
            end
        elseif isobject(obj)
            if isprop(obj, name) && ~isempty(obj.(name))
                val = obj.(name);
            end
        end
    catch
        val = defaultVal;
    end
    if isempty(val)
        val = defaultVal;
    end
end

function coeff = pickHeaveComponent(val)
% Return the heave (3rd DOF) component from a PTO property vector.
    coeff = 0;
    if isnumeric(val) && ~isempty(val)
        vec = val(:);
        coeff = double(vec(min(3, numel(vec))));
    end
end

function txt = toCharScalar(val)
% Convert different string-like inputs into a char row vector for JSON metadata.
    if isstring(val)
        txt = char(val);
    elseif ischar(val)
        txt = val;
    elseif isnumeric(val) && isscalar(val) && ~isnan(val)
        txt = num2str(val);
    else
        txt = '';
    end
end

function num = toDoubleScalar(val, defaultVal)
% Ensure scalars are returned as doubles, otherwise provide the default.
    if isnumeric(val) && ~isempty(val)
        num = double(val(1));
    else
        num = defaultVal;
    end
end

function vec = toRowVector(val)
% Convert numeric arrays to a row vector of doubles; otherwise return empty.
    vec = [];
    if isnumeric(val) && ~isempty(val)
        vec = double(val(:).');
    end
end
