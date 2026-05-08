function result = runExperimentCore(userOverrides)
% Core execution entrypoint used by both headless script and GUI.

if nargin < 1
    userOverrides = struct();
end

user = defaultUserConfig();
user = mergeStructs(user, userOverrides);

cfg = buildSystemConfig(user);
result = struct("status", "unknown", "runFolder", "", "message", "");
conn = struct("port", "", "baudRate", cfg.serialBaud);

pump = [];
cleanupObj = onCleanup(@()safeStopAndDisconnect(pump, cfg));

try
    fprintf("\n--- LEGATO 180 CONTROL ---\n");
    [pump, conn] = connectPump(cfg.serialBaud, user.preferredPort);

    verifyVendorIdForSelectedPort(cfg.requiredVendorIdHex, conn.port, user.vidCheckMode);

    logger = initRunLogger(cfg, user, conn);
    result.runFolder = logger.runFolder;

    fprintf("Syringe Profile: %s\n", cfg.activeSyringe.label);
    fprintf("Step Volume Constant: %.6f nL/step\n", cfg.stepVolume_nL);

    doPrime = logical(user.doPrime);
    if user.interactive
        doPrime = strcmpi(strtrim(input("Prime line first at 10 uL/min? (y/n): ", "s")), "y");
    end

    if doPrime
        sendCommand(pump, cfg, "rate", 10, "u/m", logger, 0, "prime");
        sendCommand(pump, cfg, "run", logger, 0, "prime");
        if user.interactive
            input("Priming in progress. Press ENTER to stop priming...", "s");
        else
            waitSecondsWithStop(5, user, pump, cfg, logger, 0, "prime");
        end
        sendCommand(pump, cfg, "stop", logger, 0, "prime");
    end

    if strcmpi(user.mode, "calibrate")
        runCalibrationMode(pump, cfg, user, conn, logger);
    else
        runPulseMode(pump, cfg, user, conn, logger);
    end

    clear cleanupObj;
    safeStopAndDisconnect(pump, cfg);
    fprintf("Completed run successfully.\n");

    result.status = "ok";
    result.message = "Completed run successfully.";
catch ME
    if strcmp(ME.identifier, "LEGATO:UserStop")
        fprintf("\nStopped by user.\n");
        result.status = "stopped";
        result.message = ME.message;
    else
        fprintf(2, "\nERROR: %s\n", ME.message);
        result.status = "error";
        result.message = ME.message;
        % Keep MATLAB session alive on run failures and aggressively stop pump.
        try
            safeStopAndDisconnect(pump, cfg);
        catch
        end
        try
            safeEmergencyStop(conn, cfg);
        catch
        end
        fprintf(2, "Run aborted safely. Pump stop attempted and session kept alive.\n");
    end
end
end

function cfg = buildSystemConfig(user)
cfg = struct();
cfg.serialBaud = 9600;
cfg.serialTerminator = "CR";
cfg.requiredVendorIdHex = "0x1fe9";
cfg.pulseDeliveryMode = lower(string(user.pulseDeliveryMode));
cfg.commandPrefix = char(user.commandPrefix); % e.g. '' or '0'
cfg.rateCommandVerb = char(user.rateCommandVerb); % e.g. 'irate' or 'rate'
cfg.runCommandVerb = char(user.runCommandVerb);   % usually 'run'
cfg.stopCommandVerb = char(user.stopCommandVerb); % usually 'stop'
cfg.rateUnitToken = "nl/m"; % Explicit nanoliter per minute token for Legato commands.
cfg.strokeVolMin_nL = 0.05;
if cfg.pulseDeliveryMode == "bench"
    cfg.strokeVolMax_nL = Inf;
else
    cfg.strokeVolMax_nL = 10.0; % Raised physiology cap for ongoing testing at higher stroke volumes.
end
cfg.bpmMin = 60;
cfg.bpmMax = 220;
cfg.defaultSystoleDuty = 0.30;
cfg.pressureWarnPa = 100;
cfg.pressureAbortPa = 400;
cfg.stepSize_nm = 31;
cfg.logRoot = fullfile(pwd, 'logs');
cfg.commandPause_s = 0.005;   % Small pacing delay to reduce serial command burst load.
cfg.minSinusoidSegment_s = 0.04; % Limit sinusoidal command update frequency for Legato stability.
cfg.stepResolutionTolerance_nL = 1e-9;
cfg.enableTerumo1mLPhysiologyCompensation = logical(user.enableTerumo1mLPhysiologyCompensation);
cfg.terumo1mLDeliveryEfficiency = user.terumo1mLDeliveryEfficiency; % Delivered/commanded ratio for optional compensation.
cfg.enableHamilton100uLPhysiologyCompensation = logical(user.enableHamilton100uLPhysiologyCompensation);
cfg.hamilton100uLPhysiologyCompBpm = user.hamilton100uLPhysiologyCompBpm;
cfg.hamilton100uLPhysiologyCompEff = user.hamilton100uLPhysiologyCompEff;
cfg.hamilton100uLHighStrokeSv_nL = user.hamilton100uLHighStrokeSv_nL;
cfg.hamilton100uLHighStrokeGain = user.hamilton100uLHighStrokeGain;

cfg.syringeProfiles = makeSyringeProfiles(cfg.stepSize_nm);
cfg.activeSyringe = selectSyringeProfile(cfg.syringeProfiles, user.syringeProfile);
cfg.stepVolume_nL = cfg.activeSyringe.stepVolume_nL;
end

function runPulseMode(pump, cfg, user, conn, logger)
bpm = user.bpm;
requestedSv_nL = user.strokeVolume_nL;
runSeconds = user.runSeconds;
systoleDuty = user.systoleDuty;
pulseShape = lower(string(user.pulseShape));
pulseDeliveryMode = cfg.pulseDeliveryMode;

if user.interactive
    bpm = askNumeric(sprintf("Enter target BPM [%d-%d]: ", cfg.bpmMin, cfg.bpmMax), cfg.bpmMin, cfg.bpmMax);
    requestedSv_nL = askNumeric(sprintf("Enter stroke volume nL/beat [%.2f-%.2f]: ", cfg.strokeVolMin_nL, cfg.strokeVolMax_nL), cfg.strokeVolMin_nL, cfg.strokeVolMax_nL);
    runSeconds = askNumeric("Enter runtime in seconds (>= 5): ", 5, inf);

    dutyPrompt = sprintf("Enter systole duty fraction (0.1-0.8) or press ENTER for %.2f: ", cfg.defaultSystoleDuty);
    dutyRaw = strtrim(input(dutyPrompt, "s"));
    if isempty(dutyRaw)
        systoleDuty = cfg.defaultSystoleDuty;
    else
        systoleDuty = str2double(dutyRaw);
    end

    pulseShape = lower(string(strtrim(input("Pulse shape [square/sinusoidal]: ", "s"))));
    if strlength(pulseShape) == 0
        pulseShape = "square";
    end
end

validateattributes(bpm, {'numeric'}, {'real', 'finite', '>=', cfg.bpmMin, '<=', cfg.bpmMax});
validateattributes(requestedSv_nL, {'numeric'}, {'real', 'finite', '>=', cfg.strokeVolMin_nL, '<=', cfg.strokeVolMax_nL});
validateattributes(runSeconds, {'numeric'}, {'real', 'finite', '>=', 5});
validateattributes(systoleDuty, {'numeric'}, {'real', 'finite', '>=', 0.1, '<=', 0.8});

if pulseShape ~= "square" && pulseShape ~= "sinusoidal"
    error("pulseShape must be 'square' or 'sinusoidal'.");
end

rateCompensationGain = 1.0;
compensationLabel = "none";
if cfg.enableTerumo1mLPhysiologyCompensation && pulseDeliveryMode == "physiology" && strcmpi(char(user.syringeProfile), 'terumo_1mL')
    eff = cfg.terumo1mLDeliveryEfficiency;
    if ~(isfinite(eff) && eff > 0 && eff <= 1)
        error("Invalid cfg.terumo1mLDeliveryEfficiency %.6f. Expected (0, 1].", eff);
    end
    rateCompensationGain = 1 / eff;
    compensationLabel = "terumo_1mL_physiology";
elseif cfg.enableHamilton100uLPhysiologyCompensation && pulseDeliveryMode == "physiology" && strcmpi(char(user.syringeProfile), 'hamilton_100uL')
    eff = interpolateCompensationEfficiency(bpm, cfg.hamilton100uLPhysiologyCompBpm, cfg.hamilton100uLPhysiologyCompEff);
    if ~(isfinite(eff) && eff > 0 && eff <= 1)
        error("Invalid interpolated hamilton_100uL physiology efficiency %.6f. Expected (0, 1].", eff);
    end
    rateCompensationGain = 1 / eff;

    if requestedSv_nL >= cfg.hamilton100uLHighStrokeSv_nL(1) && bpm <= 150
        highStrokeGain = interpolateCompensationGain(requestedSv_nL, cfg.hamilton100uLHighStrokeSv_nL, cfg.hamilton100uLHighStrokeGain);
        rateCompensationGain = rateCompensationGain * highStrokeGain;
        compensationLabel = "hamilton_100uL_physiology_bpm_sv";
    else
        compensationLabel = "hamilton_100uL_physiology_bpm";
    end
end

[sv_nL, strokeStepCount, strokeAdjusted, strokeAdjustmentNote] = resolvePulseStrokeVolume(requestedSv_nL, cfg);
requestedFlow_nL_min = bpm * requestedSv_nL;
effectiveFlow_nL_min = bpm * sv_nL;
requestedMeanStepHz = (requestedFlow_nL_min / 60) / cfg.stepVolume_nL;
effectiveMeanStepHz = (effectiveFlow_nL_min / 60) / cfg.stepVolume_nL;
beatPeriod_s = 60 / bpm;
systoleDuration_s = beatPeriod_s * systoleDuty;
diastoleDuration_s = beatPeriod_s - systoleDuration_s;
diastoleRateFloor_nL_min = 0.1; % Shared floor for bench + physiology to avoid pump beeping at zero rate.
diastoleVolPerBeat_nL = diastoleRateFloor_nL_min * (diastoleDuration_s / 60);
if diastoleVolPerBeat_nL >= sv_nL
    error("Requested stroke volume %.4f nL/beat is too low for current duty %.3f with diastole floor %.4f nL/min.", ...
        sv_nL, systoleDuty, diastoleRateFloor_nL_min);
end

if strokeAdjusted
    warning("%s", strokeAdjustmentNote);
end

systoleVolume_nL = sv_nL - diastoleVolPerBeat_nL;
squareSystoleRate_nL_min = (systoleVolume_nL / systoleDuration_s) * 60;
commandedSquareSystoleRate_nL_min = squareSystoleRate_nL_min * rateCompensationGain;
targetBeats = max(1, round((runSeconds / 60) * bpm));
effectiveRunSeconds = targetBeats * beatPeriod_s;
sinusoidSegmentsUsed = max(2, round(user.systoleSegments));
if pulseShape == "sinusoidal"
    maxSegByTiming = max(2, floor(systoleDuration_s / cfg.minSinusoidSegment_s));
    sinusoidSegmentsUsed = min(sinusoidSegmentsUsed, maxSegByTiming);
    if sinusoidSegmentsUsed < round(user.systoleSegments)
        warning("Reducing sinusoidal segments from %d to %d to avoid command overload at %.1f BPM.", ...
            round(user.systoleSegments), sinusoidSegmentsUsed, bpm);
    end
end

fprintf("\n--- TARGET SUMMARY ---\n");
fprintf("Port: %s @ %d baud\n", conn.port, conn.baudRate);
fprintf("Mode: Pulsatile (%s)\n", pulseShape);
fprintf("Pulse Delivery Mode: %s\n", pulseDeliveryMode);
fprintf("BPM: %.2f\n", bpm);
fprintf("Requested Stroke Volume: %.4f nL/beat\n", requestedSv_nL);
fprintf("Effective Stroke Volume: %.4f nL/beat", sv_nL);
if isfinite(strokeStepCount)
    fprintf(" (%d step(s) at %.6f nL/step)\n", strokeStepCount, cfg.stepVolume_nL);
else
    fprintf("\n");
end
fprintf("Requested Mean Flow: %.4f nL/min\n", requestedFlow_nL_min);
fprintf("Effective Mean Flow: %.4f nL/min\n", effectiveFlow_nL_min);
fprintf("Requested Mean Step Frequency: %.4f Hz\n", requestedMeanStepHz);
fprintf("Effective Mean Step Frequency: %.4f Hz (using %.6f nL/step)\n", effectiveMeanStepHz, cfg.stepVolume_nL);
fprintf("Systole/Diastole: %.4f s / %.4f s\n", systoleDuration_s, diastoleDuration_s);
fprintf("Square-wave Systolic Rate: %.4f nL/min\n", squareSystoleRate_nL_min);
if rateCompensationGain ~= 1
    fprintf("Compensated Systolic Command Rate: %.4f nL/min (gain %.4f; mode=%s)\n", ...
        commandedSquareSystoleRate_nL_min, rateCompensationGain, compensationLabel);
end
fprintf("Diastole Floor Rate: %.4f nL/min\n", diastoleRateFloor_nL_min);
fprintf("Target Beats: %d (effective runtime %.3f s)\n", targetBeats, effectiveRunSeconds);

appendRunLog(logger, toc(logger.t0), 0, "summary", effectiveFlow_nL_min, "", "pulse", ...
    sprintf("bpm=%.3f;requested_sv_nL=%.6f;effective_sv_nL=%.6f;requested_flow_nL_min=%.6f;effective_flow_nL_min=%.6f;requested_meanStepHz=%.6f;effective_meanStepHz=%.6f;stroke_steps=%d;stroke_adjusted=%d;pulseDeliveryMode=%s;systoleVol_nL=%.6f;diastoleRate_nL_min=%.6f;rateCompGain=%.6f;compMode=%s;targetBeats=%d;effectiveRun_s=%.6f", ...
    bpm, requestedSv_nL, sv_nL, requestedFlow_nL_min, effectiveFlow_nL_min, requestedMeanStepHz, effectiveMeanStepHz, strokeStepCountForLog(strokeStepCount), logical(strokeAdjusted), char(pulseDeliveryMode), systoleVolume_nL, diastoleRateFloor_nL_min, rateCompensationGain, char(compensationLabel), targetBeats, effectiveRunSeconds));

if effectiveFlow_nL_min < 10 || effectiveFlow_nL_min > 45
    warning("Effective flow %.3f nL/min is outside the 10-45 nL/min planning window.", effectiveFlow_nL_min);
end

estPressurePa = estimatePressurePa(effectiveFlow_nL_min);
if estPressurePa >= cfg.pressureAbortPa
    error("Estimated pressure %.2f Pa exceeds abort threshold %.2f Pa.", estPressurePa, cfg.pressureAbortPa);
elseif estPressurePa >= cfg.pressureWarnPa
    warning("Estimated pressure %.2f Pa exceeds warning threshold %.2f Pa.", estPressurePa, cfg.pressureWarnPa);
end

if user.interactive
    input("Press ENTER to start pulsatile perfusion...", "s");
end

t0 = tic;
isContinuousBenchPulse = pulseDeliveryMode == "bench";
if isContinuousBenchPulse
    sendCommand(pump, cfg, "rate", diastoleRateFloor_nL_min, cfg.rateUnitToken, logger, 0, "pulse");
    sendCommand(pump, cfg, "run", logger, 0, "pulse");
end
for beatIndex = 1:targetBeats
    abortIfStopRequested(user, pump, cfg, logger, beatIndex, "pulse");

    if pulseShape == "sinusoidal"
        if ~isContinuousBenchPulse
            sendCommand(pump, cfg, "run", logger, beatIndex, "pulse");
        end
        runSinusoidalBeat(pump, cfg, user, t0, beatIndex, beatPeriod_s, systoleDuration_s, systoleVolume_nL, sinusoidSegmentsUsed, rateCompensationGain, logger);
    else
        logLine(beatIndex, "systole", commandedSquareSystoleRate_nL_min, toc(t0));
        sendCommand(pump, cfg, "rate", commandedSquareSystoleRate_nL_min, cfg.rateUnitToken, logger, beatIndex, "pulse");
        if ~isContinuousBenchPulse
            sendCommand(pump, cfg, "run", logger, beatIndex, "pulse");
        end
        waitWithDrift(t0, beatIndex, beatPeriod_s, systoleDuration_s, user, pump, cfg, logger, beatIndex, "pulse");
    end

    if isContinuousBenchPulse
        logLine(beatIndex, "diastole", diastoleRateFloor_nL_min, toc(t0));
        sendCommand(pump, cfg, "rate", diastoleRateFloor_nL_min, cfg.rateUnitToken, logger, beatIndex, "pulse");
    else
        logLine(beatIndex, "diastole", diastoleRateFloor_nL_min, toc(t0));
        sendCommand(pump, cfg, "rate", diastoleRateFloor_nL_min, cfg.rateUnitToken, logger, beatIndex, "pulse");
        sendCommand(pump, cfg, "stop", logger, beatIndex, "pulse");
    end
    waitWithDrift(t0, beatIndex, beatPeriod_s, beatPeriod_s, user, pump, cfg, logger, beatIndex, "pulse");
end

sendCommand(pump, cfg, "stop", logger, beatIndex, "pulse");
end

function runCalibrationMode(pump, cfg, user, conn, logger)
rate_uL_min = user.calibRate_uL_min;
duration_s = user.calibDuration_s;
density_g_mL = user.fluidDensity_g_mL;
measuredMass_g = user.measuredMass_g;

if user.interactive
    rate_uL_min = askNumeric("Calibration rate in uL/min (>0): ", eps, inf);
    duration_s = askNumeric("Calibration duration in seconds (>=10): ", 10, inf);
    density_g_mL = askNumeric("Fluid density in g/mL (0.8-1.2 typical): ", 0.8, 1.2);
    input("Tare balance and place collection vial. Press ENTER to start calibration dispense...", "s");
end

validateattributes(rate_uL_min, {'numeric'}, {'real', 'finite', '>', 0});
validateattributes(duration_s, {'numeric'}, {'real', 'finite', '>=', 10});
validateattributes(density_g_mL, {'numeric'}, {'real', 'finite', '>', 0});

fprintf("\n--- CALIBRATION MODE ---\n");
fprintf("Port: %s @ %d baud\n", conn.port, conn.baudRate);
fprintf("Syringe: %s\n", cfg.activeSyringe.label);
fprintf("Current Step Constant: %.6f nL/step\n", cfg.stepVolume_nL);
fprintf("Dispense Command: %.4f uL/min for %.2f s\n", rate_uL_min, duration_s);

appendRunLog(logger, toc(logger.t0), 0, "calibration", 0, "", "calibrate", ...
    sprintf("rate_uL_min=%.6f;duration_s=%.3f;density_g_mL=%.6f", rate_uL_min, duration_s, density_g_mL));

sendCommand(pump, cfg, "rate", rate_uL_min, "u/m", logger, 0, "calibrate");
sendCommand(pump, cfg, "run", logger, 0, "calibrate");
waitSecondsWithStop(duration_s, user, pump, cfg, logger, 0, "calibrate");
sendCommand(pump, cfg, "stop", logger, 0, "calibrate");

expected_uL = rate_uL_min * (duration_s / 60);

if user.interactive
    measuredMass_g = askNumeric("Enter measured collected mass in grams: ", eps, inf);
end

if ~isfinite(measuredMass_g) || measuredMass_g <= 0
    fprintf("Measured mass not provided. Expected dispense only: %.4f uL\n", expected_uL);
    fprintf("Set measuredMass_g and rerun mode='calibrate' to compute corrected constant.\n");
    return;
end

measured_uL = (measuredMass_g / density_g_mL) * 1000;
correctionFactor = measured_uL / expected_uL;
suggestedStep_nL = cfg.stepVolume_nL * correctionFactor;

fprintf("Expected Volume: %.4f uL\n", expected_uL);
fprintf("Measured Volume: %.4f uL\n", measured_uL);
fprintf("Correction Factor (measured/expected): %.6f\n", correctionFactor);
fprintf("Suggested step constant: %.6f nL/step\n", suggestedStep_nL);

appendRunLog(logger, toc(logger.t0), 0, "calibration_result", 0, "", "calibrate", ...
    sprintf("expected_uL=%.6f;measured_uL=%.6f;factor=%.6f;suggested_nL_step=%.9f", ...
    expected_uL, measured_uL, correctionFactor, suggestedStep_nL));
end

function runSinusoidalBeat(pump, cfg, user, t0, beatIndex, beatPeriod_s, systoleDuration_s, systoleVolume_nL, nSeg, rateCompensationGain, logger)
nSeg = max(4, round(nSeg));
peakRate_nL_min = (systoleVolume_nL * 60 * pi) / (2 * systoleDuration_s);

for k = 1:nSeg
    abortIfStopRequested(user, pump, cfg, logger, beatIndex, "pulse");
    segStart = (k - 1) / nSeg * systoleDuration_s;
    segEnd = k / nSeg * systoleDuration_s;
    segMid = (segStart + segEnd) / 2;
    rateNow = peakRate_nL_min * sin(pi * segMid / systoleDuration_s);
    rateNow = max(rateNow, 0);
    rateNow = rateNow * rateCompensationGain;

    logLine(beatIndex, "systole", rateNow, toc(t0));
    sendCommand(pump, cfg, "rate", rateNow, cfg.rateUnitToken, logger, beatIndex, "pulse");
    waitWithDrift(t0, beatIndex, beatPeriod_s, segEnd, user, pump, cfg, logger, beatIndex, "pulse");
end
end

function verifyVendorIdForSelectedPort(requiredVidHex, selectedPort, vidCheckMode)
% Strict handshake: selected serial node must map to required USB vendor ID.
selectedPort = char(selectedPort);
mode = lower(char(vidCheckMode));

if strcmp(mode, 'off')
    warning("VID handshake disabled by configuration.");
    return;
end

if ismac
    if strcmp(mode, 'strict')
        verifyVendorIdMac(requiredVidHex, selectedPort);
    else
        try
            verifyVendorIdMac(requiredVidHex, selectedPort);
        catch ME
            warning("Strict macOS VID check failed (%s). Trying relaxed fallback.", ME.message);
            verifyVendorIdMacRelaxed(requiredVidHex);
            warning("Using relaxed macOS VID handshake for development. Set user.vidCheckMode='strict' before lab deployment.");
        end
    end
elseif ispc
    verifyVendorIdWindows(requiredVidHex, selectedPort);
else
    error("VID handshake not implemented on this OS. Supported: macOS, Windows.");
end
end

function verifyVendorIdMacRelaxed(requiredVidHex)
% Development fallback: confirms required VID exists in macOS USB metadata.
requiredNorm = char(normalizeHex(requiredVidHex));
requiredDec = num2str(hex2dec(requiredNorm));
found = false;

% Source 1: system_profiler output.
[statusSp, outSp] = system("system_profiler SPUSBDataType");
if statusSp == 0
    found = usbTextContainsVid(outSp, requiredNorm, requiredDec);
end

% Source 2: ioreg USB tree (often exposes idVendor even when system_profiler is sparse).
if ~found
    [statusIo, outIo] = system("ioreg -p IOUSB -l -w 0");
    if statusIo == 0
        found = usbTextContainsVid(outIo, requiredNorm, requiredDec);
    end
end

% Development fallback for this bench setup: known Pico signature on macOS.
if ~found && statusSp == 0
    outLower = lower(char(outSp));
    hasPicoSignature = ~isempty(strfind(outLower, 'serial number:')) && ~isempty(strfind(outLower, 'd105402')) ...
        && ~isempty(strfind(outLower, 'manufacturer:')) && ~isempty(strfind(outLower, 'syringe pump'));
    if hasPicoSignature
        warning("Relaxed VID matcher used Pico signature fallback (D105402 + Syringe Pump). Confirm VID in strict mode before deployment.");
        found = true;
    end
end

if ~found
    error("Relaxed VID handshake failed: required VID %s not found in USB tree.", requiredVidHex);
end

fprintf("Relaxed macOS VID handshake passed: %s found in USB metadata.\n", requiredVidHex);
end

function tf = usbTextContainsVid(rawText, requiredNorm, requiredDec)
txt = lower(char(rawText));

% Match explicit hex VID token with optional 0x prefix.
hexPattern = ['(?<![0-9a-f])(?:0x)?' regexptranslate('escape', requiredNorm) '(?![0-9a-f])'];
if ~isempty(regexpi(txt, hexPattern, 'once'))
    tf = true;
    return;
end

% Match common decimal idVendor representation in ioreg trees.
decPattern = ['(?<![0-9])' regexptranslate('escape', requiredDec) '(?![0-9])'];
if ~isempty(strfind(txt, 'idvendor')) && ~isempty(regexpi(txt, decPattern, 'once'))
    tf = true;
    return;
end

tf = false;
end

function verifyVendorIdMac(requiredVidHex, selectedPort)
[status, out] = system("ioreg -r -c IOSerialBSDClient -l -w 0");
if status ~= 0
    error("VID handshake failed: unable to query IOSerialBSDClient tree.");
end

blocks = splitIoRegBlocks(out);
portBlock = "";
for i = 1:numel(blocks)
    blk = blocks{i};
    if ~isempty(strfind(lower(char(blk)), lower(char(selectedPort))))
        portBlock = char(blk);
        break;
    end
end

if isempty(portBlock)
    error("VID handshake failed: selected port %s not found in ioreg serial map.", selectedPort);
end

vid = extractVendorIdFromBlock(char(portBlock));
if isempty(char(vid))
    error('VID handshake failed: vendor ID not discoverable for selected port %s. Ensure device exposes idVendor in IOSerialBSDClient properties.', selectedPort);
end

if ~strcmpi(normalizeHex(vid), normalizeHex(requiredVidHex))
    error("VID mismatch for selected port %s. Found %s, required %s.", selectedPort, vid, requiredVidHex);
end

fprintf("VID handshake passed for %s: %s\n", selectedPort, vid);
end

function verifyVendorIdWindows(requiredVidHex, selectedPort)
vidTag = ['VID_' upper(char(normalizeHex(requiredVidHex)))];
port = upper(char(selectedPort));

% Use PowerShell CIM query and require both COM port name and VID match.
ps = [ ...
    "$port='" port "'; " ...
    "$vid='" vidTag "'; " ...
    "$dev=Get-CimInstance Win32_PnPEntity | Where-Object { $_.Name -like ('*(' + $port + ')*') -and $_.PNPDeviceID -like ('*' + $vid + '*') } | Select-Object -First 1; " ...
    "if($dev){$dev.PNPDeviceID}" ...
    ];

cmd = "powershell -NoProfile -ExecutionPolicy Bypass -Command """ + ps + """";
[status, out] = system(cmd);

if status ~= 0
    error("VID handshake failed on Windows while querying PnP entities for %s.", selectedPort);
end

pnpId = strtrim(out);
if isempty(pnpId)
    error("VID mismatch or port mismatch: could not find %s with %s.", selectedPort, vidTag);
end

fprintf("VID handshake passed for %s: %s\n", selectedPort, pnpId);
end

function blocks = splitIoRegBlocks(ioText)
raw = regexp(ioText, '(?=\n\s*\+-o )', 'split');
if isempty(raw)
    blocks = {ioText};
else
    blocks = raw;
end
end

function vid = extractVendorIdFromBlock(blockText)
vid = '';
t = regexp(blockText, '"idVendor"\s*=\s*(0x[0-9a-fA-F]+)', 'tokens', 'once');
if ~isempty(t)
    vid = char(t{1});
    return;
end

% Fallback for some device trees that expose vendor IDs with a different key.
t = regexp(blockText, '"USB Vendor ID"\s*=\s*(0x[0-9a-fA-F]+)', 'tokens', 'once');
if ~isempty(t)
    vid = char(t{1});
end
end

function h = normalizeHex(hexIn)
h = lower(strtrim(char(hexIn)));
h = regexprep(h, '^0x', '');
h = regexprep(h, '^0+', '');
if isempty(h)
    h = '0';
end
end

function logger = initRunLogger(cfg, user, conn)
if ~exist(cfg.logRoot, 'dir')
    mkdir(cfg.logRoot);
end

runStamp = datestr(now, 'yyyymmdd_HHMMSS');
runFolder = fullfile(cfg.logRoot, [runStamp '_' lower(char(user.mode))]);
mkdir(runFolder);

csvPath = fullfile(runFolder, 'events.csv');
header = 'time_s,beat,phase,rate_nL_min,command,mode,message\n';
writeTextFile(csvPath, header);

metaPath = fullfile(runFolder, 'metadata.txt');
metaText = sprintf(['timestamp=%s\n' ...
    'port=%s\n' ...
    'baud=%d\n' ...
    'mode=%s\n' ...
    'syringe_profile=%s\n' ...
    'step_volume_nL=%.9f\n'], ...
    datestr(now, 'yyyy-mm-dd HH:MM:SS'), char(conn.port), conn.baudRate, ...
    char(user.mode), char(user.syringeProfile), cfg.stepVolume_nL);
writeTextFile(metaPath, metaText);

logger = struct('runFolder', runFolder, 'csvPath', csvPath, 't0', tic);
end

function appendRunLog(logger, tSec, beatIdx, phase, rate_nL_min, command, mode, message)
line = sprintf("%.6f,%d,%s,%.9f,%s,%s,%s\n", ...
    tSec, beatIdx, sanitizeCsvField(phase), rate_nL_min, ...
    sanitizeCsvField(command), sanitizeCsvField(mode), sanitizeCsvField(message));

fid = fopen(logger.csvPath, "a");
if fid == -1
    warning("Could not append run log to %s", logger.csvPath);
    return;
end
fprintf(fid, "%s", line);
fclose(fid);
end

function out = sanitizeCsvField(in)
if isnumeric(in)
    out = num2str(in);
elseif isstring(in)
    out = char(in);
elseif ischar(in)
    out = in;
else
    out = char(string(in));
end
out = strrep(out, '"', '''');
out = strrep(out, ',', ';');
out = strrep(out, sprintf('\n'), ' ');
out = strrep(out, sprintf('\r'), ' ');
end

function sendCommand(pumpObj, cfg, op, varargin)
logger = [];
beatIdx = 0;
mode = "";

prefix = strtrim(char(cfg.commandPrefix));
if isempty(prefix)
    prefix = '';
else
    prefix = [prefix ' '];
end

switch lower(op)
    case "rate"
        if numel(varargin) < 2
            error("rate command requires value and unit token.");
        end
        value = varargin{1};
        unitToken = varargin{2};
        cmd = sprintf('%s%s %.6f %s', prefix, cfg.rateCommandVerb, value, unitToken);
        if numel(varargin) >= 3
            logger = varargin{3};
        end
        if numel(varargin) >= 4
            beatIdx = varargin{4};
        end
        if numel(varargin) >= 5
            mode = varargin{5};
        end
        rateForLog = value;
    case "run"
        cmd = sprintf('%s%s', prefix, cfg.runCommandVerb);
        if numel(varargin) >= 1
            logger = varargin{1};
        end
        if numel(varargin) >= 2
            beatIdx = varargin{2};
        end
        if numel(varargin) >= 3
            mode = varargin{3};
        end
        rateForLog = NaN;
    case "stop"
        cmd = sprintf('%s%s', prefix, cfg.stopCommandVerb);
        if numel(varargin) >= 1
            logger = varargin{1};
        end
        if numel(varargin) >= 2
            beatIdx = varargin{2};
        end
        if numel(varargin) >= 3
            mode = varargin{3};
        end
        rateForLog = NaN;
    otherwise
        error("Unknown command operation: %s", op);
end

sent = false;
for attempt = 1:2
    try
        writeline(pumpObj, cmd);
        sent = true;
        break;
    catch MEw
        if attempt == 1
            pause(0.05);
        else
            rethrow(MEw);
        end
    end
end

if sent && isfield(cfg, "commandPause_s") && cfg.commandPause_s > 0
    pause(cfg.commandPause_s);
end

if ~isempty(logger)
    appendRunLog(logger, toc(logger.t0), beatIdx, "command", rateForLog, cmd, mode, "");
end
end

function value = askNumeric(prompt, minVal, maxVal)
raw = input(prompt, "s");
value = str2double(strtrim(raw));
if ~isfinite(value) || value < minVal || value > maxVal
    error("Invalid input. Expected numeric value in [%.4g, %.4g].", minVal, maxVal);
end
end

function waitWithDrift(t0, beatIndex, beatPeriod, phaseEndInBeat, user, pump, cfg, logger, beatIdx, modeName)
targetT = (beatIndex - 1) * beatPeriod + phaseEndInBeat;
while true
    abortIfStopRequested(user, pump, cfg, logger, beatIdx, modeName);
    remaining = targetT - toc(t0);
    if remaining <= 0
        break;
    end
    pause(min(remaining, 0.02));
end
end

function waitSecondsWithStop(duration_s, user, pump, cfg, logger, beatIdx, modeName)
tStart = tic;
while toc(tStart) < duration_s
    abortIfStopRequested(user, pump, cfg, logger, beatIdx, modeName);
    remaining = duration_s - toc(tStart);
    pause(min(remaining, 0.02));
end
end

function abortIfStopRequested(user, pump, cfg, logger, beatIdx, modeName)
processUi(user);
if shouldStop(user)
    appendRunLog(logger, toc(logger.t0), beatIdx, "stop_request", NaN, "", modeName, "GUI stop requested");
    try
        sendCommand(pump, cfg, "stop", logger, beatIdx, modeName);
    catch
    end
    error("LEGATO:UserStop", "Run stopped by user request.");
end
end

function tf = shouldStop(user)
tf = false;
if isfield(user, "stopRequestedFcn") && ~isempty(user.stopRequestedFcn)
    try
        tf = logical(user.stopRequestedFcn());
    catch
        tf = false;
    end
end
end

function processUi(user)
if isfield(user, "processUiFcn") && ~isempty(user.processUiFcn)
    try
        user.processUiFcn();
    catch
    end
end
end

function estPa = estimatePressurePa(flow_nL_min)
% Hagen-Poiseuille pressure drop estimate for current benchtop tubing setup.
mu_pa_s = 0.001;      % Water / E3 dynamic viscosity (Pa.s)
length_m = 0.375;     % Total path length: 15cm needle holder + 22.5cm tubing = 37.5cm (m)
radius_m = 0.00035;   % Tubing internal radius (m) for 0.7 mm ID

flow_m3_s = max(flow_nL_min, 0) * 1e-12 / 60;
estPa = (8 * mu_pa_s * length_m * flow_m3_s) / (pi * radius_m^4);
end

function logLine(beatIndex, phaseName, rate_nL_min, elapsed_s)
fprintf("t=%.3fs | beat=%d | phase=%s | rate=%.4f nL/min\n", elapsed_s, beatIndex, phaseName, rate_nL_min);
end

function safeStopAndDisconnect(pumpObj, cfg)
if isempty(pumpObj)
    return;
end

try
    prefix = strtrim(char(cfg.commandPrefix));
    if isempty(prefix)
        stopCmd = char(cfg.stopCommandVerb);
    else
        stopCmd = sprintf('%s %s', prefix, cfg.stopCommandVerb);
    end
    writeline(pumpObj, stopCmd);
catch
end

try
    delete(pumpObj);
catch
end
end

function safeEmergencyStop(conn, cfg)
% Secondary stop path used when active serial object is invalid/disconnected.
if isempty(conn) || ~isfield(conn, "port")
    return;
end

port = char(conn.port);
if isempty(strtrim(port))
    return;
end

tmp = [];
try
    tmp = serialport(port, cfg.serialBaud, "Timeout", 1);
    configureTerminator(tmp, char(cfg.serialTerminator));

    prefix = strtrim(char(cfg.commandPrefix));
    if isempty(prefix)
        stopCmd = char(cfg.stopCommandVerb);
    else
        stopCmd = sprintf('%s %s', prefix, cfg.stopCommandVerb);
    end

    writeline(tmp, stopCmd);
    pause(0.05);
    writeline(tmp, stopCmd);
catch
end

try
    if ~isempty(tmp)
        delete(tmp);
    end
catch
end
end

function profiles = makeSyringeProfiles(stepSize_nm)
profiles = struct();

profiles.hamilton_100uL = struct( ...
    "label", "100 uL Hamilton Glass (primary)", ...
    "diameter_mm", 1.46, ...
    "stepVolume_nL", 0.0519, ...
    "pulseStrokeRounding", false, ...
    "notes", "Primary profile: fixed provisional constant");

profiles.terumo_1mL = struct( ...
    "label", "1 mL Terumo Plastic (baseline)", ...
    "diameter_mm", 4.70, ...
    "stepVolume_nL", stepVolumeFromDiameter(4.70, stepSize_nm), ...
    "pulseStrokeRounding", true, ...
    "notes", "Baseline profile from geometry");

profiles.terumo_10mL = struct( ...
    "label", "10 mL Terumo Plastic (baseline)", ...
    "diameter_mm", 14.50, ...
    "stepVolume_nL", stepVolumeFromDiameter(14.50, stepSize_nm), ...
    "pulseStrokeRounding", false, ...
    "notes", "Baseline profile from geometry");
end

function profile = selectSyringeProfile(profiles, profileName)
name = char(profileName);
if ~isfield(profiles, name)
    error("Unknown syringe profile '%s'.", name);
end
profile = profiles.(name);
end

function stepCount = strokeStepCountForLog(stepCountIn)
stepCount = stepCountIn;
if ~isfinite(stepCount)
    stepCount = -1;
end
end

function [effectiveSv_nL, stepCount, wasAdjusted, adjustmentNote] = resolvePulseStrokeVolume(requestedSv_nL, cfg)
effectiveSv_nL = requestedSv_nL;
stepCount = NaN;
wasAdjusted = false;
adjustmentNote = "";

if ~isfield(cfg.activeSyringe, "pulseStrokeRounding") || ~logical(cfg.activeSyringe.pulseStrokeRounding)
    return;
end

stepVolume_nL = cfg.stepVolume_nL;
if ~(isfinite(stepVolume_nL) && stepVolume_nL > 0)
    return;
end

stepCount = max(1, round(requestedSv_nL / stepVolume_nL));
if isfinite(cfg.strokeVolMax_nL)
    maxStepCount = floor((cfg.strokeVolMax_nL + cfg.stepResolutionTolerance_nL) / stepVolume_nL);
    if maxStepCount < 1
        error("Configured stroke maximum %.4f nL is below one achievable pump step of %.6f nL.", cfg.strokeVolMax_nL, stepVolume_nL);
    end
    stepCount = min(stepCount, maxStepCount);
end

effectiveSv_nL = stepCount * stepVolume_nL;
wasAdjusted = abs(effectiveSv_nL - requestedSv_nL) > max(cfg.stepResolutionTolerance_nL, 1e-6 * stepVolume_nL);
if wasAdjusted
    adjustmentNote = sprintf("Requested stroke volume %.4f nL/beat rounded to %.4f nL/beat (%d step(s) at %.6f nL/step).", ...
        requestedSv_nL, effectiveSv_nL, stepCount, stepVolume_nL);
end
end

function stepVolume_nL = stepVolumeFromDiameter(diameter_mm, stepSize_nm)
area_mm2 = pi * (diameter_mm / 2)^2;
stepLength_mm = stepSize_nm * 1e-6;
stepVolume_uL = area_mm2 * stepLength_mm;
stepVolume_nL = stepVolume_uL * 1000;
end

function eff = interpolateCompensationEfficiency(bpm, bpmKnots, effKnots)
bpmKnots = double(bpmKnots(:)');
effKnots = double(effKnots(:)');

if numel(bpmKnots) < 2 || numel(effKnots) ~= numel(bpmKnots)
    error("Compensation knot vectors must be same length with at least two points.");
end
if any(~isfinite(bpmKnots)) || any(~isfinite(effKnots))
    error("Compensation knot vectors must be finite.");
end
if any(diff(bpmKnots) <= 0)
    error("Compensation BPM knots must be strictly increasing.");
end
if any(effKnots <= 0) || any(effKnots > 1)
    error("Compensation efficiency knots must be within (0, 1].");
end

bpmClamped = min(max(double(bpm), bpmKnots(1)), bpmKnots(end));
eff = interp1(bpmKnots, effKnots, bpmClamped, "linear");
end

function gain = interpolateCompensationGain(value, knotValues, gainKnots)
knotValues = double(knotValues(:)');
gainKnots = double(gainKnots(:)');

if numel(knotValues) < 2 || numel(gainKnots) ~= numel(knotValues)
    error("Compensation gain knot vectors must be same length with at least two points.");
end
if any(~isfinite(knotValues)) || any(~isfinite(gainKnots))
    error("Compensation gain knot vectors must be finite.");
end
if any(diff(knotValues) <= 0)
    error("Compensation gain knots must be strictly increasing.");
end
if any(gainKnots <= 0)
    error("Compensation gain knots must be positive.");
end

valueClamped = min(max(double(value), knotValues(1)), knotValues(end));
gain = interp1(knotValues, gainKnots, valueClamped, "linear");
end

function out = mergeStructs(base, overrides)
out = base;
if isempty(overrides)
    return;
end

f = fieldnames(overrides);
for i = 1:numel(f)
    out.(f{i}) = overrides.(f{i});
end
end

function user = defaultUserConfig()
user = struct();
user.mode = "pulse";
user.interactive = false;
user.doPrime = false;
user.preferredPort = ""; % Optional explicit serial port (e.g., COM4 or /dev/tty.usbmodemXXXX)
user.vidCheckMode = "auto"; % "auto", "strict", or "off"
user.commandPrefix = ""; % Empty for direct commands; set to "0" for address-prefixed firmware.
user.rateCommandVerb = "irate"; % Legato-style infusion rate verb.
user.runCommandVerb = "run";
user.stopCommandVerb = "stop";
user.stopRequestedFcn = [];
user.processUiFcn = [];
user.syringeProfile = "terumo_1mL";
user.pulseDeliveryMode = "physiology"; % "physiology" (zebrafish default) or "bench" (high-flow diagnostics)
user.enableTerumo1mLPhysiologyCompensation = true;
user.terumo1mLDeliveryEfficiency = 0.667;
user.enableHamilton100uLPhysiologyCompensation = true;
% Empirical physiology pulse efficiency for 100 uL syringe from pump-screen tests.
user.hamilton100uLPhysiologyCompBpm = [60 140 150 165 180];
user.hamilton100uLPhysiologyCompEff = [0.704 0.724 0.490 0.408 0.302];
user.hamilton100uLHighStrokeSv_nL = [2 5 10];
user.hamilton100uLHighStrokeGain = [1.155 1.177 1.190];

user.bpm = 150;
user.strokeVolume_nL = 0.50;
user.runSeconds = 30;
user.systoleDuty = 0.30;
user.pulseShape = "square";
user.systoleSegments = 12;

user.calibRate_uL_min = 1.0;
user.calibDuration_s = 120;
user.fluidDensity_g_mL = 0.997;
user.measuredMass_g = NaN;
end

function writeTextFile(path, textData)
fid = fopen(path, "w");
if fid == -1
    error("Could not write file: %s", path);
end
fprintf(fid, "%s", textData);
fclose(fid);
end
