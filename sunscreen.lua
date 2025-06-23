local language = "nl"  -- Change to "en" for English

local translations = {
    ["nl"] = {
        closing_due_to = "Zonnescherm sluit vanwege",
        expected_rain = "verwachte regen",
        high_wind = "hoge windsnelheid",
        notification_title = "Zonnescherm sluiting",
        already_closed = "Weerwaarschuwing aanwezig, maar alle zonneschermen zijn al gesloten — geen actie ondernomen.",
        rain_soon = "Regen verwacht binnen 5 tot 10 minuten tot",
        no_rain = "Geen regen verwacht binnen 5 tot 10 minuten",
        strong_wind = "Het waait wel heel erg hard buiten",
        breeze = "Lekker briesje buiten",
        dimmer_to_zero = "Zonnescherm (dimmer) gaat naar 0%",
        dimmer_zero_already = "Zonnescherm (dimmer) staat al op 0%",
        switch_turning_off = "Zonnescherm (schakelaar) wordt uitgeschakeld",
        switch_already_off = "Zonnescherm (schakelaar) is al uit",
        sunscreen_not_found = "Fout: zonneschermapparaat met IDX niet gevonden",
    },
    ["en"] = {
        closing_due_to = "Sunscreen closing due to",
        expected_rain = "expected rain",
        high_wind = "high wind speed",
        notification_title = "Sunscreen Closing",
        already_closed = "Weather warning present, but all sunscreens already closed — no action taken.",
        rain_soon = "Rain expected in the next 5 to 10 minutes until",
        no_rain = "No rain expected in the next 5 to 10 minutes",
        strong_wind = "It's very windy outside",
        breeze = "Nice breeze outside",
        dimmer_to_zero = "Sunscreen (dimmer) going to 0%",
        dimmer_zero_already = "Sunscreen (dimmer) already at 0%",
        switch_turning_off = "Sunscreen (switch) going off",
        switch_already_off = "Sunscreen (switch) already off",
        sunscreen_not_found = "Error: Sunscreen device with IDX not found" ,
    },
}

-- Set the IDX of the virtual text device
local RainText_IDX = 51
local WindText_IDX = 49

-- Set the list of IDXs for the sunscreen devices (as percentages or switches)
local Sunscreen_IDXS = { 52, 36 } -- Add more IDXs as needed for example { 52, 53, 54 }

-- Set the IDX of the wind device
local Wind_IDX = 15

-- Set the maximum wind speed threshold (in m/s)
local Max_Wind_Speed = 6.5

-- Set the latitude and longitude and round it to 2 decimal
local function round(num, numDecimalPlaces)
    local mult = 10^(numDecimalPlaces or 0)
    return math.floor(num * mult + 0.5) / mult
end

return {
    active = true, -- optional
    on = {
        timer = { 'every 5 minutes' }
    },
    logging = {
        level = domoticz.LOG_DEBUG,
        marker = "Rain and Sunscreen"
    },
    execute = function(domoticz, item)
        local lat = round(domoticz.settings.location.latitude, 2)
        local lon = round(domoticz.settings.location.longitude, 2)

        -- Set the API URL
        local apiUrl = "https://gadgets.buienradar.nl/data/raintext?lat=" .. lat .. "&lon=" .. lon

        -- Initialize variables to store the rain prediction data
        local rainPrediction = {}
        local rainExpected = false
        local alertTime = ""
        local checkEndTime = ""

        -- Function to fetch the data from the API
        local function fetchData()
            -- Fetch the data from the API using curl
            local handle = io.popen("curl -s '" .. apiUrl .. "'")
            local data = handle:read("*a")
            handle:close()

            -- Check if data was fetched correctly
            if not data or data == "" then
                domoticz.log("Error: Failed to fetch data from API", domoticz.LOG_ERROR)
                return
            end

            -- Split the data into individual lines
            local lines = {}
            for line in data:gmatch("([^\n]*)\n?") do
                table.insert(lines, line)
            end

            -- Process each line of data
            rainPrediction = {}
            for _, line in ipairs(lines) do
                local rainIntensity, time = line:match("^(%d+)%|(.+)$")
                table.insert(rainPrediction, { time = time, intensity = rainIntensity })
            end

            -- Filter the data to get the predictions for the next 5 to 10 minutes
            local alertPredictions = {}
            for _, prediction in ipairs(rainPrediction) do
                if prediction.time then
                    local hour, minute = prediction.time:match("(%d+):(%d+)")
                    if hour and minute then
                        local currentHour = tonumber(os.date("%H"))
                        local currentMinute = tonumber(os.date("%M"))
                        local predictionTime = tonumber(hour) * 60 + tonumber(minute)
                        local currentTime = currentHour * 60 + currentMinute
                        if (predictionTime > currentTime + 5) and (predictionTime <= currentTime + 10) then
                            table.insert(alertPredictions, prediction)
                        end
                    end
                end
            end

            -- Find the alert time if rain is expected within 5 to 10 minutes
            rainExpected = false
            if #alertPredictions > 0 then
                for _, prediction in ipairs(alertPredictions) do
                    if tonumber(prediction.intensity) > 0 then
                        local alertHour, alertMinute = prediction.time:match("(%d+):(%d+)")
                        alertTime = string.format("%02d:%02d", tonumber(alertHour), tonumber(alertMinute))
                        rainExpected = true
                        break
                    end
                end
            else
                alertTime = "unknown"
            end

            -- Set the check end time
            checkEndTime = os.date("%H:%M")

            -- Prepare the message for the virtual text device
            local updateMessage = ""
            if rainExpected then
                updateMessage = translations[language].rain_soon .. " " .. alertTime
            else
                updateMessage = translations[language].no_rain
            end
            -- Update the virtual text device only if the message has changed
            local currentMessage = domoticz.devices(RainText_IDX).text
            if currentMessage ~= updateMessage then
                domoticz.devices(RainText_IDX).updateText(updateMessage)
            end
        end

        -- Fetch the data immediately
        fetchData()

        -- Initialize wind speed variable
        local windSpeed = 0

        -- Get the wind device
        local windDevice = domoticz.devices(Wind_IDX)
        if windDevice then
            domoticz.log("Wind device found: " .. windDevice.name, domoticz.LOG_INFO)
            local windData = windDevice.state
            if windData then
                domoticz.log("Wind data: " .. windData, domoticz.LOG_INFO)
                local values = {}
                for value in string.gmatch(windData, "([^;]+)") do
                    table.insert(values, value)
                end
                domoticz.log("Values table:", domoticz.LOG_INFO)
                for i, value in ipairs(values) do
                    domoticz.log("  [" .. i .. "]: " .. value, domoticz.LOG_INFO)
                end
                -- Now you can access the individual values
                local windBearing = tonumber(values[1])
                local windDirection = values[2]
                windSpeed = tonumber(values[3]) / 10
                local windGustSpeed = tonumber(values[4]) / 10
                domoticz.log("Wind bearing: " .. tostring(windBearing), domoticz.LOG_INFO)
                domoticz.log("Wind direction: " .. windDirection, domoticz.LOG_INFO)
                domoticz.log("Wind speed: " .. tostring(windSpeed), domoticz.LOG_INFO)
                domoticz.log("Wind gust speed: " .. tostring(windGustSpeed), domoticz.LOG_INFO)
                
                                -- Prepare the message for the virtual text device
                local updateMessage = ""
                    if windSpeed > Max_Wind_Speed then
                        updateMessage = translations[language].strong_wind .. " " .. alertTime
                    else
                        updateMessage = translations[language].breeze
                    end
                -- Update the virtual text device only if the message has changed
                local currentMessage = domoticz.devices(WindText_IDX).text
                    if currentMessage ~= updateMessage then
                        domoticz.devices(WindText_IDX).updateText(updateMessage)
                    end
                
            else
                domoticz.log("Error: No data available for wind device with IDX " .. Wind_IDX, domoticz.LOG_ERROR)
            end
        else
            domoticz.log("Error: Wind device with IDX " .. Wind_IDX .. " not found", domoticz.LOG_ERROR)
        end
        -- Check if rain is expected or wind speed is above the maximum threshold
        if rainExpected or windSpeed > Max_Wind_Speed then
            local closedStates = { Off = true, Closed = true, ["0"] = true }
            local anyOpen = false
        
            -- Check if any sunscreen is open
            for _, idx in ipairs(Sunscreen_IDXS) do
                local sunscreen = domoticz.devices(idx)
                if sunscreen then
                    domoticz.log("Checking sunscreen: " .. sunscreen.name ..
                        ", type: " .. tostring(sunscreen.deviceType) ..
                        ", state: " .. tostring(sunscreen.state) ..
                        ", percentage: " .. tostring(sunscreen.percentage), domoticz.LOG_DEBUG)
        
                    if sunscreen.deviceType == domoticz.DEVICE_TYPE_DIMMER then
                        if sunscreen.percentage and sunscreen.percentage > 0 then
                            anyOpen = true
                            break
                        end
                    else
                        if not closedStates[sunscreen.state] then
                            anyOpen = true
                            break
                        end
                    end
                else
                    domoticz.log(translations[language].sunscreen_not_found .. " (" .. idx .. ")", domoticz.LOG_ERROR)
                end
            end
        
            if anyOpen then
                -- Construct the reason
                local reason = (rainExpected and translations[language].expected_rain or "") ..
                               (rainExpected and windSpeed > Max_Wind_Speed and " en " or "") ..
                               (windSpeed > Max_Wind_Speed and translations[language].high_wind or "")
                
                local message = translations[language].closing_due_to .. " " .. reason .. "."
        
                domoticz.log(message, domoticz.LOG_WARNING)
                domoticz.notify(translations[language].notification_title, message, domoticz.PRIORITY_NORMAL)
        
                -- Close the screens
                for _, idx in ipairs(Sunscreen_IDXS) do
                    local sunscreen = domoticz.devices(idx)
                    if sunscreen then
                        if sunscreen.deviceType == domoticz.DEVICE_TYPE_DIMMER then
                            if sunscreen.percentage > 0 then
                                sunscreen.dimTo(0)
                                domoticz.log(translations[language].dimmer_to_zero, domoticz.LOG_INFO)
                            else
                                domoticz.log(translations[language].dimmer_zero_already, domoticz.LOG_INFO)
                            end
                        else
                            if not closedStates[sunscreen.state] then
                                sunscreen.switchOff()
                                domoticz.log(translations[language].switch_turning_off, domoticz.LOG_INFO)
                            else
                                domoticz.log(translations[language].switch_already_off, domoticz.LOG_INFO)
                            end
                        end
                    else
                        domoticz.log(translations[language].sunscreen_not_found .. " (" .. idx .. ")", domoticz.LOG_ERROR)
                    end
                end
            else
                domoticz.log(translations[language].already_closed, domoticz.LOG_INFO)
            end
        end
    end
}
