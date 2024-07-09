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
            rainExpected = false
            for _, line in ipairs(lines) do
                local rainIntensity, time = line:match("^(%d+)%|(.+)$")
                if rainIntensity and rainIntensity ~= "000" then
                    rainExpected = true
                end
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
                        if (predictionTime > currentTime) and (predictionTime <= currentTime + 10) then
                            table.insert(alertPredictions, prediction)
                        end
                    end
                end
            end

            -- Find the alert time if rain is expected within 5 to 10 minutes
            if #alertPredictions > 0 then
                local alertHour, alertMinute = alertPredictions[1].time:match("(%d+):(%d+)")
                alertTime = string.format("%02d:%02d", tonumber(alertHour), tonumber(alertMinute))
            else
                alertTime = "unknown"
            end

            -- Set the check end time
            checkEndTime = os.date("%H:%M")

            -- Prepare the message for the virtual text device
            local updateMessage = ""
            if #alertPredictions > 0 then
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
    end
}
