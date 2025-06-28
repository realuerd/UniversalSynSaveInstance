--[[
    Advanced Instance Saver
    Ein leistungsfähiges Tool zum Speichern von Roblox-Instanzen in verschiedenen Formaten
    Entwickelt von [Dein Name]
--]]

local InstanceSaver = {}

-- Hilfsfunktionen
local function createBuffer()
    return {
        data = {},
        size = 0,
        add = function(self, str)
            self.size = self.size + 1
            self.data[self.size] = str
        end,
        concat = function(self)
            return table.concat(self.data)
        end,
        clear = function(self)
            table.clear(self.data)
            self.size = 0
        end
    }
end

local function getService(name)
    local success, service = pcall(game.GetService, game, name)
    return success and service or nil
end

-- Typkonvertierungen
local TypeHandlers = {
    Vector3 = function(vec)
        return string.format("<Vector3>%f,%f,%f</Vector3>", vec.X, vec.Y, vec.Z)
    end,
    
    Color3 = function(col)
        return string.format("<Color3>%f,%f,%f</Color3>", col.R, col.G, col.B)
    end,
    
    EnumItem = function(enum)
        return string.format("<Enum>%s.%s</Enum>", tostring(enum.EnumType), enum.Name)
    end,
    
    Instance = function(inst, refs)
        return string.format('<Ref>%d</Ref>', refs[inst] or -1)
    end
}

-- Hauptfunktion zum Speichern
function InstanceSaver.save(root, options)
    options = options or {}
    local refCounter = 0
    local references = {}
    local buffer = createBuffer()
    local sharedStrings = {}
    
    -- Header schreiben
    buffer:add('<?xml version="1.0"?>\n')
    buffer:add('<roblox xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n')
    
    local function processInstance(instance, depth)
        -- Referenz verwalten
        refCounter = refCounter + 1
        references[instance] = refCounter
        
        -- Einrückung
        local indent = string.rep("  ", depth)
        
        -- Instanz-Header
        buffer:add(string.format('%s<Item class="%s" referent="RBX%d">\n', 
            indent, instance.ClassName, refCounter))
        
        buffer:add(indent..'  <Properties>\n')
        
        -- Eigenschaften verarbeiten
        for _, prop in pairs(instance:GetProperties()) do
            if not options.skipProperties or not options.skipProperties[prop] then
                local value = instance[prop]
                local valueType = typeof(value)
                
                if TypeHandlers[valueType] then
                    local propValue = TypeHandlers[valueType](value, references)
                    buffer:add(string.format('%s    <%s name="%s">%s</%s>\n',
                        indent, valueType, prop, propValue, valueType))
                elseif valueType == "string" then
                    -- Strings sicher escapen
                    local escaped = value:gsub("[<>&\"']", {
                        ["<"] = "&lt;",
                        [">"] = "&gt;",
                        ["&"] = "&amp;",
                        ["\""] = "&quot;",
                        ["'"] = "&apos;"
                    })
                    buffer:add(string.format('%s    <string name="%s"><![CDATA[%s]]></string>\n',
                        indent, prop, escaped))
                elseif valueType == "number" then
                    buffer:add(string.format('%s    <float name="%s">%g</float>\n',
                        indent, prop, value))
                elseif valueType == "boolean" then
                    buffer:add(string.format('%s    <bool name="%s">%s</bool>\n',
                        indent, prop, value and "true" or "false"))
                end
            end
        end
        
        buffer:add(indent..'  </Properties>\n')
        
        -- Kinder verarbeiten
        if #instance:GetChildren() > 0 then
            for _, child in ipairs(instance:GetChildren()) do
                processInstance(child, depth + 1)
            end
        end
        
        buffer:add(indent..'</Item>\n')
    end
    
    -- Hauptinstanz verarbeiten
    processInstance(root, 1)
    
    -- Shared Strings hinzufügen
    if next(sharedStrings) then
        buffer:add('  <SharedStrings>\n')
        for id, str in pairs(sharedStrings) do
            buffer:add(string.format('    <SharedString md5="%s">%s</SharedString>\n', id, str))
        end
        buffer:add('  </SharedStrings>\n')
    end
    
    -- Footer
    buffer:add('</roblox>')
    
    return buffer:concat()
end

-- Optionen für verschiedene Speichermodi
InstanceSaver.presets = {
    full = {
        skipProperties = {
            -- Keine Eigenschaften werden übersprungen
        }
    },
    
    optimized = {
        skipProperties = {
            -- Häufig unnötige Eigenschaften
            "Archivable" = true,
            "RobloxLocked" = true
        }
    },
    
    scriptsOnly = {
        skipProperties = function(instance, prop)
            -- Nur Skript-relevante Eigenschaften behalten
            return not (instance:IsA("LuaSourceContainer") and prop ~= "Name"
        end
    }
}

-- Hilfsfunktion zum Dateischreiben
function InstanceSaver.saveToFile(instance, filename, options)
    local content = InstanceSaver.save(instance, options)
    
    if options and options.callback then
        options.callback(content)
    else
        writefile(filename, content)
    end
    
    return true
end

return InstanceSaver
