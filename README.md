# zebrafish-perfusion-pump

MATLAB scripts to control and calibrate a syringe pump for zebrafish perfusion.

Contents:
- runExperiment.m, runExperimentCore.m, runExperimentGUI.m — main control & GUI
- calibrateSystem.m, calculateFlowRate.m, syringeAnalysis.m — calibration helpers
- resources/ — device/project files

Usage
1. Open MATLAB and add this folder to the path.
2. Run `runExperiment.m` to start the GUI and follow prompts.

Calibration constants are stored in code; prefer saving refined values in `calibration/`.
