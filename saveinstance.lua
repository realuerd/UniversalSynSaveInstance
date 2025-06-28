-- SaveInstance Implementation
-- A clean-room implementation for saving Roblox instances

local function createService(serviceName)
    local success, service = pcall(game.GetService, game, serviceName)
    return success and service or nil
end

local services = {
    Players = createService("Players"),
    HttpService = createService("HttpService"),
    MarketplaceService = createService("MarketplaceService"),
    RunService = createService("RunService"),
    CoreGui = createService("CoreGui"),
    GuiService = createService("GuiService")
}

local function getLocalPlayer()
    return services.Players and (services.Players.LocalPlayer or services.Players:FindFirstChildOfClass("Player"))
end

local function sanitizeFilename(name)
    return name:gsub("[^%w _-]", ""):gsub(" +", " "):sub(1, 240)
end

local function formatFileSize(bytes)
    local units = {"B", "KB", "MB", "GB"}
    local unitIndex = 1
    
    while bytes >= 1024 and unitIndex < #units do
        bytes = bytes / 1024
        unitIndex = unitIndex + 1
    end
    
    return string.format("%.1f %s", bytes, units[unitIndex])
end

local function getDefaultProperties(instance)
    local defaults = {}
    local className = instance.ClassName
    
    -- Create a temporary instance to get default properties
    local temp = Instance.new(className)
    for _, prop in ipairs(instance:GetPropertyChangedSignal(""):GetConnections()) do
        local propName = prop._name or prop.Name
        if propName ~= "" then
            defaults[propName] = temp[propName]
        end
    end
    temp:Destroy()
    
    return defaults
end

local function shouldIgnoreInstance(instance, ignoreList)
    if not instance then return true end
    
    -- Check if instance is in ignore list
    if ignoreList[instance] then return true end
    
    -- Check by class name
    local className = instance.ClassName
    if ignoreList[className] then
        if type(ignoreList[className]) == "table" then
            return ignoreList[className][instance.Name] ~= nil
        end
        return true
    end
    
    return false
end

local function saveProperty(instance, propName, value, defaultValues)
    local propType = typeof(value)
    
    -- Skip if property matches default value
    if defaultValues and defaultValues[propName] == value then
        return nil
    end
    
    -- Basic property serialization
    if propType == "string" then
        return string.format('<string name="%s"><![CDATA[%s]]></string>', propName, value)
    elseif propType == "number" then
        return string.format('<float name="%s">%g</float>', propName, value)
    elseif propType == "boolean" then
        return string.format('<bool name="%s">%s</bool>', propName, tostring(value))
    elseif propType == "Color3" then
        return string.format('<Color3 name="%s"><R>%g</R><G>%g</G><B>%g</B></Color3>', 
            propName, value.r, value.g, value.b)
    elseif propType == "Vector3" then
        return string.format('<Vector3 name="%s"><X>%g</X><Y>%g</Y><Z>%g</Z></Vector3>', 
            propName, value.x, value.y, value.z)
    elseif propType == "EnumItem" then
        return string.format('<token name="%s">%s</token>', propName, tostring(value)))
    end
    
    -- Add more property types as needed
    
    return nil
end

local function saveInstance(instance, options)
    local output = {}
    local refCount = 0
    local references = {}
    
    local function generateReference(obj)
        if not references[obj] then
            refCount = refCount + 1
            references[obj] = refCount
        end
        return references[obj]
    end
    
    local function processInstance(obj, depth)
        if shouldIgnoreInstance(obj, options.ignoreList) then
            return nil
        end
        
        local className = obj.ClassName
        local ref = generateReference(obj)
        local defaultProps = options.ignoreDefaults and getDefaultProperties(obj) or nil
        
        local xml = {string.format('<Item class="%s" referent="RBX%d">', className, ref)}
        table.insert(xml, '<Properties>')
        
        -- Save properties
        for _, propName in ipairs(obj:GetPropertyChangedSignal(""):GetConnections()) do
            local name = propName._name or propName.Name
            if name ~= "" and not options.ignoreProperties[name] then
                local success, value = pcall(function() return obj[name] end)
                if success and value ~= nil then
                    local propXml = saveProperty(obj, name, value, defaultProps)
                    if propXml then
                        table.insert(xml, propXml)
                    end
                end
            end
        end
        
        table.insert(xml, '</Properties>')
        
        -- Process children
        local children = obj:GetChildren()
        if #children > 0 then
            for _, child in ipairs(children) do
                local childXml = processInstance(child, depth + 1)
                if childXml then
                    table.insert(xml, childXml)
                end
            end
        end
        
        table.insert(xml, '</Item>')
        return table.concat(xml, '\n')
    end
    
    -- Start processing from root instance
    local rootXml = processInstance(instance, 0)
    if rootXml then
        table.insert(output, rootXml)
    end
    
    return table.concat(output, '\n')
end

local function saveToFile(content, filename)
    if services.HttpService and services.HttpService.JSONEncode then
        filename = sanitizeFilename(filename)
        
        -- Try to save directly first
        local success = pcall(function()
            writefile(filename, content)
        end)
        
        if not success then
            -- Fallback to chunked saving if direct save fails
            local chunkSize = 1000000  -- 1MB chunks
            for i = 1, math.ceil(#content / chunkSize) do
                local chunk = content:sub((i-1)*chunkSize+1, i*chunkSize)
                appendfile(filename, chunk)
            end
        end
        
        return true
    end
    
    return false
end

local function createStatusGui(message)
    if services.CoreGui then
        local gui = Instance.new("ScreenGui")
        gui.Name = "SaveInstanceStatus"
        gui.DisplayOrder = 999999
        
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(0, 300, 0, 60)
        frame.Position = UDim2.new(1, -310, 1, -70)
        frame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
        frame.BackgroundTransparency = 0.5
        frame.BorderSizePixel = 0
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -20, 1, -20)
        label.Position = UDim2.new(0, 10, 0, 10)
        label.Text = message
        label.TextColor3 = Color3.new(1, 1, 1)
        label.Font = Enum.Font.SourceSans
        label.TextSize = 18
        label.BackgroundTransparency = 1
        label.TextXAlignment = Enum.TextXAlignment.Left
        
        label.Parent = frame
        frame.Parent = gui
        
        -- Try to parent to CoreGui safely
        pcall(function() gui.Parent = services.CoreGui end)
        
        return gui
    end
    return nil
end

local function saveInstanceToFile(instance, options)
    options = options or {}
    options.ignoreList = options.ignoreList or {}
    options.ignoreProperties = options.ignoreProperties or {}
    options.ignoreDefaults = options.ignoreDefaults ~= false
    
    -- Add default ignores
    options.ignoreList["CoreGui"] = true
    options.ignoreList["CorePackages"] = true
    
    local statusGui
    if options.showStatus then
        statusGui = createStatusGui("Saving instance...")
    end
    
    local startTime = os.clock()
    local content = saveInstance(instance, options)
    local elapsed = os.clock() - startTime
    
    local filename
    if instance == game then
        local placeName = "Place"
        if services.MarketplaceService then
            local success, info = pcall(services.MarketplaceService.GetProductInfo, services.MarketplaceService, game.PlaceId)
            if success and info then
                placeName = info.Name
            end
        end
        filename = sanitizeFilename(placeName .. ".rbxlx")
    else
        filename = sanitizeFilename(instance.Name .. ".rbxmx")
    end
    
    -- Add XML header and footer
    local fullContent = '<?xml version="1.0" encoding="utf-8"?>\n<roblox version="4">\n' .. 
                        content .. '\n</roblox>'
    
    local success = saveToFile(fullContent, filename)
    
    if statusGui then
        if success then
            statusGui:FindFirstChildOfClass("TextLabel").Text = string.format(
                "Saved successfully!\nTime: %.2fs | Size: %s", 
                elapsed, 
                formatFileSize(#fullContent)
            )
            delay(5, function() pcall(function() statusGui:Destroy() end) end)
        else
            statusGui:FindFirstChildOfClass("TextLabel").Text = "Failed to save!"
            delay(3, function() pcall(function() statusGui:Destroy() end) end)
        end
    end
    
    return success, filename
end

-- Public API
return {
    save = function(options)
        return saveInstanceToFile(game, options)
    end,
    
    saveModel = function(instance, options)
        if not instance or not instance:IsA("Instance") then
            return false, "Invalid instance"
        end
        return saveInstanceToFile(instance, options)
    end
}
