function [pumpObj, connectionInfo] = connectPump(preferredBaud, preferredPort)
    % Connect to the Legato serial device using validated default settings.
    if nargin < 1
        preferredBaud = 9600;
    end
    if nargin < 2
        preferredPort = "";
    end

    ports = serialportlist("all");
    disp("Available Ports:");
    disp(ports);

    if isempty(ports)
        error("No serial device detected. Check USB connection and drivers.");
    end

    portsCell = cellstr(ports);
    preferredPortChar = char(preferredPort);

    if ~isempty(strtrim(preferredPortChar))
        idx = find(strcmpi(portsCell, preferredPortChar), 1);
        if isempty(idx)
            error("Preferred port '%s' was not found in serialportlist output.", preferredPortChar);
        end
        targetPort = portsCell{idx};
    else
        portsLower = lower(portsCell);

        % macOS Pico profile priority for this development machine.
        picoMatch = ~cellfun(@isempty, strfind(portsLower, 'usbmodem')) & ~cellfun(@isempty, strfind(portsLower, 'd105402'));
        usbModemMatch = ~cellfun(@isempty, strfind(portsLower, 'usbmodem'));
        usbLike = ~cellfun(@isempty, strfind(portsLower, 'usb')) | ~cellfun(@isempty, strfind(portsLower, 'acm')) | ~cellfun(@isempty, strfind(portsLower, 'modem'));

        if any(picoMatch)
            targetPort = portsCell{find(picoMatch, 1, 'last')};
        elseif any(usbModemMatch)
            targetPort = portsCell{find(usbModemMatch, 1, 'last')};
        elseif any(usbLike)
            targetPort = portsCell{find(usbLike, 1, 'last')};
        else
            targetPort = portsCell{end};
        end
    end

    try
        pumpObj = serialport(targetPort, preferredBaud);
        configureTerminator(pumpObj, 'CR');
        flush(pumpObj);
    catch ME
        error("Could not connect at %d baud on %s. %s", preferredBaud, char(targetPort), ME.message);
    end

    connectionInfo = struct( ...
        "port", char(targetPort), ...
        "baudRate", preferredBaud, ...
        "terminator", "CR");

    disp("Connected to pump serial port.");
    disp(connectionInfo);
end