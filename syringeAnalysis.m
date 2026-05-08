%% Syringe Comparison Analysis (For Capstone Report)
clc; clear;

diameters = [14.5, 4.7, 1.46]; % [10 mL, 1 mL, 100 uL] diameters in mm
volumes = [10000, 1000, 100];   % in uL
step_size_nm = 31;              % Legato 180 linear step

fprintf('%-10s | %-15s | %-15s\n', 'Syringe', 'Resolution (pL)', 'Steps at 1uL/min');
fprintf('------------------------------------------------------------\n');

for i = 1:length(diameters)
    area = pi * (diameters(i)/2)^2; % mm^2
    vol_step_pl = (area * (step_size_nm * 1e-6)) * 1e6; % mm^3 to pL
    
    % Frequency needed for 1 uL/min
    freq = (1000000 / 60) / vol_step_pl; 
    
    fprintf('%-10d | %-15.2f | %-15.2f Hz\n', volumes(i), vol_step_pl, freq);
end