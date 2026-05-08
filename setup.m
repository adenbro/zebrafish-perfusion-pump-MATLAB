% setup.m - quick project setup for new lab members
% Run this once after cloning to add the project and subfolders to the MATLAB path
function setup()
  p = fileparts(mfilename('fullpath'));
  addpath(genpath(p));
  fprintf('Added project path: %s\n', p);
  fprintf('You can now run runExperiment.m to start the GUI.\n');
  % To permanently save the path uncomment the next line (may require permissions):
  % savepath;
end
