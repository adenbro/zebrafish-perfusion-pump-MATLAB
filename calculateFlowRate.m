function [q_nl_min, step_hz] = calculateFlowRate(tau_target, r_um, syringe_vol_ul)
    % Physics Parameters
    mu = 0.001; % Viscosity of Water/PBS (Pa.s)
    r_m = r_um * 1e-6; % convert microns to meters
    
    % 1. Calculate Q in m^3/s: Q = (tau * pi * r^3) / (4 * mu)
    q_m3s = (tau_target * pi * r_m^3) / (4 * mu);
    
    % 2. Convert to nL/min (The pump's native units)
    q_nl_min = q_m3s * 1e12 * 60;
    
    % 3. Calculate Step Frequency for 100uL Syringe (51.9 pL/step)
    % If using 1mL syringe, change this to 537.8
    if syringe_vol_ul == 100
        vol_per_step_pl = 51.9;
    else
        vol_per_step_pl = 537.8; % 1mL assumption
    end
    
    q_pl_sec = (q_nl_min * 1000) / 60;
    step_hz = q_pl_sec / vol_per_step_pl;
end