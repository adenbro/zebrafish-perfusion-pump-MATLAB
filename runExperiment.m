%% Zebrafish Legato Control (Headless Wrapper)
% Edit only the values in this block for daily use.
clear; clc;

user = struct();
user.mode = "pulse";                    % "pulse" or "smooth"
user.interactive = false;                % false = fully headless
user.doPrime = false;
user.preferredPort = "";                % e.g. "COM4" on Windows, "/dev/tty.usbmodemXXXX" on macOS
user.vidCheckMode = "auto";             % "auto" (recommended), "strict", or "off"
user.commandPrefix = "";                % Empty for direct commands; use "0" if pump requires address prefix.
user.rateCommandVerb = "irate";         % Use "irate" for Legato; change to "rate" if needed.
user.runCommandVerb = "run";
user.stopCommandVerb = "stop";
user.syringeProfile = "terumo_1mL";     % "hamilton_100uL", "terumo_1mL", "terumo_10mL"
user.pulseDeliveryMode = "physiology";  % "physiology" for zebrafish runs; "bench" for high-flow validation.

% Pulsatile mode settings
user.bpm = 150;
user.strokeVolume_nL = 0.50;             % 48 hpf preset (75 nL/min at 150 BPM)
user.runSeconds = 30;
user.systoleDuty = 0.30;
user.pulseShape = "square";            % "square" or "sinusoidal"
user.systoleSegments = 12;

% Smooth mode settings
user.calibRate_uL_min = 1.0;
user.calibDuration_s = 120;
user.fluidDensity_g_mL = 0.997;
user.measuredMass_g = NaN;

runExperimentCore(user);

 