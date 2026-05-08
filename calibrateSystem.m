%% Zebrafish Perfusion Calibration & Sweep Tool
clear; clc;

% --- 1. USER INPUTS ---
radius_um = 20;             % measured internal radius of  needle
target_shear_range = 0.1:0.05:1.0; % sweep from 0.1 to 1.0 Pa
syringe_vol_ul = 100;       % resolution based on your 100uL glass syringe

% --- 2. SWEEP ENGINE ---
% initialize arrays to store results
num_points = length(target_shear_range);
flow_rates = zeros(1, num_points);
frequencies = zeros(1, num_points);

for i = 1:num_points
    % calling existing function
    [q, hz] = calculateFlowRate(target_shear_range(i), radius_um, syringe_vol_ul);
    flow_rates(i) = q;
    frequencies(i) = hz;
end

% --- 3. DATA VISUALIZATION ---
Results = table(target_shear_range', flow_rates', frequencies', ...
    'VariableNames', {'Shear_Stress_Pa', 'Flow_nL_min', 'Stepper_Hz'});

fprintf('--- Calibration Table for r = %d um ---\n', radius_um);
disp(Results);

% Plotting the Control Curve
figure('Color', 'w', 'Name', 'System Characterization');
yyaxis left
plot(target_shear_range, flow_rates, '-b', 'LineWidth', 2);
ylabel('Required Flow Rate (nL/min)');
xlabel('Target Wall Shear Stress (Pa)');

yyaxis right
plot(target_shear_range, frequencies, '--r', 'LineWidth', 1.5);
ylabel('Motor Step Frequency (Hz)');

title(['Perfusion Calibration Curve (Needle Radius: ', num2str(radius_um), ' \mum)']);
grid on;
legend('Flow Rate (nL/min)', 'Step Frequency (Hz)', 'Location', 'northwest');

% --- 4. EXPORT FOR REPORT ---
% writetable(Results, 'System_Calibration.csv');
% saveas(gcf, 'Calibration_Curve.png');