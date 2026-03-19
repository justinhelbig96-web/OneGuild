------------------------------------------------------------------------
-- OneGuild - Core.lua
-- Addon initialization, guild lock, database & utility functions
------------------------------------------------------------------------

-- EARLY DEBUG: This prints BEFORE anything else loads
print("|cFFFFB800[OneGuild]|r Core.lua wird geladen...")

local ADDON_NAME, OneGuild = ...
_G.OneGuild = OneGuild

------------------------------------------------------------------------
-- GUILD LOCK  –  This addon ONLY works for members of this guild.
-- Change the name below to lock to a different guild.
------------------------------------------------------------------------
OneGuild.REQUIRED_GUILD = "One"

------------------------------------------------------------------------
-- Version & Constants
------------------------------------------------------------------------
OneGuild.VERSION = "1.0.8c"

------------------------------------------------------------------------
-- Admin Whitelist  –  Characters listed here get auto-admin rights.
-- Also: the guild leader (rank index 0) is always auto-admin.
------------------------------------------------------------------------
OneGuild.ADMIN_WHITELIST = {
    ["Rigipsplatte"] = true,
}

OneGuild.COLORS = {
    TITLE   = "|cFFFFB800",    -- Gold
    SUCCESS = "|cFF66FF66",    -- Soft Green
    WARNING = "|cFFFFCC00",    -- Yellow-Gold
    ERROR   = "|cFFFF4444",    -- Red
    INFO    = "|cFFDDB866",    -- Warm Gold
    MUTED   = "|cFF8B7355",    -- Warm Grey-Brown
    GUILD   = "|cFFFFD700",    -- Bright Gold
    BRONZE  = "|cFF8B6914",    -- Dark Bronze
    DARKRED = "|cFF6B1010",    -- Dark Red
}

local DEFAULTS = {
    events       = {},
    raids        = {},
    notes        = {},
    characters   = {},
    addonMembers = {},        -- { ["Name-Realm"] = { main, classFile, level, lastSeen, version } }
    dkp          = {},        -- { ["Name-Realm"] = number }  DKP per member
    dkpHistory   = {},        -- { { player, amount, newTotal, bonusType, source, timestamp } }
    auctionHistory = {},      -- { { itemLink, itemName, auctioneer, winner, winAmount, timestamp } }
    deletedRaids  = {},       -- { ["created:author"] = true }  tombstones for deleted raids
    deletedEvents = {},       -- { ["created:author"] = true }  tombstones for deleted events
    raidGroups   = {},        -- global raid groups { [1..8] = { "Name", ... } }
    lootmeister  = nil,       -- global lootmeister name (short)
    settings     = {
        minimap        = true,
        soundAlerts    = true,
        openOnLogin    = false,
        mapShowPins    = true,
        mapShowNames   = true,
        mapPinSize     = 16,
        mapLabelSize   = 10,
        mapPinAlpha    = 0.9,
        lootAutoPass   = true,    -- auto-pass in guild raids
        dkpPermission  = "officer",  -- who can edit DKP: "leader", "officer", "raidlead", "all"
    },
    dismissed    = false,
    welcomeDismissedVersion = "",
    rulesAccepted = false,
    guildBankMoney = 0,
}

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
OneGuild.isGuildVerified = false
OneGuild.playerGuild     = nil
OneGuild.playerName      = nil
OneGuild.debugMode       = true   -- DEBUG: auf false setzen um Debug-Ausgaben zu deaktivieren
OneGuild.newerVersion    = nil    -- set to newer version string if a guild member has a higher version

--- Compare two semver strings ("1.2.3"). Returns 1 if a>b, -1 if a<b, 0 if equal.
function OneGuild:CompareVersions(a, b)
    if not a or not b then return 0 end
    local a1, a2, a3 = strsplit(".", a)
    local b1, b2, b3 = strsplit(".", b)
    a1, a2, a3 = tonumber(a1) or 0, tonumber(a2) or 0, tonumber(a3) or 0
    b1, b2, b3 = tonumber(b1) or 0, tonumber(b2) or 0, tonumber(b3) or 0
    if a1 ~= b1 then return a1 > b1 and 1 or -1 end
    if a2 ~= b2 then return a2 > b2 and 1 or -1 end
    if a3 ~= b3 then return a3 > b3 and 1 or -1 end
    return 0
end

OneGuild.GITHUB_URL = "https://github.com/justinhelbig96-web/OneGuild/releases"

------------------------------------------------------------------------
-- Event Frame
------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame", "OneGuildEventFrame", UIParent)
OneGuild.eventFrame = eventFrame

local registeredEvents = {
    "ADDON_LOADED",
    "PLAYER_LOGIN",
    "PLAYER_GUILD_UPDATE",
    "GUILD_ROSTER_UPDATE",
    "GUILD_MOTD",
    "GUILD_NEWS_UPDATE",
    "CHAT_MSG_GUILD",
    "GUILD_RANKS_UPDATE",
    "CHAT_MSG_ADDON",
    "PLAYER_LOGOUT",
    "PLAYER_LEAVING_WORLD",
    "GUILDBANKFRAME_OPENED",
    "GUILDBANK_UPDATE_MONEY",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
}

for _, event in ipairs(registeredEvents) do
    pcall(function() eventFrame:RegisterEvent(event) end)
end

------------------------------------------------------------------------
-- Database
------------------------------------------------------------------------
function OneGuild:InitDB()
    if not OneGuildDB then
        OneGuildDB = {}
    end
    for key, default in pairs(DEFAULTS) do
        if OneGuildDB[key] == nil then
            if type(default) == "table" then
                OneGuildDB[key] = self:DeepCopy(default)
            else
                OneGuildDB[key] = default
            end
        end
    end
    self.db = OneGuildDB
end

function OneGuild:DeepCopy(orig)
    local copy = {}
    for k, v in pairs(orig) do
        if type(v) == "table" then
            copy[k] = self:DeepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

------------------------------------------------------------------------
-- Chat Helpers
------------------------------------------------------------------------
local PREFIX = OneGuild.COLORS.TITLE .. "OneGuild|r: "

function OneGuild:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

function OneGuild:PrintError(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. self.COLORS.ERROR .. msg .. "|r")
end

function OneGuild:PrintSuccess(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. self.COLORS.SUCCESS .. msg .. "|r")
end

function OneGuild:Debug(msg)
    if self.debugMode then
        DEFAULT_CHAT_FRAME:AddMessage("|cFF666666[OG-Debug]|r " .. tostring(msg))
    end
end

------------------------------------------------------------------------
-- Guild Verification  –  The heart of the guild lock
------------------------------------------------------------------------
function OneGuild:VerifyGuild()
    self:Debug("--- Guild Verification gestartet ---")
    self:Debug("IsInGuild() = " .. tostring(IsInGuild()))

    if IsInGuild() then
        local guildName, guildRankName, guildRankIndex, realm = GetGuildInfo("player")
        self:Debug("GetGuildInfo() = " .. tostring(guildName)
            .. "  |  Rang: " .. tostring(guildRankName)
            .. " (" .. tostring(guildRankIndex) .. ")"
            .. "  |  Realm: " .. tostring(realm))
        self:Debug("Erwartete Gilde: '" .. self.REQUIRED_GUILD .. "'")

        if guildName then
            self:Debug("Vergleich: '" .. guildName .. "' == '" .. self.REQUIRED_GUILD
                .. "' → " .. tostring(guildName == self.REQUIRED_GUILD))
            self.playerGuild = guildName
            if guildName == self.REQUIRED_GUILD then
                self.isGuildVerified = true
                self:Debug("|cFF00FF00✔ VERIFIZIERT|r — Gilde stimmt überein!")
                return true
            else
                self.isGuildVerified = false
                self:Debug("|cFFFF3333✘ ABGELEHNT|r — Gilde stimmt NICHT überein!")
                self:PrintError("Dieses Addon ist exklusiv für die Gilde <" ..
                    self.REQUIRED_GUILD .. ">. Du bist in <" .. guildName .. ">.")
                return false
            end
        else
            self:Debug("|cFFFFCC00GetGuildInfo() hat nil zurückgegeben (Daten noch nicht geladen)|r")
        end
    else
        self.isGuildVerified = false
        self:Debug("|cFFFF3333✘ Spieler ist in KEINER Gilde|r")
        self:PrintError("Du bist in keiner Gilde. Dieses Addon ist exklusiv für <" ..
            self.REQUIRED_GUILD .. ">.")
        return false
    end
    return false
end

--- Guard function: returns true if the addon should proceed
function OneGuild:IsAuthorized()
    return self.isGuildVerified == true
end

------------------------------------------------------------------------
-- Auto-Admin  –  guild leader (rank index 0) + whitelist get admin
------------------------------------------------------------------------
function OneGuild:CheckAutoAdmin()
    if self.isAdmin then return end   -- already admin
    if not IsInGuild() then return end

    local playerName = UnitName("player") or ""

    -- 1) Check whitelist
    if self.ADMIN_WHITELIST and self.ADMIN_WHITELIST[playerName] then
        self.isAdmin = true
        self:PrintSuccess("Auto-Admin: Du bist auf der Whitelist.")
        return
    end

    -- 2) Check guild leader (rankIndex 0 = Gildenmeister)
    local _, _, rankIndex = GetGuildInfo("player")
    if rankIndex and rankIndex == 0 then
        self.isAdmin = true
        self:PrintSuccess("Auto-Admin: Du bist Gildenmeister.")
        return
    end
end

------------------------------------------------------------------------
-- DKP Permission Check
-- Returns true if the current player can edit/distribute DKP
------------------------------------------------------------------------
function OneGuild:CanEditDKP()
    local myName = UnitName("player") or ""

    -- Whitelist always allowed
    if self.ADMIN_WHITELIST and self.ADMIN_WHITELIST[myName] then return true end

    -- Guild leader (rank 0) always allowed
    local _, _, rankIndex = GetGuildInfo("player")
    if rankIndex and rankIndex == 0 then return true end

    -- Check setting
    local perm = (self.db and self.db.settings and self.db.settings.dkpPermission) or "officer"

    if perm == "leader" then
        -- Only rank 0 + whitelist (already checked above)
        return false
    elseif perm == "officer" then
        -- Officers = rank 0 or 1
        if rankIndex and rankIndex <= 1 then return true end
        return false
    elseif perm == "raidlead" then
        -- Officers + RL/Assist in raid
        if rankIndex and rankIndex <= 1 then return true end
        if IsInRaid() then
            if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
                return true
            end
        end
        return false
    elseif perm == "all" then
        return true
    end

    return false
end

------------------------------------------------------------------------
-- Permission Settings Check
-- Only Whitelist + rank 0/1 can change permission settings
------------------------------------------------------------------------
function OneGuild:CanEditPermissions()
    local myName = UnitName("player") or ""
    if self.ADMIN_WHITELIST and self.ADMIN_WHITELIST[myName] then return true end
    local _, _, rankIndex = GetGuildInfo("player")
    if rankIndex and rankIndex ~= nil and rankIndex <= 1 then return true end
    return false
end

------------------------------------------------------------------------
-- DKP History  — stores every DKP change for auditability
-- Each entry: { player, amount, newTotal, bonusType, source, timestamp }
------------------------------------------------------------------------
function OneGuild:AddDKPHistory(player, amount, newTotal, bonusType, source)
    if not self.db then return end
    if not self.db.dkpHistory then self.db.dkpHistory = {} end
    table.insert(self.db.dkpHistory, {
        player    = player,
        amount    = amount,
        newTotal  = newTotal,
        bonusType = bonusType or "manual",
        source    = source or (UnitName("player") or "?"),
        timestamp = time(),
    })
    -- Cap at 500 entries to avoid SavedVariables bloat
    while #self.db.dkpHistory > 500 do
        table.remove(self.db.dkpHistory, 1)
    end
end

------------------------------------------------------------------------
-- CENTRAL DKP FUNCTIONS  — single source of truth for all DKP access
-- Internally uses SHORT NAME (e.g. "Rigipsplatte") as canonical key.
------------------------------------------------------------------------
function OneGuild:NormalizeDKPKey(nameOrKey)
    if not nameOrKey then return nil end
    local short = strsplit("-", nameOrKey)
    return short
end

-- Collect all known keys for a player (short + full variants)
function OneGuild:GetAllDKPKeys(nameOrKey)
    local short = strsplit("-", nameOrKey)
    local keys = { short }
    if nameOrKey ~= short then
        table.insert(keys, nameOrKey)
    end
    -- Also check addonMembers for other sender keys for same main
    if self.db and self.db.addonMembers then
        for senderKey, member in pairs(self.db.addonMembers) do
            local sk = strsplit("-", senderKey)
            if sk == short then
                if senderKey ~= short then
                    local found = false
                    for _, k in ipairs(keys) do
                        if k == senderKey then found = true; break end
                    end
                    if not found then table.insert(keys, senderKey) end
                end
            end
        end
    end
    return keys
end

function OneGuild:GetDKPForPlayer(nameOrKey)
    if not self.db or not self.db.dkp then return 0 end
    local short = self:NormalizeDKPKey(nameOrKey)
    if not short then return 0 end
    return self.db.dkp[short] or 0
end

function OneGuild:SetDKPForPlayer(nameOrKey, val)
    if not self.db then return end
    if not self.db.dkp then self.db.dkp = {} end
    local allKeys = self:GetAllDKPKeys(nameOrKey)
    -- Store under ALL known keys so any lookup path finds the same value
    for _, k in ipairs(allKeys) do
        self.db.dkp[k] = val
    end
end

------------------------------------------------------------------------
-- Utility: Format timestamp
------------------------------------------------------------------------
function OneGuild:FormatTime(timestamp)
    return date("%d.%m.%Y %H:%M", timestamp)
end

function OneGuild:FormatDate(timestamp)
    return date("%d.%m.%Y", timestamp)
end

function OneGuild:GetPlayerName()
    if not self.playerName then
        local name = UnitName("player")
        self.playerName = name or "Unknown"
    end
    return self.playerName
end


------------------------------------------------------------------------
-- Slash Commands
------------------------------------------------------------------------
SLASH_ONEGUILD1 = "/oneguild"
SLASH_ONEGUILD2 = "/og"

SlashCmdList["ONEGUILD"] = function(msg)
    msg = strtrim(msg or ""):lower()

    -- Debug commands work regardless of guild authorization
    if msg == "debug delete" or msg == "debug reset" then
        OneGuildDB = nil
        OneGuild.db = nil
        OneGuild.isGuildVerified = false
        OneGuild.playerGuild = nil
        if OneGuild.mainFrame then OneGuild.mainFrame:Hide() end
        if OneGuild.mainSelectFrame then OneGuild.mainSelectFrame:Hide() end
        print("|cFFFF4444[OneGuild]|r Alle Daten geloescht! Bitte |cFFFFD700/reload|r eingeben!")
        return
    end

    if not OneGuild:IsAuthorized() then
        OneGuild:VerifyGuild()
        return
    end

    if msg == "" or msg == "show" or msg == "toggle" then
        OneGuild:ToggleMainWindow()
    elseif msg == "members" or msg == "mitglieder" then
        OneGuild:ToggleMainWindow()
        if OneGuild.mainFrame then
            OneGuild:ShowTab(1)
        end
    elseif msg == "events" then
        OneGuild:ToggleMainWindow()
        if OneGuild.mainFrame then
            OneGuild:ShowTab(2)
        end
    elseif msg == "raid" then
        OneGuild:ToggleMainWindow()
        if OneGuild.mainFrame then
            OneGuild:ShowTab(3)
        end
    elseif msg == "notes" then
        OneGuild:ToggleMainWindow()
        if OneGuild.mainFrame then
            OneGuild:ShowTab(4)
        end
    elseif msg == "chars" or msg == "characters" then
        OneGuild:ToggleMainWindow()
        if OneGuild.mainFrame then
            OneGuild:ShowTab(5)
        end
    elseif msg == "main" then
        local mainKey, mainChar = OneGuild:GetMainCharacter()
        if mainChar then
            OneGuild:Print(OneGuild.COLORS.WARNING .. "Main: " ..
                mainChar.name .. "-" .. mainChar.realm ..
                " (Lvl " .. mainChar.level .. " " .. mainChar.className .. ")|r")
        else
            OneGuild:Print(OneGuild.COLORS.WARNING .. "Kein Main gesetzt! Nutze /og chars|r")
        end
    elseif msg == "setmain" then
        OneGuild:ShowMainSelectionDialog()
    elseif msg == "map" then
        if OneGuild.ToggleMapPins then
            OneGuild:ToggleMapPins()
        else
            OneGuild:Print(OneGuild.COLORS.ERROR .. "Karten-Modul nicht geladen.|r")
        end
    elseif msg == "groups" or msg == "gruppen" then
        if OneGuild.ToggleRaidGroups then
            OneGuild:ToggleRaidGroups()
        else
            OneGuild:Print(OneGuild.COLORS.ERROR .. "RaidGroups-Modul nicht geladen.|r")
        end
    elseif msg == "lootcheck" then
        if OneGuild.StartAddonCheck then
            OneGuild:StartAddonCheck()
        else
            OneGuild:Print(OneGuild.COLORS.ERROR .. "Loot-Modul nicht geladen.|r")
        end
    elseif msg == "settings" or msg == "options" then
        if OneGuild.ToggleSettings then
            OneGuild:ToggleSettings()
        else
            OneGuild:Print(OneGuild.COLORS.ERROR .. "Einstellungen nicht geladen.|r")
        end
    elseif msg == "motd" then
        local motd = GetGuildRosterMOTD()
        if motd and motd ~= "" then
            OneGuild:Print(OneGuild.COLORS.GUILD .. "MOTD: " .. motd .. "|r")
        else
            OneGuild:Print(OneGuild.COLORS.MUTED .. "Kein MOTD gesetzt.|r")
        end
    elseif msg == "help" then
        OneGuild:Print("Befehle:")
        OneGuild:Print("  /og         - Hauptfenster öffnen/schließen")
        OneGuild:Print("  /og members  - Mitglieder anzeigen")
        OneGuild:Print("  /og events   - Event-Planer anzeigen")
        OneGuild:Print("  /og raid     - Raid-Planer anzeigen")
        OneGuild:Print("  /og notes    - Notizen anzeigen")
        OneGuild:Print("  /og chars    - Meine Charaktere")
        OneGuild:Print("  /og main     - Main-Charakter anzeigen")
        OneGuild:Print("  /og setmain  - Main-Charakter wählen")
        OneGuild:Print("  /og motd     - MOTD im Chat anzeigen")
        OneGuild:Print("  /og map      - Karten-Pins an/aus")
        OneGuild:Print("  /og groups   - Raid-Gruppen öffnen")
        OneGuild:Print("  /og lootcheck - Addon-Check starten")
        OneGuild:Print("  /og settings - Einstellungen öffnen")
        OneGuild:Print("  /og debug delete - Alle Daten zurücksetzen (Test)")
        OneGuild:Print("  /og help     - Diese Hilfe")
    else
        OneGuild:Print("Unbekannter Befehl. Nutze " ..
            OneGuild.COLORS.INFO .. "/og help|r für eine Übersicht.")
    end
end

------------------------------------------------------------------------
-- Baganator Hook  –  detect guild bank open even when Baganator
-- replaces the default guild bank UI
------------------------------------------------------------------------
function OneGuild:HandleGuildBankOpen()
    C_Timer.After(0.5, function()
        local money = GetGuildBankMoney and GetGuildBankMoney() or 0
        OneGuild:Debug("GuildBank open → money = " .. tostring(money))
        if money > 0 and OneGuild.db then
            OneGuild.db.guildBankMoney = money
            if OneGuild.SendCommMessage then
                OneGuild:SendCommMessage("GLD", tostring(money))
            end
            if OneGuild.UpdateGoldDisplay then
                OneGuild:UpdateGoldDisplay()
            end
        end
    end)
    -- Second attempt after data is fully loaded
    C_Timer.After(2, function()
        local money = GetGuildBankMoney and GetGuildBankMoney() or 0
        if money > 0 and OneGuild.db then
            OneGuild.db.guildBankMoney = money
            if OneGuild.SendCommMessage then
                OneGuild:SendCommMessage("GLD", tostring(money))
            end
            if OneGuild.UpdateGoldDisplay then
                OneGuild:UpdateGoldDisplay()
            end
        end
    end)
end

function OneGuild:HookBaganatorGuildBank()
    -- Hook Baganator's guild bank frame if it exists
    local bagFrame = _G["BaganatorGuildViewFrame"] or _G["Baganator_GuildViewFrame"]
    if bagFrame and bagFrame.HookScript then
        bagFrame:HookScript("OnShow", function()
            OneGuild:Debug("Baganator GuildBank frame detected → reading money")
            OneGuild:HandleGuildBankOpen()
        end)
        OneGuild:Debug("Baganator guild bank hook installed")
    else
        -- Try generic: hook any frame named with "GuildBank" from Baganator
        if IsAddOnLoaded and IsAddOnLoaded("Baganator") or
           C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Baganator") then
            OneGuild:Debug("Baganator loaded but guild view frame not found yet, trying delayed hook")
            C_Timer.After(5, function()
                local f = _G["BaganatorGuildViewFrame"] or _G["Baganator_GuildViewFrame"]
                if f and f.HookScript then
                    f:HookScript("OnShow", function()
                        OneGuild:Debug("Baganator GuildBank frame (delayed) → reading money")
                        OneGuild:HandleGuildBankOpen()
                    end)
                    OneGuild:Debug("Baganator guild bank hook installed (delayed)")
                end
            end)
        end
    end
end

------------------------------------------------------------------------
-- Main Event Handler
------------------------------------------------------------------------
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == ADDON_NAME then
            OneGuild:InitDB()
            OneGuild:Print("v" .. OneGuild.VERSION .. " geladen. Warte auf Gilden-Verifizierung...")
        end

    elseif event == "PLAYER_LOGIN" then
        OneGuild:Debug("PLAYER_LOGIN Event empfangen")
        OneGuild:Debug("Spieler: " .. tostring(UnitName("player")) .. "  Realm: " .. tostring(GetRealmName()))
        OneGuild:Debug("Warte 2 Sekunden auf Gilden-Daten...")
        -- Small delay to ensure guild info is available
        C_Timer.After(2, function()
            OneGuild:Debug("Timer abgelaufen — starte Verifizierung")
            if OneGuild:VerifyGuild() then
                OneGuild:PrintSuccess("Gilde <" .. OneGuild.REQUIRED_GUILD ..
                    "> verifiziert! Addon aktiv.")
                OneGuild:BuildMainFrame()

                -- Register this character in account-wide DB
                if OneGuild.RegisterCurrentCharacter then
                    OneGuild:RegisterCurrentCharacter()
                end

                -- Request guild roster data
                if C_GuildInfo and C_GuildInfo.GuildRoster then
                    C_GuildInfo.GuildRoster()
                elseif GuildRoster then
                    GuildRoster()
                end

                -- Auto-admin check (guild leader + whitelist)
                C_Timer.After(1, function()
                    OneGuild:CheckAutoAdmin()
                end)

                -- First-time setup: show rules if not yet accepted
                if OneGuild.CheckRulesAccepted then
                    OneGuild:CheckRulesAccepted()
                end

                -- Show welcome screen if not dismissed for this version
                if OneGuild.ShouldShowWelcome and OneGuild:ShouldShowWelcome() then
                    OneGuild:ShowWelcomeScreen()
                end

                -- Initialize addon communication
                if OneGuild.InitComm then
                    OneGuild:InitComm()
                end

                -- Initialize map position tracking
                if OneGuild.InitMap then
                    OneGuild:InitMap()
                end

                -- Hook into Communities Frame (J key)
                if OneGuild.HookCommunitiesFrame then
                    OneGuild:HookCommunitiesFrame()
                end

                if OneGuild.db.settings.openOnLogin then
                    OneGuild:ToggleMainWindow()
                end

                -- Initialize loot system
                if OneGuild.InitLoot then
                    OneGuild:InitLoot()
                end

                -- Hook Baganator guild bank view (if Baganator is loaded)
                C_Timer.After(3, function()
                    OneGuild:HookBaganatorGuildBank()
                end)
            end
        end)

    elseif event == "PLAYER_GUILD_UPDATE" then
        -- Re-verify if guild status changes (kicked, gquit, etc.)
        C_Timer.After(1, function()
            local wasVerified = OneGuild.isGuildVerified
            OneGuild:VerifyGuild()
            if wasVerified and not OneGuild.isGuildVerified then
                OneGuild:PrintError("Du bist nicht mehr in <" .. OneGuild.REQUIRED_GUILD ..
                    ">. Addon deaktiviert.")
                if OneGuild.mainFrame and OneGuild.mainFrame:IsShown() then
                    OneGuild.mainFrame:Hide()
                end
            end
        end)

    elseif event == "GUILD_ROSTER_UPDATE" then
        -- Guild roster data updated
        if OneGuild:IsAuthorized() and OneGuild.RefreshMembers then
            OneGuild:RefreshMembers()
        end
        -- Load DKP from officer notes (throttled to avoid spam)
        if OneGuild:IsAuthorized() and OneGuild.LoadDKPFromOfficerNotes then
            if not OneGuild._lastOfficerNoteLoad or (time() - OneGuild._lastOfficerNoteLoad) >= 10 then
                OneGuild._lastOfficerNoteLoad = time()
                OneGuild:LoadDKPFromOfficerNotes()
            end
        end

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        if OneGuild.HandleAddonMessage then
            OneGuild:HandleAddonMessage(prefix, message, channel, sender)
        end

    elseif event == "PLAYER_LOGOUT" or event == "PLAYER_LEAVING_WORLD" then
        -- Send BYE to guild so others know we're going offline
        if OneGuild.SendBye then
            OneGuild:SendBye()
        end

    elseif event == "GUILD_MOTD" then
        if OneGuild:IsAuthorized() then
            local motd = ...
            if motd and motd ~= "" then
                OneGuild:Print(OneGuild.COLORS.GUILD .. "Neues MOTD: " .. motd .. "|r")
            end
            if OneGuild.UpdateMOTDDisplay then
                OneGuild:UpdateMOTDDisplay()
            end
        end

    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        local interactionType = ...
        -- Guild bank = 10 (Enum.PlayerInteractionType.GuildBanker)
        local guildBankType = 10
        if Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker then
            guildBankType = Enum.PlayerInteractionType.GuildBanker
        end
        if interactionType == guildBankType then
            OneGuild:Debug("Gildenbank geoeffnet (InteractionManager)")
            OneGuild:HandleGuildBankOpen()
        end

    elseif event == "GUILDBANKFRAME_OPENED" or event == "GUILDBANK_UPDATE_MONEY" then
        OneGuild:Debug("Gildenbank Event: " .. event)
        if OneGuild:IsAuthorized() then
            OneGuild:HandleGuildBankOpen()
        end
    end
end)

------------------------------------------------------------------------
-- Officer Note DKP Storage
-- Format in officer note: "DKP:123"
------------------------------------------------------------------------
function OneGuild:SaveDKPToOfficerNote(memberKey, dkpVal)
    if not IsInGuild() then return end
    if not CanEditOfficerNote or not CanEditOfficerNote() then return end

    local shortName = strsplit("-", memberKey)
    local numGuild = GetNumGuildMembers() or 0
    for i = 1, numGuild do
        local gName, _, _, _, _, _, _, officerNote = GetGuildRosterInfo(i)
        if gName then
            local gs = strsplit("-", gName)
            if gs == shortName or gName == memberKey then
                local newNote = "DKP:" .. tostring(dkpVal)
                GuildRosterSetOfficerNote(i, newNote)
                self:Debug("DKP in Offiziersnotiz gespeichert: " .. gs .. " = " .. tostring(dkpVal))
                return
            end
        end
    end
end

function OneGuild:LoadDKPFromOfficerNotes()
    if not IsInGuild() then return end
    if not self.db then return end
    if not self.db.dkp then self.db.dkp = {} end

    local numGuild = GetNumGuildMembers() or 0
    local loaded = 0
    for i = 1, numGuild do
        local gName, _, _, _, _, _, _, officerNote = GetGuildRosterInfo(i)
        if gName and officerNote then
            local dkpStr = officerNote:match("DKP:(-?%d+)")
            if dkpStr then
                local dkpVal = tonumber(dkpStr) or 0
                -- Use centralized setter to store under all known keys
                self:SetDKPForPlayer(gName, dkpVal)
                loaded = loaded + 1
            end
        end
    end
    if loaded > 0 then
        self:Debug("DKP aus Offiziersnotizen geladen: " .. loaded .. " Spieler")
    end
end
