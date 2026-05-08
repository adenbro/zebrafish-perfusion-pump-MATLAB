function pumpObj = connectPump()
    % Find all available serial ports on the Mac
    ports = serialportlist("all");
    disp("Available Ports:");
    disp(ports);
    
    % If you have multiple, you might need to change the index below
    if isempty(ports)
        error("No pump detected. Check USB-C connection and drivers.");
    end
    
    % Select the last port (usually the one just plugged in)
    targetPort = ports(end); 
    
    % Legato 180 Default Settings
    baudRate = 115200;
    
    try
        pumpObj = serialport(targetPort, baudRate);
        configureTerminator(pumpObj, "CR");
        disp(['Successfully connected to: ', char(targetPort)]);
    catch
        error("Could not connect. Is the port already open in another app?");
    end
end