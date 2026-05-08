# zebrafish-perfusion-pump

MATLAB scripts to control and calibrate a syringe pump for zebrafish perfusion.

Contents:
- runExperiment.m, runExperimentCore.m, runExperimentGUI.m — main control & GUI
- calibrateSystem.m, calculateFlowRate.m, syringeAnalysis.m — calibration helpers
- resources/ — device/project files
- setup.m — adds the project to the MATLAB path for new users

Modes:
- `pulse` for pulsatile waveform experiments
- `smooth` for steady/continuous flow

Note: smooth mode is simpler to use, but exact delivered volume still depends on calibration and syringe profile.

Usage
1. Open MATLAB and add this folder to the path.
2. Or run `setup` once, then `runExperiment.m` to start the GUI and follow prompts.

Calibration constants are stored in code; prefer saving refined values in `calibration/`.
