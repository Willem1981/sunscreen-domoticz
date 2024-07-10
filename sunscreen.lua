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

        -- Set the IDX of the virtual text device
        local RainText_IDX = 51

        -- Set the list of IDXs for the sunscreen devices (as percentages or switches)
        local Sunscreen_IDXS = { 52 } -- Add more IDXs as needed for example { 52, 53, 54 }

        -- Set the latitude and longitude and round it to 2 decimal
        function round(num, numDecimalPlaces)
            local mult = 10^(numDecimalPlaces or 0)
            return math.floor(num * mult + 0.5) / mult
        end

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
                updateMessage = 'Rain expected in the next 5 to 10 minutes until ' .. alertTime .. '. Checked at: ' .. checkEndTime .. '.'
                domoticz.log("Rain expected in the next 5 to 10 minutes until " .. alertTime .. ". Checked at: " .. checkEndTime .. ".", domoticz.LOG_INFO)
                -- Add the update command to the command array for the virtual text device
                domoticz.devices(RainText_IDX).updateText(updateMessage)
                -- Check the type of each sunscreen device and set to 0% or off
                for _, idx in ipairs(Sunscreen_IDXS) do
                    local sunscreen = domoticz.devices(idx)
                    if sunscreen then
                        if sunscreen.deviceType == domoticz.DEVICE_TYPE_DIMMER then
                            if sunscreen.percentage > 0 then
                                sunscreen.dimTo(0)
                                domoticz.log('Sunscreen (dimmer) going to 0%', domoticz.LOG_INFO)
                            else
                                domoticz.log('Sunscreen (dimmer) already at 0%', domoticz.LOG_INFO)
                            end
                        else
                            if sunscreen.state ~= 'Off' then
                                sunscreen.switchOff()
                                domoticz.log('Sunscreen (switch) going off', domoticz.LOG_INFO)
                            else
                                domoticz.log('Sunscreen (switch) already off', domoticz.LOG_INFO)
                            end
                        end
                    else
                        domoticz.log('Error: Sunscreen device with IDX ' .. idx .. ' not found', domoticz.LOG_ERROR)
                    end
                end
            else
                updateMessage = 'No rain expected in the next 5 to 10 minutes. Checked at: ' .. checkEndTime .. '.'
                domoticz.log("No rain expected in the next 5 to 10 minutes. Checked at: " .. checkEndTime .. ".", domoticz.LOG_INFO)
                -- Add the update command to the command array for the virtual text device
                domoticz.devices(RainText_IDX).updateText(updateMessage)
            end
        end

        -- Fetch the data immediately
        fetchData()
        
        -- Set the IDX of the wind device
        local Wind_IDX = 15

        -- Set the maximum wind speed threshold (in m/s)
        local Max_Wind_Speed = 5.4

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
                local windSpeed = tonumber(values[3]) / 10
                local windGustSpeed = tonumber(values[4]) / 10
                domoticz.log("Wind bearing: " .. tostring(windBearing), domoticz.LOG_INFO)
                domoticz.log("Wind direction: " .. windDirection, domoticz.LOG_INFO)
                domoticz.log("Wind speed: " .. tostring(windSpeed), domoticz.LOG_INFO)
                domoticz.log("Wind gust speed: " .. tostring(windGustSpeed), domoticz.LOG_INFO)

                -- Check if wind speed is above the maximum threshold
                if windSpeed > Max_Wind_Speed then
                    domoticz.log("Closing sunscreen due to high wind speed: " .. tostring(windSpeed), domoticz.LOG_WARNING)
                    -- Switch off or dim all sunscreen devices
                    for _, idx in ipairs(Sunscreen_IDXS) do
                        local sunscreen = domoticz.devices(idx)
                        if sunscreen then
                            if sunscreen.deviceType == domoticz.DEVICE_TYPE_DIMMER then
                                if sunscreen.percentage > 0 then
                                    sunscreen.dimTo(0)
                                    domoticz.log('Sunscreen (dimmer) going to 0%', domoticz.LOG_INFO)
                                else
                                    domoticz.log('Sunscreen (dimmer) already at 0%', domoticz.LOG_INFO)
                                end
                            else
                                if sunscreen.state ~= 'Off' then
                                    sunscreen.switchOff()
                                    domoticz.log('Sunscreen (switch) going off', domoticz.LOG_INFO)
                                else
                                    domoticz.log('Sunscreen (switch) already off', domoticz.LOG_INFO)
                                end
                            end
                        else
                            domoticz.log('Error: Sunscreen device with IDX ' .. idx .. ' not found', domoticz.LOG_ERROR)
                        end
                    end
                end
            else
                domoticz.log("Error: No data available for wind device with IDX " .. Wind_IDX, domoticz.LOG_ERROR)
            end
        else
            domoticz.log("Error: Wind device with IDX " .. Wind_IDX .. " not found", domoticz.LOG_ERROR)
        end
    end
}
