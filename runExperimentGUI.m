function runExperimentGUI()
% Single-window GUI with iterative UX polish for zebrafish perfusion control.

baseFont = 12;
palette = makePalette();

% Auto-center window on screen
screenSize = get(0, 'ScreenSize'); % [left bottom width height]
screenWidth = screenSize(3);
screenHeight = screenSize(4);
windowWidth = 560;
windowHeight = min(830, screenHeight - 100); % Leave 100px margin for taskbar/top bar
windowLeft = max(40, (screenWidth - windowWidth) / 2);
windowTop = max(40, (screenHeight - windowHeight) / 2);

f = uifigure( ...
    "Name", "Zebrafish Perfusion Control", ...
    "Position", [windowLeft windowTop windowWidth windowHeight], ...
    "Color", palette.FigureBg, ...
    "CloseRequestFcn", @onCloseFigure);

g = uigridlayout(f, [28 2]);
g.RowHeight = {28, 22, 22, 22, 22, 22, 22, 28, 22, 22, 22, 22, 22, 22, 28, 22, 22, 28, 22, 22, 22, 30, 22, 22, 22, 70, 28, 22};
g.ColumnWidth = {220, '1x'};
g.Padding = [12 12 12 12];
g.RowSpacing = 4;
g.ColumnSpacing = 8;
g.BackgroundColor = palette.FigureBg;

sectionLabel = uilabel(g, "Text", "MAIN SETTINGS", "FontSize", baseFont + 1, "FontColor", [0.60 0.65 0.70], "FontWeight", "bold");
sectionLabel.Layout.Row = 1;
sectionLabel.Layout.Column = [1 2];

makeHelpLabel(g, 2, "Mode", @onHelpMode, baseFont, palette);
ddMode = uidropdown(g, "Items", {'pulse', 'smooth'}, "Value", 'pulse', "FontSize", baseFont);
ddMode.Tooltip = "Choose pulse mode for waveform experiments or smooth mode for continuous flow.";
ddMode.Layout.Row = 2;
ddMode.Layout.Column = 2;
styleInputControl(ddMode, palette);

makeHelpLabel(g, 3, "Pulse Delivery Mode", @onHelpPulseDelivery, baseFont, palette);
ddPulseDelivery = uidropdown(g, "Items", {'physiology', 'bench'}, "Value", 'physiology', "ValueChangedFcn", @onPulseDeliveryModeChanged, "FontSize", baseFont);
ddPulseDelivery.Tooltip = "Physiology uses stop-based diastole; bench uses a diastolic floor for diagnostics.";
ddPulseDelivery.Layout.Row = 3;
ddPulseDelivery.Layout.Column = 2;
styleInputControl(ddPulseDelivery, palette);

makeHelpLabel(g, 4, "Pulse Preset", @onHelpPreset, baseFont, palette);
ddPreset = uidropdown(g, "Items", {'custom', 'zebrafish_48hpf', 'zebrafish_72hpf', 'zebrafish_96hpf'}, "Value", 'zebrafish_48hpf', "ValueChangedFcn", @onPresetChanged, "FontSize", baseFont);
ddPreset.Tooltip = "Apply research-validated defaults for developmental stage experiments.";
ddPreset.Layout.Row = 4;
ddPreset.Layout.Column = 2;
styleInputControl(ddPreset, palette);

makeHelpLabel(g, 5, "Syringe Profile", @onHelpSyringe, baseFont, palette);
ddSyr = uidropdown(g, "Items", {'hamilton_100uL', 'terumo_1mL', 'terumo_10mL'}, "Value", 'terumo_1mL', "ValueChangedFcn", @onSyringeChanged, "FontSize", baseFont);
ddSyr.Tooltip = "Sets syringe geometry used for step-size and effective stroke calculations.";
ddSyr.Layout.Row = 5;
ddSyr.Layout.Column = 2;
styleInputControl(ddSyr, palette);

makeStandardLabel(g, 6, "Preferred Port (optional)", baseFont, palette);
efPort = uieditfield(g, "text", "Value", "", "Placeholder", "COM4 or /dev/tty.usbmodem...", "FontSize", baseFont);
efPort.Tooltip = "Optional serial port override. Leave empty to auto-select.";
efPort.Layout.Row = 6;
efPort.Layout.Column = 2;
styleInputControl(efPort, palette);

makeHelpLabel(g, 7, "Prime First", @onHelpPrime, baseFont, palette);
cbPrime = uicheckbox(g, "Value", false, "Text", "Prime at 10 uL/min", "FontSize", baseFont);
cbPrime.Tooltip = "Run a short prime before experiment start.";
cbPrime.Layout.Row = 7;
cbPrime.Layout.Column = 2;

sectionLabel2 = uilabel(g, "Text", "PULSE VARIABLES", "FontSize", baseFont + 1, "FontColor", [0.60 0.65 0.70], "FontWeight", "bold");
sectionLabel2.Layout.Row = 8;
sectionLabel2.Layout.Column = [1 2];

makeHelpLabel(g, 9, "BPM", @onHelpBpm, baseFont, palette);
efBpm = uieditfield(g, "numeric", "Value", 150, "Limits", [60 220], "FontSize", baseFont);
efBpm.Tooltip = "Beats per minute. Combined with stroke volume, this sets mean flow.";
efBpm.Layout.Row = 9;
efBpm.Layout.Column = 2;
styleInputControl(efBpm, palette);

makeHelpLabel(g, 10, "Stroke Volume (nL/beat)", @onHelpSv, baseFont, palette);
efSv = uieditfield(g, "numeric", "Value", 0.50, "Limits", [0.05 10.0], "FontSize", baseFont);
efSv.Tooltip = "Theoretical stroke target before syringe-step rounding.";
efSv.Layout.Row = 10;
efSv.Layout.Column = 2;
styleInputControl(efSv, palette);

makeHelpLabel(g, 11, "Run Time (s)", @onHelpRuntime, baseFont, palette);
efRun = uieditfield(g, "numeric", "Value", 30, "Limits", [5 Inf], "FontSize", baseFont);
efRun.Tooltip = "Total run duration in seconds.";
efRun.Layout.Row = 11;
efRun.Layout.Column = 2;
styleInputControl(efRun, palette);

makeHelpLabel(g, 12, "Systole Duty", @onHelpDuty, baseFont, palette);
efDuty = uieditfield(g, "numeric", "Value", 0.30, "Limits", [0.1 0.8], "FontSize", baseFont);
efDuty.Tooltip = "Fraction of each beat spent in systole. Typical embryonic target is around 0.3.";
efDuty.Layout.Row = 12;
efDuty.Layout.Column = 2;
styleInputControl(efDuty, palette);

makeHelpLabel(g, 13, "Pulse Shape", @onHelpShape, baseFont, palette);
ddShape = uidropdown(g, "Items", {'square', 'sinusoidal'}, "Value", 'square', "FontSize", baseFont);
ddShape.Tooltip = "Square is simple and robust. Sinusoidal is smoother and often more physiologic.";
ddShape.Layout.Row = 13;
ddShape.Layout.Column = 2;
styleInputControl(ddShape, palette);

makeHelpLabel(g, 14, "Systole Segments", @onHelpSegments, baseFont, palette);
efSeg = uieditfield(g, "numeric", "Value", 12, "Limits", [4 100], "RoundFractionalValues", true, "FontSize", baseFont);
efSeg.Tooltip = "Used for sinusoidal mode: number of systolic update segments.";
efSeg.Layout.Row = 14;
styleInputControl(efSeg, palette);

sectionLabel3 = uilabel(g, "Text", "SMOOTH VARIABLES", "FontSize", baseFont + 1, "FontColor", [0.60 0.65 0.70], "FontWeight", "bold");
sectionLabel3.Layout.Row = 15;
sectionLabel3.Layout.Column = [1 2];

makeHelpLabel(g, 16, "Smooth Flow Rate (uL/min)", @onHelpCalRate, baseFont, palette);
efCrate = uieditfield(g, "numeric", "Value", 1.0, "Limits", [eps Inf], "FontSize", baseFont);
efCrate.Tooltip = "Steady infusion rate for smooth mode.";
efCrate.Layout.Row = 16;
efCrate.Layout.Column = 2;
styleInputControl(efCrate, palette);

makeHelpLabel(g, 17, "Smooth Duration (s)", @onHelpCalDuration, baseFont, palette);
efCdur = uieditfield(g, "numeric", "Value", 120, "Limits", [10 Inf], "FontSize", baseFont);
efCdur.Tooltip = "Duration for smooth-flow dispense.";
efCdur.Layout.Row = 17;
efCdur.Layout.Column = 2;
styleInputControl(efCdur, palette);

sectionLabel4 = uilabel(g, "Text", "EXTRA SETTINGS", "FontSize", baseFont + 1, "FontColor", [0.60 0.65 0.70], "FontWeight", "bold");
sectionLabel4.Layout.Row = 18;
sectionLabel4.Layout.Column = [1 2];

makeHelpLabel(g, 19, "Fluid Density (g/mL)", @onHelpDensity, baseFont, palette);
efDen = uieditfield(g, "numeric", "Value", 0.997, "Limits", [0.8 1.2], "FontSize", baseFont);
efDen.Tooltip = "Used for mass-to-volume conversion in calibration mode.";
efDen.Layout.Row = 19;
efDen.Layout.Column = 2;
styleInputControl(efDen, palette);

makeHelpLabel(g, 20, "Measured Mass (g, optional; 0 = skip)", @onHelpMeasuredMass, baseFont, palette);
efMass = uieditfield(g, "numeric", "Value", 0, "Limits", [0 Inf], "FontSize", baseFont);
efMass.Tooltip = "Optional collected mass for calibration correction.";
efMass.Layout.Row = 20;
efMass.Layout.Column = 2;
styleInputControl(efMass, palette);

makeStandardLabel(g, 21, "Logs Folder", baseFont, palette);
logHint = uilabel(g, "Text", fullfile(pwd, "logs"), "FontSize", baseFont - 1, "FontColor", palette.TextMuted);
logHint.WordWrap = "on";
logHint.Layout.Row = 21;
logHint.Layout.Column = 2;

makeStandardLabel(g, 22, "Mode Note", baseFont, palette);
modeHint = uilabel(g, "Text", "Pulse mode: waveform control enabled.", "FontSize", baseFont - 1, "FontColor", palette.TextMain);
modeHint.WordWrap = "on";
modeHint.Layout.Row = 22;
modeHint.Layout.Column = 2;

makeStandardLabel(g, 23, "Theoretical Stroke", baseFont, palette);
lblTheoretical = uilabel(g, "Text", "0.0000 nL/beat", "FontSize", baseFont, "FontColor", palette.TextMain, "FontWeight", "bold");
lblTheoretical.Layout.Row = 23;
lblTheoretical.Layout.Column = 2;

makeStandardLabel(g, 24, "Effective Stroke", baseFont, palette);
lblEffective = uilabel(g, "Text", "0.0000 nL/beat", "FontSize", baseFont, "FontColor", palette.Good, "FontWeight", "bold");
lblEffective.Layout.Row = 24;
lblEffective.Layout.Column = 2;

makeStandardLabel(g, 25, "Command Preview", baseFont, palette);
previewHint = uilabel(g, "Text", "Exact serial strings update in real time.", "FontSize", baseFont - 1, "FontColor", palette.TextMuted);
previewHint.Layout.Row = 25;
previewHint.Layout.Column = 2;

cmdPreview = uitextarea(g, "Editable", "off", "FontName", "Menlo", "FontSize", baseFont - 1, "BackgroundColor", palette.Panel, "FontColor", palette.TextMain);
cmdPreview.Layout.Row = 26;
cmdPreview.Layout.Column = [1 2];

setappdata(f, "stopRequested", false);
setappdata(f, "helpDlg", []);
setappdata(f, "helpHtml", []);

btnRun = uibutton(g, "Text", "Run", "ButtonPushedFcn", @onRun, "FontWeight", "bold", "FontSize", baseFont, "BackgroundColor", palette.RunBg, "FontColor", palette.RunFg);
btnRun.Layout.Row = 27;
btnRun.Layout.Column = 1;

btnStop = uibutton(g, "Text", "STOP", "ButtonPushedFcn", @onStop, "FontWeight", "bold", "FontSize", baseFont, "BackgroundColor", palette.StopBg, "FontColor", palette.StopFg);
btnStop.Layout.Row = 27;
btnStop.Layout.Column = 2;
btnStop.Enable = "off";

status = uilabel(g, "Text", "Ready", "FontWeight", "bold", "FontSize", baseFont, "FontColor", palette.TextMain);
status.Layout.Row = 28;
status.Layout.Column = 1;

timerLabel = uilabel(g, "Text", "Elapsed: 00:00.0", "HorizontalAlignment", "right", "FontWeight", "bold", "FontSize", baseFont, "FontColor", palette.TextMain);
timerLabel.Layout.Row = 28;
timerLabel.Layout.Column = 2;

runStartTic = [];
uiTimer = timer("ExecutionMode", "fixedRate", "Period", 0.2, "TimerFcn", @onTimerTick);

valueControls = {ddMode, ddPulseDelivery, ddPreset, ddSyr, efPort, cbPrime, efBpm, efSv, efRun, efDuty, ddShape, efSeg, efCrate, efCdur, efDen, efMass};
for i = 1:numel(valueControls)
    if isprop(valueControls{i}, "ValueChangedFcn")
        valueControls{i}.ValueChangedFcn = @(~,~)onValueChanged();
    end
end
ddPreset.ValueChangedFcn = @onPresetChanged;
ddPulseDelivery.ValueChangedFcn = @onPulseDeliveryModeChanged;
ddSyr.ValueChangedFcn = @onSyringeChanged;

onPresetChanged();
onPulseDeliveryModeChanged();
updateDerivedDisplays();

    function onRun(~, ~)
        setappdata(f, "stopRequested", false);
        btnRun.Enable = "off";
        btnStop.Enable = "on";
        status.Text = "Running...";
        status.FontColor = palette.Running;

        runStartTic = tic;
        timerLabel.Text = "Elapsed: 00:00.0";
        if strcmp(uiTimer.Running, "off")
            start(uiTimer);
        end

        user = struct();
        user.mode = string(ddMode.Value);
        user.interactive = false;
        user.doPrime = cbPrime.Value;
        user.preferredPort = string(strtrim(efPort.Value));
        user.vidCheckMode = "auto";
        user.stopRequestedFcn = @()logical(getappdata(f, "stopRequested"));
        user.processUiFcn = @()drawnow;
        user.syringeProfile = string(ddSyr.Value);
        user.pulseDeliveryMode = string(ddPulseDelivery.Value);

        user.bpm = efBpm.Value;
        user.strokeVolume_nL = efSv.Value;
        user.runSeconds = efRun.Value;
        user.systoleDuty = efDuty.Value;
        user.pulseShape = string(ddShape.Value);
        user.systoleSegments = efSeg.Value;

        user.calibRate_uL_min = efCrate.Value;
        user.calibDuration_s = efCdur.Value;
        user.fluidDensity_g_mL = efDen.Value;
        user.measuredMass_g = efMass.Value;

        drawnow;

        try
            result = runExperimentCore(user);
            if isfield(result, "status") && string(result.status) == "stopped"
                status.Text = "Stopped";
                status.FontColor = palette.Warning;
                uialert(f, sprintf("Run stopped by user. Logs saved at:\n%s", result.runFolder), "Stopped", "Icon", "warning");
            elseif isfield(result, "status") && string(result.status) == "error"
                status.Text = "Error";
                status.FontColor = palette.Error;
                uialert(f, sprintf("Run failed safely: %s\n\nLogs saved at:\n%s", result.message, result.runFolder), "Run Failed", "Icon", "error");
            else
                status.Text = "Completed";
                status.FontColor = palette.Good;
                uialert(f, sprintf("Run complete. Logs saved at:\n%s", result.runFolder), "Success", "Icon", "success");
            end
        catch ME
            status.Text = "Error";
            status.FontColor = palette.Error;
            fprintf(2, "\nGUI Run Error:\n%s\n", getReport(ME, 'extended', 'hyperlinks', 'off'));
            uialert(f, ME.message, "Run Failed", "Icon", "error");
        end

        stopElapsedTimer();
        btnRun.Enable = "on";
        btnStop.Enable = "off";
        updateDerivedDisplays();
    end

    function onStop(~, ~)
        setappdata(f, "stopRequested", true);
        status.Text = "Stopping...";
        status.FontColor = palette.Warning;
    end

    function onPresetChanged(~, ~)
        preset = string(ddPreset.Value);
        if preset == "zebrafish_48hpf"
            efBpm.Value = 140;
            efSv.Value = 0.15;
            efDuty.Value = 0.40;
            ddShape.Value = 'square';
        elseif preset == "zebrafish_72hpf"
            efBpm.Value = 150;
            efSv.Value = 0.20;
            efDuty.Value = 0.30;
            ddShape.Value = 'sinusoidal';
        elseif preset == "zebrafish_96hpf"
            efBpm.Value = 165;
            efSv.Value = 0.25;
            efDuty.Value = 0.30;
            ddShape.Value = 'square';
        end
        updateDerivedDisplays();
    end

    function onPulseDeliveryModeChanged(~, ~)
        pulseMode = string(ddPulseDelivery.Value);
        if pulseMode == "bench"
            efSv.Limits = [0.05 Inf];
        else
            efSv.Limits = [0.05 10.0];
            if efSv.Value > 10.0
                efSv.Value = 10.0;
            end
        end
        updateModeHint();
        updateDerivedDisplays();
    end

    function onSyringeChanged(~, ~)
        updateModeHint();
        updateDerivedDisplays();
    end

    function onValueChanged()
        if ddPreset.Value ~= "custom"
            ddPreset.Value = 'custom';
        end
        updateDerivedDisplays();
    end

    function updateModeHint()
        mainMode = string(ddMode.Value);
        pulseMode = string(ddPulseDelivery.Value);
        syringeProfile = string(ddSyr.Value);

        if mainMode == "smooth"
            if syringeProfile == "terumo_1mL"
                modeHint.Text = "Smooth mode: continuous flow for priming, calibration, and simple validation. 1 mL uses step rounding.";
            else
                modeHint.Text = "Smooth mode: continuous flow for priming, calibration, and simple validation.";
            end
        elseif pulseMode == "bench"
            if syringeProfile == "terumo_1mL"
                modeHint.Text = "Bench mode: high-flow diagnostics enabled; 1 mL stroke will be step-rounded and reported below.";
            else
                modeHint.Text = "Bench mode: high-flow diagnostics enabled with diastolic floor behavior.";
            end
        else
            if syringeProfile == "terumo_1mL"
                modeHint.Text = "Physiology mode: 1 mL profile applies step rounding and compensation-aware command preview.";
            else
                modeHint.Text = "Physiology mode: stop-based diastole for embryonic waveform fidelity.";
            end
        end
    end

    function updateDerivedDisplays()
        requestedSv = efSv.Value;
        effectiveSv = requestedSv;

        if string(ddSyr.Value) == "terumo_1mL"
            stepVolume_nL = stepVolumeFromDiameter(4.70, 31);
            nSteps = max(1, round(requestedSv / stepVolume_nL));
            effectiveSv = nSteps * stepVolume_nL;
        end

        lblTheoretical.Text = sprintf("%.4f nL/beat", requestedSv);
        lblEffective.Text = sprintf("%.4f nL/beat", effectiveSv);

        pctErr = 0;
        if requestedSv > 0
            pctErr = abs(effectiveSv - requestedSv) / requestedSv * 100;
        end

        if pctErr > 5
            lblEffective.FontColor = palette.Amber;
        else
            lblEffective.FontColor = palette.Good;
        end

        cmdPreview.Value = buildCommandPreview(effectiveSv);
    end

    function lines = buildCommandPreview(effectiveSv)
        if string(ddMode.Value) == "smooth"
            lines = [ ...
                sprintf("irate %.6f u/m", efCrate.Value)
                "run"
                sprintf("... flow for %.3f s ...", efCdur.Value)
                "stop"
                ];
            return;
        end

        bpm = efBpm.Value;
        duty = efDuty.Value;
        pulseMode = string(ddPulseDelivery.Value);

        beatPeriod_s = 60 / max(bpm, 1e-9);
        systoleDuration_s = beatPeriod_s * duty;
        diastoleDuration_s = beatPeriod_s - systoleDuration_s;

        if pulseMode == "bench"
            diastoleRate_nL_min = 10.0;
        else
            diastoleRate_nL_min = 0.0;
        end

        diastoleVolPerBeat_nL = diastoleRate_nL_min * (diastoleDuration_s / 60);
        systoleVolume_nL = max(effectiveSv - diastoleVolPerBeat_nL, 0);
        systoleRate_nL_min = (systoleVolume_nL / max(systoleDuration_s, eps)) * 60;

        rateCompGain = 1.0;
        if string(ddSyr.Value) == "terumo_1mL" && pulseMode == "physiology"
            rateCompGain = 1 / 0.667;
        end
        cmdRate = systoleRate_nL_min * rateCompGain;

        if pulseMode == "bench"
            lines = [ ...
                sprintf("irate %.6f nl/m", diastoleRate_nL_min)
                "run"
                sprintf("irate %.6f nl/m", cmdRate)
                sprintf("irate %.6f nl/m", diastoleRate_nL_min)
                "... repeat each beat ..."
                "stop"
                ];
        else
            lines = [ ...
                sprintf("irate %.6f nl/m", cmdRate)
                "run"
                "stop"
                "... repeat each beat ..."
                "stop"
                ];
        end

        if string(ddShape.Value) == "sinusoidal"
            lines = [lines; sprintf("%% sinusoidal shape with %d segments/beat", round(efSeg.Value))];
        end
        lines = string(lines(:));
    end

    function onTimerTick(~, ~)
        if isempty(runStartTic)
            return;
        end
        elapsed = toc(runStartTic);
        mins = floor(elapsed / 60);
        secs = elapsed - mins * 60;
        timerLabel.Text = sprintf("Elapsed: %02d:%04.1f", mins, secs);
    end

    function stopElapsedTimer()
        if strcmp(uiTimer.Running, "on")
            stop(uiTimer);
        end
        runStartTic = [];
    end

    function onCloseFigure(~, ~)
        stopElapsedTimer();
        helpDlg = getappdata(f, "helpDlg");
        if ~isempty(helpDlg) && isvalid(helpDlg)
            try
                delete(helpDlg);
            catch
            end
        end
        try
            delete(uiTimer);
        catch
        end
        delete(f);
    end

    function onHelpBpm(~, ~)
        showHelpDialog("BPM Help", [
            "Definition: BPM is heart-cycle frequency."
            "Engineering:"
            "- Sets beat period and command update cadence."
            "- Mean flow is approximately BPM x effective stroke volume."
            "Biology:"
            "- Typical embryo targets are 140-150 BPM (48 hpf)."
            "- Typical embryo targets are 150-170 BPM (72-96 hpf)."
            "- Temperature and anesthesia can shift observed BPM."
        ]);
    end

    function onHelpSv(~, ~)
        showHelpDialog("Stroke Volume Help", [
            "Definition: Stroke volume is target delivery per beat (nL/beat)."
            "Engineering:"
            "- 1 mL syringe values round to motor step resolution (~0.5378 nL/step)."
            "- Confirm actual command in Effective Stroke readout."
            "Biology:"
            "- This is your primary mechanical loading / dosage control."
            "- Small changes can alter valve and chamber stress."
        ]);
    end

    function onHelpDuty(~, ~)
        showHelpDialog("Systole Duty Help", [
            "Definition: Systole duty is fraction of each beat with pump ON."
            "Engineering:"
            "- Duty 0.3 means 30% systole and 70% diastole."
            "- Lower duty needs higher peak systolic rate for same SV."
            "Biology:"
            "- Embryonic zebrafish typically spend less time in systole."
            "- 0.3 is a common physiologic approximation."
        ]);
    end

    function onHelpShape(~, ~)
        showHelpDialog("Pulse Shape Help", [
            "Definition: Pulse shape controls systolic rate profile."
            "Square:"
            "- Instant switching; simplest for timing validation."
            "Sinusoidal:"
            "- Smooth acceleration/deceleration; more biologically natural."
            "- Requires more serial updates; high BPM can increase latency."
        ]);
    end

    function onHelpMode(~, ~)
        showHelpDialog("Mode Help", [
            "Pulse mode:"
            "- Engineering: cycles between systole and diastole commands."
            "- Biology: needed for physiologic hemodynamics and WSS studies."
            "Smooth mode (steady-flow equivalent):"
            "- Engineering: constant non-pulsatile flow for priming and calibration."
            "- Biology: useful for gentle entry, concentration checks, and first-pass validation."
        ]);
    end

    function onHelpPulseDelivery(~, ~)
        showHelpDialog("Pulse Delivery Help", [
            "Physiology mode:"
            "- Engineering: true stop at diastole (0 nL/min command)."
            "- Best for low-flow zebrafish presets."
            "Bench mode:"
            "- Engineering: uses 10 nL/min diastolic floor to reduce rate-zero alarms."
            "- Intended for diagnostics and stress-testing, not delicate physiology."
        ]);
    end

    function onHelpPreset(~, ~)
        showHelpDialog("Preset Help", [
            "Presets load research-guided baseline BPM, SV, and duty."
            "48 hpf: 140 BPM, 0.15 nL/beat, duty 0.40"
            "72 hpf: 150 BPM, 0.20 nL/beat, duty 0.30"
            "96 hpf: 165 BPM, 0.25 nL/beat, duty 0.30"
            "Tip: On 1 mL syringe, Effective Stroke may differ due to step rounding."
        ]);
    end

    function onHelpSyringe(~, ~)
        showHelpDialog("Syringe Profile Help", [
            "Syringe profile sets mechanical delivery resolution."
            "Engineering:"
            "- 100 uL Hamilton: ~0.0519 nL/step"
            "- 1 mL Terumo: ~0.5378 nL/step (about 10x coarser)"
            "Biology:"
            "- Use 100 uL for 48-72 hpf precision pulsation."
            "- Use 1 mL mainly for high-volume bench calibration/testing."
        ]);
    end

    function onHelpPrime(~, ~)
        showHelpDialog("Prime Help", [
            "Prime clears air and wets tubing before data collection."
            "Engineering:"
            "- Reduces compressibility artifacts and delayed flow onset."
            "Biology:"
            "- Lowers bubble risk before vessel entry."
        ]);
    end

    function onHelpRuntime(~, ~)
        showHelpDialog("Run Time Help", [
            "Runtime is total experiment duration in seconds."
            "Engineering:"
            "- Longer runs improve gravimetric signal-to-noise."
            "- Total beats = BPM x runtime / 60."
            "Biology:"
            "- Keep duration no longer than needed for endpoint and viability."
        ]);
    end

    function onHelpSegments(~, ~)
        showHelpDialog("Systole Segments Help", [
            "Applies only to sinusoidal pulse shape."
            "Engineering:"
            "- More segments improve waveform smoothness."
            "- More segments also increase serial traffic and possible latency."
            "Practical:"
            "- Use moderate values (for example 8-16) for stability."
        ]);
    end

    function onHelpCalRate(~, ~)
        showHelpDialog("Smooth Flow Rate Help", [
            "Smooth flow rate is steady flow (uL/min) used in smooth mode."
            "Engineering:"
            "- Compare expected volume to mass-derived measured volume."
            "- Prefer stable mid-range rates to reduce quantization artifacts."
        ]);
    end

    function onHelpCalDuration(~, ~)
        showHelpDialog("Smooth Duration Help", [
            "Smooth duration sets how long steady dispense runs."
            "Engineering:"
            "- Longer windows reduce relative balance noise and evaporation bias."
            "- Typical range is 60-180 s depending on target volume."
        ]);
    end

    function onHelpDensity(~, ~)
        showHelpDialog("Fluid Density Help", [
            "Fluid density converts mass to delivered volume."
            "Formula: volume (uL) = mass (g) / density (g/mL) x 1000"
            "For water near room temperature, 0.997 g/mL is a common value."
        ]);
    end

    function onHelpMeasuredMass(~, ~)
        showHelpDialog("Measured Mass Help", [
            "Measured mass is optional input for calibration correction."
            "Engineering:"
            "- Enter collected mass to estimate correction factor."
            "- Leave 0 to skip correction and run open-loop validation."
        ]);
    end

    function showHelpDialog(titleText, lines)
        helpDlg = getappdata(f, "helpDlg");
        helpHtml = getappdata(f, "helpHtml");

        if isempty(helpDlg) || ~isvalid(helpDlg)
            helpDlg = uifigure( ...
                "Name", titleText, ...
                "Color", palette.FigureBg, ...
                "Position", [f.Position(1)+50, f.Position(2)+50, 520, 420], ...
                "WindowStyle", "normal", ...
                "CloseRequestFcn", @onCloseHelpDialog);

            dlgGrid = uigridlayout(helpDlg, [2 1]);
            dlgGrid.RowHeight = {'1x', 36};
            dlgGrid.ColumnWidth = {'1x'};
            dlgGrid.Padding = [10 10 10 10];
            dlgGrid.RowSpacing = 8;

            helpHtml = uihtml(dlgGrid);
            helpHtml.Layout.Row = 1;

            btnClose = uibutton(dlgGrid, ...
                "Text", "Close", ...
                "ButtonPushedFcn", @(~,~)onCloseHelpDialog(), ...
                "BackgroundColor", palette.HelpBg, ...
                "FontColor", palette.HelpFg, ...
                "FontWeight", "bold");
            btnClose.Layout.Row = 2;

            setappdata(f, "helpDlg", helpDlg);
            setappdata(f, "helpHtml", helpHtml);
        end

        helpDlg.Name = titleText;
        helpHtml.HTMLSource = formatHelpHtml(lines);
        helpDlg.Visible = "on";

        % Bring help to front without blocking interaction with the main app.
        try
            helpDlg.Position = helpDlg.Position;
        catch
        end
    end

    function onCloseHelpDialog(~, ~)
        helpDlg = getappdata(f, "helpDlg");
        if ~isempty(helpDlg) && isvalid(helpDlg)
            delete(helpDlg);
        end
        setappdata(f, "helpDlg", []);
        setappdata(f, "helpHtml", []);
    end

    function html = formatHelpHtml(lines)
        lines = string(lines(:));
        textColor = rgbToHex(palette.TextMain);
        panelColor = rgbToHex(palette.Panel);
        headingColor = rgbToHex([0.97 0.97 0.99]);

        body = "";
        for k = 1:numel(lines)
            s = strtrim(lines(k));
            if strlength(s) == 0
                body = body + "<div class='sp'></div>";
                continue;
            end

            if endsWith(s, ":")
                body = body + "<div class='hdr'>" + escapeHtml(s) + "</div>";
            elseif startsWith(s, "-")
                bulletText = strtrim(extractAfter(s, 1));
                body = body + "<div class='bullet'>&bull; " + escapeHtml(bulletText) + "</div>";
            else
                body = body + "<div class='txt'>" + escapeHtml(s) + "</div>";
            end
        end

        html = "<html><head><meta charset='utf-8'><style>" + ...
            "html,body{height:100%;margin:0;padding:0;background:" + panelColor + ";}" + ...
            "body{overflow-y:scroll;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:" + textColor + ";}" + ...
            ".wrap{padding:10px 12px 10px 12px;font-size:13px;line-height:1.35;}" + ...
            ".hdr{font-weight:700;color:" + headingColor + ";margin-top:8px;margin-bottom:2px;}" + ...
            ".txt{margin:2px 0 2px 0;}" + ...
            ".bullet{margin:2px 0 2px 14px;}" + ...
            ".sp{height:4px;}" + ...
            "</style></head><body><div class='wrap'>" + body + "</div></body></html>";
    end

    function h = escapeHtml(s)
        h = string(s);
        h = replace(h, "&", "&amp;");
        h = replace(h, "<", "&lt;");
        h = replace(h, ">", "&gt;");
        h = replace(h, '"', "&quot;");
        h = replace(h, "'", "&#39;");
    end

    function hex = rgbToHex(rgb)
        rgb = max(0, min(1, rgb));
        vals = round(rgb * 255);
        hex = sprintf('#%02X%02X%02X', vals(1), vals(2), vals(3));
    end
end

function makeStandardLabel(parent, row, txt, fontSize, palette)
lbl = uilabel(parent, "Text", txt, "FontSize", fontSize, "FontColor", palette.TextMain);
lbl.Layout.Row = row;
lbl.Layout.Column = 1;
end

function makeHelpLabel(parent, row, txt, helpFcn, fontSize, palette)
panel = uipanel(parent, "BorderType", "none", "BackgroundColor", palette.FigureBg);
panel.Layout.Row = row;
panel.Layout.Column = 1;

grid = uigridlayout(panel, [1 2]);
grid.ColumnWidth = {'1x', 28};
grid.RowHeight = {'1x'};
grid.Padding = [0 0 0 0];
grid.ColumnSpacing = 2;
grid.BackgroundColor = palette.FigureBg;

uilabel(grid, "Text", txt, "FontSize", fontSize, "FontColor", palette.TextMain);
btn = uibutton(grid, "Text", "?", "ButtonPushedFcn", helpFcn, "FontSize", fontSize - 2, "FontWeight", "bold", ...
    "BackgroundColor", palette.HelpBg, "FontColor", palette.HelpFg);
btn.Tooltip = "Open researcher support note.";
end

function stepVolume_nL = stepVolumeFromDiameter(diameter_mm, stepSize_nm)
area_mm2 = pi * (diameter_mm / 2)^2;
stepLength_mm = stepSize_nm * 1e-6;
stepVolume_uL = area_mm2 * stepLength_mm;
stepVolume_nL = stepVolume_uL * 1000;
end

function p = makePalette()
p = struct();
p.FigureBg = [0.17 0.18 0.20];
p.Panel = [0.23 0.24 0.27];
p.InputBg = [0.28 0.29 0.32];
p.TextMain = [0.92 0.93 0.95];
p.TextMuted = [0.76 0.79 0.83];
p.RunBg = [0.15 0.46 0.74];
p.RunFg = [1 1 1];
p.StopBg = [0.77 0.20 0.18];
p.StopFg = [1 1 1];
p.Good = [0.12 0.53 0.30];
p.Warning = [0.68 0.44 0.10];
p.Error = [0.67 0.19 0.19];
p.Running = [0.12 0.53 0.30];
p.Amber = [0.82 0.52 0.07];
p.HelpBg = [0.34 0.35 0.39];
p.HelpFg = [0.93 0.94 0.96];
end

function styleInputControl(ctrl, palette)
try
    ctrl.BackgroundColor = palette.InputBg;
catch
end
try
    ctrl.FontColor = palette.TextMain;
catch
end
end