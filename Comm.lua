------------------------------------------------------------------------
-- OneGuild - Comm.lua
-- Addon-to-addon communication via guild channel
-- Syncs presence, characters, raids, events & signups
------------------------------------------------------------------------
print("|cFFFFB800[OneGuild]|r Comm.lua wird geladen...")

local _, OneGuild = ...

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local COMM_PREFIX = "OGuild1"
local SYNC_INTERVAL = 180           -- full auto-sync every 180 seconds (3 min)

-- Message types (keep short — WoW addon message limit is 255 bytes)
local MSG_HELLO    = "HI"           -- presence / main info
local MSG_SYNC     = "SYNC"         -- request everyone to re-broadcast
local MSG_BYE      = "BYE"          -- going offline
local MSG_CHARINFO = "CHR"          -- one character row
local MSG_RAID     = "RD"           -- one raid definition
local MSG_RAIDSIGN = "RS"           -- one raid signup
local MSG_EVENT    = "EV"           -- one event definition
local MSG_EVTSIGN  = "ES"           -- one event signup
local MSG_DKP      = "DK"           -- DKP update for a member
local MSG_RAIDDEL  = "RDD"          -- raid deleted (tombstone)
local MSG_EVTDEL   = "EVD"          -- event deleted (tombstone)
local MSG_POS      = "POS"          -- player position broadcast
local MSG_GOLD     = "GLD"          -- guild bank money update
local MSG_LCHECK   = "LCK"          -- loot addon-check request
local MSG_LREPLY   = "LCR"          -- loot addon-check response
local MSG_LACTIVATE = "LAP"         -- loot auto-pass activate/deactivate
local MSG_RGROUPS  = "RGS"          -- raid groups sync
local MSG_GGROUP   = "GGR"          -- global group assignment sync
local MSG_GLM      = "GLM"          -- global lootmeister sync
local MSG_AUCSTART = "ACS"          -- DKP auction start
local MSG_AUCBID   = "ACB"          -- DKP auction bid
local MSG_AUCEND   = "ACE"          -- DKP auction end (winner)
local MSG_AUCCANCEL= "ACC"          -- DKP auction cancel
local MSG_WLSYNC   = "WLS"          -- whitelist sync

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local isCommReady = false
local syncTicker  = nil

------------------------------------------------------------------------
-- Initialize comm system
------------------------------------------------------------------------
function OneGuild:InitComm()
    if isCommReady then return end

    local ok = C_ChatInfo.RegisterAddonMessagePrefix(COMM_PREFIX)
    if ok then
        self:Debug("Comm: Prefix '" .. COMM_PREFIX .. "' registriert")
    else
        self:Debug("Comm: Prefix-Registrierung fehlgeschlagen")
    end

    isCommReady = true

    -- Initial broadcast after a short delay
    C_Timer.After(4, function()
        OneGuild:FullSync()
    end)

    -- Request other members to also send their data (for new members)
    -- Send MSG_SYNC with short delay so others respond
    C_Timer.After(6, function()
        if OneGuild:IsAuthorized() then
            OneGuild:SendCommMessage(MSG_SYNC)
        end
    end)

    -- Auto-sync every SYNC_INTERVAL seconds
    syncTicker = C_Timer.NewTicker(SYNC_INTERVAL, function()
        if OneGuild:IsAuthorized() then
            OneGuild:FullSync()
        end
    end)

    -- Push all local DKP to officer notes (in case they got out of sync)
    C_Timer.After(10, function()
        if OneGuild:IsAuthorized() and OneGuild.PushAllDKPToOfficerNotes then
            OneGuild:PushAllDKPToOfficerNotes()
        end
    end)
end

------------------------------------------------------------------------
-- Send a raw addon message
------------------------------------------------------------------------
function OneGuild:SendCommMessage(msgType, data)
    if not isCommReady then return end
    if not IsInGuild() then return end

    local payload = msgType
    if data then
        payload = msgType .. ":" .. data
    end

    C_ChatInfo.SendAddonMessage(COMM_PREFIX, payload, "GUILD")
    if msgType ~= "POS" then
        self:Debug("Comm TX: " .. payload)
    end
end

------------------------------------------------------------------------
-- Send auction message to RAID or PARTY channel (more reliable than GUILD)
-- Falls back to GUILD if not in a group
------------------------------------------------------------------------
function OneGuild:SendAuctionMessage(msgType, data)
    if not isCommReady then return end

    local payload = msgType
    if data then payload = msgType .. ":" .. data end

    if IsInRaid() then
        C_ChatInfo.SendAddonMessage(COMM_PREFIX, payload, "RAID")
        self:Debug("AUC TX [RAID]: " .. strsub(payload, 1, 80))
    elseif IsInGroup() then
        C_ChatInfo.SendAddonMessage(COMM_PREFIX, payload, "PARTY")
        self:Debug("AUC TX [PARTY]: " .. strsub(payload, 1, 80))
    elseif IsInGuild() then
        -- Fallback to GUILD if somehow not in group
        C_ChatInfo.SendAddonMessage(COMM_PREFIX, payload, "GUILD")
        self:Debug("AUC TX [GUILD fallback]: " .. strsub(payload, 1, 80))
    end
end

------------------------------------------------------------------------
-- FullSync  -- broadcast EVERYTHING (called on init, button & timer)
------------------------------------------------------------------------
function OneGuild:FullSync()
    if not self:IsAuthorized() then return end

    -- Clean up stale tombstones (older than 7 days)
    self:CleanOldTombstones()

    self:BroadcastPresence()
    -- Do NOT broadcast MSG_SYNC — avoid thundering herd!
    -- MSG_SYNC was causing every member to respond with FullSync simultaneously.

    local delay = 0.5
    -- characters
    delay = self:BroadcastCharacters(delay)
    -- raids
    delay = self:BroadcastAllRaids(delay)
    -- events
    delay = self:BroadcastAllEvents(delay)
    -- dkp
    delay = self:BroadcastAllDKP(delay)
    -- whitelist
    delay = self:BroadcastWhitelist(delay)
    -- tombstones (deleted raids/events)
    delay = self:BroadcastTombstones(delay)

    self:Debug("Comm: FullSync gestartet (broadcasts bis +" .. delay .. "s)")
end

------------------------------------------------------------------------
-- BroadcastPresence  -- announce ourselves + store in addonMembers
------------------------------------------------------------------------
function OneGuild:BroadcastPresence()
    if not self:IsAuthorized() then return end
    if not self.db then return end

    local mainKey, mainChar = nil, nil
    if self.GetMainCharacter then
        mainKey, mainChar = self:GetMainCharacter()
    end

    local parts = {}
    if mainChar then
        parts[1] = mainChar.name or "?"
        parts[2] = mainChar.realm or "?"
        parts[3] = mainChar.classFile or "WARRIOR"
        parts[4] = tostring(mainChar.level or 0)
        parts[5] = mainChar.className or "Unknown"
    else
        parts[1] = "?"
        parts[2] = "?"
        parts[3] = "?"
        parts[4] = "0"
        parts[5] = "?"
    end
    parts[6] = self.VERSION or "0"

    self:SendCommMessage(MSG_HELLO, table.concat(parts, "|"))

    -- Register self in addonMembers
    local myName  = UnitName("player")
    local myRealm = GetNormalizedRealmName() or GetRealmName() or ""
    local myFull  = myName .. "-" .. myRealm
    if not self.db.addonMembers then self.db.addonMembers = {} end

    local selfEntry = {
        sender        = myFull,
        mainName      = mainChar and mainChar.name or "?",
        mainRealm     = mainChar and mainChar.realm or "?",
        mainClass     = mainChar and mainChar.classFile or "?",
        mainLevel     = mainChar and mainChar.level or 0,
        mainClassName = mainChar and mainChar.className or "?",
        version       = self.VERSION or "0",
        online        = true,
        lastSeen      = time(),
        hasMain       = (mainChar ~= nil),
    }

    -- Attach own characters
    if self.db.characters then
        local myChars = {}
        for ck, ch in pairs(self.db.characters) do
            myChars[ck] = {
                name      = ch.name,
                realm     = ch.realm,
                classFile = ch.classFile,
                className = ch.className,
                level     = ch.level,
                itemLevel = ch.itemLevel or 0,
                isMain    = ch.isMain or false,
            }
        end
        selfEntry.characters = myChars
    end

    self.db.addonMembers[myFull] = selfEntry
end

------------------------------------------------------------------------
-- BroadcastCharacters  -- one MSG_CHARINFO per character
------------------------------------------------------------------------
function OneGuild:BroadcastCharacters(startDelay)
    if not self.db or not self.db.characters then return startDelay or 0 end
    local delay = startDelay or 0

    for _, char in pairs(self.db.characters) do
        delay = delay + 0.3
        C_Timer.After(delay, function()
            if not OneGuild:IsAuthorized() then return end
            local p = {
                char.name or "?",
                char.realm or "?",
                char.classFile or "?",
                char.className or "?",
                tostring(char.level or 0),
                tostring(char.itemLevel or 0),
                char.isMain and "1" or "0",
            }
            OneGuild:SendCommMessage(MSG_CHARINFO, table.concat(p, "|"))
        end)
    end
    return delay
end

------------------------------------------------------------------------
-- BroadcastAllRaids  -- one MSG_RAID per raid + signups
------------------------------------------------------------------------
function OneGuild:BroadcastAllRaids(startDelay)
    if not self.db or not self.db.raids then return startDelay or 0 end
    local delay = startDelay or 0

    for idx, rd in ipairs(self.db.raids) do
        delay = delay + 0.4
        C_Timer.After(delay, function()
            if not OneGuild:IsAuthorized() then return end
            OneGuild:SendSingleRaid(rd)
        end)

        -- Send each signup
        if rd.signups then
            for player, signup in pairs(rd.signups) do
                delay = delay + 0.3
                C_Timer.After(delay, function()
                    if not OneGuild:IsAuthorized() then return end
                    OneGuild:SendRaidSignup(rd, player, signup)
                end)
            end
        end
    end
    return delay
end

------------------------------------------------------------------------
-- SendSingleRaid  (used on create and on sync)
------------------------------------------------------------------------
function OneGuild:SendSingleRaid(rd)
    -- Format: title|dateStr|timeStr|description|difficulty|dungeon|author|created|timestamp|lootmeister
    local p = {
        rd.title or "?",
        rd.dateStr or "",
        rd.timeStr or "",
        rd.description or "",
        rd.difficulty or "normal",
        rd.dungeon or "",
        rd.author or "?",
        tostring(rd.created or 0),
        tostring(rd.timestamp or 0),
        rd.lootmeister or "",
    }
    self:SendCommMessage(MSG_RAID, table.concat(p, "|"))
end

------------------------------------------------------------------------
-- SendRaidSignup
------------------------------------------------------------------------
function OneGuild:SendRaidSignup(rd, player, signup)
    -- Format: raidCreated|player|status|role|signedAt
    local p = {
        tostring(rd.created or 0),
        player or "?",
        signup.status or "angemeldet",
        signup.role or "DD",
        tostring(signup.signedAt or 0),
    }
    self:SendCommMessage(MSG_RAIDSIGN, table.concat(p, "|"))
end

------------------------------------------------------------------------
-- BroadcastAllEvents  -- one MSG_EVENT per event + signups
------------------------------------------------------------------------
function OneGuild:BroadcastAllEvents(startDelay)
    if not self.db or not self.db.events then return startDelay or 0 end
    local delay = startDelay or 0

    for idx, ev in ipairs(self.db.events) do
        delay = delay + 0.4
        C_Timer.After(delay, function()
            if not OneGuild:IsAuthorized() then return end
            OneGuild:SendSingleEvent(ev)
        end)

        if ev.signups then
            for player, signup in pairs(ev.signups) do
                delay = delay + 0.3
                C_Timer.After(delay, function()
                    if not OneGuild:IsAuthorized() then return end
                    OneGuild:SendEventSignup(ev, player, signup)
                end)
            end
        end
    end
    return delay
end

------------------------------------------------------------------------
-- SendSingleEvent
------------------------------------------------------------------------
function OneGuild:SendSingleEvent(ev)
    local p = {
        ev.title or "?",
        ev.dateStr or "",
        ev.timeStr or "",
        ev.description or "",
        ev.author or "?",
        tostring(ev.created or 0),
        tostring(ev.timestamp or 0),
    }
    self:SendCommMessage(MSG_EVENT, table.concat(p, "|"))
end

------------------------------------------------------------------------
-- SendEventSignup
------------------------------------------------------------------------
function OneGuild:SendEventSignup(ev, player, signup)
    local p = {
        tostring(ev.created or 0),
        player or "?",
        signup.status or "angemeldet",
        signup.role or "DD",
        tostring(signup.signedAt or 0),
    }
    self:SendCommMessage(MSG_EVTSIGN, table.concat(p, "|"))
end

------------------------------------------------------------------------
-- Handle incoming addon messages
------------------------------------------------------------------------
function OneGuild:HandleAddonMessage(prefix, message, channel, sender)
    if prefix ~= COMM_PREFIX then return end
    -- Accept GUILD, RAID, and PARTY channels (auction msgs use RAID/PARTY)
    if channel ~= "GUILD" and channel ~= "RAID" and channel ~= "PARTY" then return end

    -- Ignore our own messages
    local myName  = UnitName("player")
    local myRealm = GetNormalizedRealmName() or GetRealmName() or ""
    local myFull  = myName .. "-" .. myRealm
    if sender == myFull or sender == myName then return end

    local msgType, data = strsplit(":", message, 2)

    -- Suppress noisy POS debug logs
    if msgType ~= MSG_POS then
        self:Debug("Comm RX von " .. sender .. ": " .. strsub(message, 1, 80))
    end

    if     msgType == MSG_POS      then
        if self.ProcessPosition then self:ProcessPosition(sender, data) end
    elseif msgType == MSG_GOLD     then
        local money = tonumber(data)
        if money and money > 0 and self.db then
            self.db.guildBankMoney = money
            if self.UpdateGoldDisplay then self:UpdateGoldDisplay() end
        end
    elseif msgType == MSG_HELLO    then self:ProcessHello(sender, data)
    elseif msgType == MSG_SYNC     then
        -- Only respond if we are the highest-priority online member (guild leader/officer)
        -- to avoid thundering herd (all members responding at once)
        local _, _, myRankIdx = GetGuildInfo("player")
        if myRankIdx and myRankIdx <= 1 then
            C_Timer.After(math.random() * 5 + 2, function()
                if OneGuild:IsAuthorized() then OneGuild:FullSync() end
            end)
        end
    elseif msgType == MSG_CHARINFO then self:ProcessCharInfo(sender, data)
    elseif msgType == MSG_RAID     then self:ProcessRaid(sender, data)
    elseif msgType == MSG_RAIDSIGN then self:ProcessRaidSignup(sender, data)
    elseif msgType == MSG_EVENT    then self:ProcessEvent(sender, data)
    elseif msgType == MSG_EVTSIGN  then self:ProcessEventSignup(sender, data)
    elseif msgType == MSG_DKP      then self:ProcessDKP(sender, data)
    elseif msgType == MSG_RAIDDEL  then self:ProcessRaidDelete(sender, data)
    elseif msgType == MSG_EVTDEL   then self:ProcessEventDelete(sender, data)
    elseif msgType == MSG_LCHECK   then
        if self.HandleLootCheckRequest then self:HandleLootCheckRequest(sender, data) end
    elseif msgType == MSG_LREPLY   then
        if self.HandleLootCheckResponse then self:HandleLootCheckResponse(sender, data) end
    elseif msgType == MSG_LACTIVATE then
        if self.HandleLootActivate then self:HandleLootActivate(sender, data) end
    elseif msgType == MSG_RGROUPS  then
        -- Raid groups sync (display only, no action needed for now)
    elseif msgType == MSG_GGROUP   then
        self:ProcessGlobalGroups(sender, data)
    elseif msgType == MSG_GLM      then
        self:ProcessGlobalLM(sender, data)
    elseif msgType == MSG_AUCSTART then
        if self.ProcessAuctionStart then self:ProcessAuctionStart(sender, data) end
    elseif msgType == MSG_AUCBID   then
        if self.ProcessAuctionBid then self:ProcessAuctionBid(sender, data) end
    elseif msgType == MSG_AUCEND   then
        if self.ProcessAuctionEnd then self:ProcessAuctionEnd(sender, data) end
    elseif msgType == MSG_AUCCANCEL then
        if self.ProcessAuctionCancel then self:ProcessAuctionCancel(sender, data) end
    elseif msgType == MSG_WLSYNC then
        self:ProcessWhitelistSync(sender, data)
    elseif msgType == MSG_BYE      then
        if self.db and self.db.addonMembers and self.db.addonMembers[sender] then
            self.db.addonMembers[sender].online = false
            self.db.addonMembers[sender].lastSeen = time()
        end
        -- Clear map position when member goes offline
        if self.ClearMemberPosition then self:ClearMemberPosition(sender) end
        if self.RefreshMembers then self:RefreshMembers() end
    end
end

------------------------------------------------------------------------
-- ProcessHello
------------------------------------------------------------------------
function OneGuild:ProcessHello(sender, data)
    if not data or not self.db then return end
    if not self.db.addonMembers then self.db.addonMembers = {} end

    local mainName, mainRealm, mainClassFile, mainLevel, mainClassName, version =
        strsplit("|", data)

    local isNew = (self.db.addonMembers[sender] == nil)

    -- Preserve existing characters when receiving a HELLO update
    local existingChars = nil
    if self.db.addonMembers[sender] then
        existingChars = self.db.addonMembers[sender].characters
    end

    self.db.addonMembers[sender] = {
        sender        = sender,
        mainName      = mainName ~= "?" and mainName or nil,
        mainRealm     = mainRealm ~= "?" and mainRealm or nil,
        mainClass     = mainClassFile ~= "?" and mainClassFile or nil,
        mainLevel     = tonumber(mainLevel) or 0,
        mainClassName = mainClassName ~= "?" and mainClassName or nil,
        version       = version or "?",
        online        = true,
        lastSeen      = time(),
        hasMain       = (mainName ~= nil and mainName ~= "?"),
        characters    = existingChars,
    }

    -- Check if this member has a newer addon version
    if version and version ~= "?" then
        local cmp = self:CompareVersions(version, self.VERSION)
        if cmp > 0 then
            -- Only update if this is newer than any previously seen
            if not self.newerVersion or self:CompareVersions(version, self.newerVersion) > 0 then
                self.newerVersion = version
                self:Print(OneGuild.COLORS.WARNING ..
                    "Neue Addon-Version v" .. version .. " verfuegbar! (du hast v" .. self.VERSION .. ")|r")
                -- Refresh main UI to show update button
                if self.UpdateVersionDisplay then self:UpdateVersionDisplay() end
            end
        end
    end

    if self.RefreshMembers then self:RefreshMembers() end

    if isNew then
        self:Debug(OneGuild.COLORS.SUCCESS ..
            "Neues Addon-Mitglied entdeckt: " .. sender .. "|r")
        -- New member appeared — push our data to them after a random delay
        -- so they receive raids, events, DKP etc. without waiting for next FullSync
        C_Timer.After(math.random() * 4 + 2, function()
            if OneGuild:IsAuthorized() then
                OneGuild:Debug("Sending FullSync for new member: " .. sender)
                OneGuild:FullSync()
            end
        end)
    end
end

------------------------------------------------------------------------
-- ProcessCharInfo
------------------------------------------------------------------------
function OneGuild:ProcessCharInfo(sender, data)
    if not data then return end
    if not self.db or not self.db.addonMembers then return end
    if not self.db.addonMembers[sender] then return end

    local name, realm, classFile, className, level, itemLevel, isMainStr =
        strsplit("|", data)

    local charKey = (name or "?") .. "-" .. (realm or "?")
    if not self.db.addonMembers[sender].characters then
        self.db.addonMembers[sender].characters = {}
    end

    self.db.addonMembers[sender].characters[charKey] = {
        name      = name ~= "?" and name or nil,
        realm     = realm ~= "?" and realm or nil,
        classFile = classFile ~= "?" and classFile or nil,
        className = className ~= "?" and className or nil,
        level     = tonumber(level) or 0,
        itemLevel = tonumber(itemLevel) or 0,
        isMain    = (isMainStr == "1"),
    }
end

------------------------------------------------------------------------
-- ProcessRaid  — merge incoming raid (keyed by created timestamp)
------------------------------------------------------------------------
function OneGuild:ProcessRaid(sender, data)
    if not data or not self.db then return end
    if not self.db.raids then self.db.raids = {} end

    local title, dateStr, timeStr, desc, diff, dungeon, author, createdStr, tsStr, lootmeister =
        strsplit("|", data)

    local created = tonumber(createdStr) or 0
    if created == 0 then return end -- invalid

    -- Check if this raid was deleted (tombstone)
    local delKey = tostring(created) .. ":" .. (author or sender)
    if self.db.deletedRaids and self.db.deletedRaids[delKey] then
        return  -- ignore deleted raid
    end

    -- Check if we already have this raid (by created timestamp + author)
    for _, rd in ipairs(self.db.raids) do
        if rd.created == created and rd.author == author then
            -- Already have it — update mutable fields
            rd.title       = title or rd.title
            rd.dateStr     = dateStr or rd.dateStr
            rd.timeStr     = timeStr or rd.timeStr
            rd.description = desc or rd.description
            rd.difficulty  = diff or rd.difficulty
            rd.dungeon     = (dungeon and dungeon ~= "") and dungeon or rd.dungeon
            rd.timestamp   = tonumber(tsStr) or rd.timestamp
            rd.lootmeister = (lootmeister and lootmeister ~= "") and lootmeister or rd.lootmeister
            if self.RefreshRaid then self:RefreshRaid() end
            return
        end
    end

    -- New raid — insert
    table.insert(self.db.raids, {
        title       = title or "?",
        description = desc or "",
        dateStr     = dateStr or "",
        timeStr     = timeStr or "",
        timestamp   = tonumber(tsStr) or 0,
        difficulty  = diff or "normal",
        dungeon     = (dungeon and dungeon ~= "") and dungeon or nil,
        lootmeister = (lootmeister and lootmeister ~= "") and lootmeister or nil,
        author      = author or sender,
        created     = created,
        signups     = {},
    })

    self:Debug("Comm: Raid empfangen '" .. (title or "?") .. "' von " .. sender)
    if self.RefreshRaid then self:RefreshRaid() end
end

------------------------------------------------------------------------
-- ProcessRaidSignup  — merge signup into the right raid
------------------------------------------------------------------------
function OneGuild:ProcessRaidSignup(sender, data)
    if not data or not self.db or not self.db.raids then return end

    local createdStr, player, status, role, signedAtStr = strsplit("|", data)
    local created = tonumber(createdStr) or 0
    if created == 0 then return end

    for _, rd in ipairs(self.db.raids) do
        if rd.created == created then
            if not rd.signups then rd.signups = {} end
            local existing = rd.signups[player]
            local newSignedAt = tonumber(signedAtStr) or 0
            if not existing or (existing.signedAt or 0) <= newSignedAt then
                if status == "withdrawn" then
                    rd.signups[player] = nil
                else
                    rd.signups[player] = {
                        status   = status or "angemeldet",
                        role     = role or "DD",
                        signedAt = newSignedAt,
                    }
                end
            end
            if self.RefreshRaid then self:RefreshRaid() end
            return
        end
    end
end

------------------------------------------------------------------------
-- ProcessEvent  — merge incoming event (keyed by created + author)
------------------------------------------------------------------------
function OneGuild:ProcessEvent(sender, data)
    if not data or not self.db then return end
    if not self.db.events then self.db.events = {} end

    local title, dateStr, timeStr, desc, author, createdStr, tsStr =
        strsplit("|", data)

    local created = tonumber(createdStr) or 0
    if created == 0 then return end

    -- Check if this event was deleted (tombstone)
    local delKey = tostring(created) .. ":" .. (author or sender)
    if self.db.deletedEvents and self.db.deletedEvents[delKey] then
        return  -- ignore deleted event
    end

    for _, ev in ipairs(self.db.events) do
        if ev.created == created and ev.author == author then
            ev.title       = title or ev.title
            ev.dateStr     = dateStr or ev.dateStr
            ev.timeStr     = timeStr or ev.timeStr
            ev.description = desc or ev.description
            ev.timestamp   = tonumber(tsStr) or ev.timestamp
            if self.RefreshEvents then self:RefreshEvents() end
            return
        end
    end

    table.insert(self.db.events, {
        title       = title or "?",
        description = desc or "",
        dateStr     = dateStr or "",
        timeStr     = timeStr or "",
        timestamp   = tonumber(tsStr) or 0,
        author      = author or sender,
        created     = created,
        signups     = {},
    })

    self:Debug("Comm: Event empfangen '" .. (title or "?") .. "' von " .. sender)
    if self.RefreshEvents then self:RefreshEvents() end
end

------------------------------------------------------------------------
-- ProcessEventSignup
------------------------------------------------------------------------
function OneGuild:ProcessEventSignup(sender, data)
    if not data or not self.db or not self.db.events then return end

    local createdStr, player, status, role, signedAtStr = strsplit("|", data)
    local created = tonumber(createdStr) or 0
    if created == 0 then return end

    for _, ev in ipairs(self.db.events) do
        if ev.created == created then
            if not ev.signups then ev.signups = {} end
            local existing = ev.signups[player]
            local newSignedAt = tonumber(signedAtStr) or 0
            if not existing or (existing.signedAt or 0) <= newSignedAt then
                if status == "withdrawn" then
                    ev.signups[player] = nil
                else
                    ev.signups[player] = {
                        status   = status or "angemeldet",
                        role     = role or "DD",
                        signedAt = newSignedAt,
                    }
                end
            end
            if self.RefreshEvents then self:RefreshEvents() end
            return
        end
    end
end

------------------------------------------------------------------------
-- Get count of known addon members
------------------------------------------------------------------------

------------------------------------------------------------------------
-- BroadcastRaidDelete  -- tell guild a raid was deleted
------------------------------------------------------------------------
function OneGuild:BroadcastRaidDelete(rd)
    if not isCommReady then return end
    local payload = tostring(rd.created or 0) .. "|" .. (rd.author or "?")
    self:SendCommMessage(MSG_RAIDDEL, payload)
end

------------------------------------------------------------------------
-- BroadcastEventDelete  -- tell guild an event was deleted
------------------------------------------------------------------------
function OneGuild:BroadcastEventDelete(ev)
    if not isCommReady then return end
    local payload = tostring(ev.created or 0) .. "|" .. (ev.author or "?")
    self:SendCommMessage(MSG_EVTDEL, payload)
end

------------------------------------------------------------------------
-- ProcessRaidDelete  -- receive raid tombstone from guild
------------------------------------------------------------------------
function OneGuild:ProcessRaidDelete(sender, data)
    if not data or not self.db then return end
    local createdStr, author = strsplit("|", data)
    local created = tonumber(createdStr) or 0
    if created == 0 then return end

    local delKey = tostring(created) .. ":" .. (author or "?")
    if not self.db.deletedRaids then self.db.deletedRaids = {} end
    self.db.deletedRaids[delKey] = true

    -- Remove the raid locally if we have it
    if self.db.raids then
        for i = #self.db.raids, 1, -1 do
            local rd = self.db.raids[i]
            if rd.created == created and rd.author == author then
                local title = rd.title or "?"
                table.remove(self.db.raids, i)
                self:Debug("Comm: Raid '" .. title .. "' remote geloescht von " .. sender)
            end
        end
    end
    if self.RefreshRaid then self:RefreshRaid() end
end

------------------------------------------------------------------------
-- ProcessEventDelete  -- receive event tombstone from guild
------------------------------------------------------------------------
function OneGuild:ProcessEventDelete(sender, data)
    if not data or not self.db then return end
    local createdStr, author = strsplit("|", data)
    local created = tonumber(createdStr) or 0
    if created == 0 then return end

    local delKey = tostring(created) .. ":" .. (author or "?")
    if not self.db.deletedEvents then self.db.deletedEvents = {} end
    self.db.deletedEvents[delKey] = true

    -- Remove the event locally if we have it
    if self.db.events then
        for i = #self.db.events, 1, -1 do
            local ev = self.db.events[i]
            if ev.created == created and ev.author == author then
                local title = ev.title or "?"
                table.remove(self.db.events, i)
                self:Debug("Comm: Event '" .. title .. "' remote geloescht von " .. sender)
            end
        end
    end
    if self.RefreshEvents then self:RefreshEvents() end
end

------------------------------------------------------------------------
-- BroadcastTombstones  -- send all delete tombstones during FullSync
------------------------------------------------------------------------
function OneGuild:BroadcastTombstones(startDelay)
    local delay = startDelay or 0

    if self.db.deletedRaids then
        for delKey, _ in pairs(self.db.deletedRaids) do
            delay = delay + 0.3
            C_Timer.After(delay, function()
                if not OneGuild:IsAuthorized() then return end
                local created, author = strsplit(":", delKey, 2)
                OneGuild:SendCommMessage(MSG_RAIDDEL, (created or "0") .. "|" .. (author or "?"))
            end)
        end
    end

    if self.db.deletedEvents then
        for delKey, _ in pairs(self.db.deletedEvents) do
            delay = delay + 0.3
            C_Timer.After(delay, function()
                if not OneGuild:IsAuthorized() then return end
                local created, author = strsplit(":", delKey, 2)
                OneGuild:SendCommMessage(MSG_EVTDEL, (created or "0") .. "|" .. (author or "?"))
            end)
        end
    end

    return delay
end

------------------------------------------------------------------------
-- CleanOldTombstones  -- remove tombstones older than 7 days
------------------------------------------------------------------------
function OneGuild:CleanOldTombstones()
    local maxAge = 7 * 24 * 60 * 60  -- 7 days in seconds
    local now = time()

    if self.db.deletedRaids then
        local keysToRemove = {}
        for delKey, ts in pairs(self.db.deletedRaids) do
            local deletedAt = tonumber(ts) or 0
            if deletedAt > 0 and (now - deletedAt) > maxAge then
                table.insert(keysToRemove, delKey)
            end
        end
        for _, k in ipairs(keysToRemove) do
            self.db.deletedRaids[k] = nil
        end
    end

    if self.db.deletedEvents then
        local keysToRemove = {}
        for delKey, ts in pairs(self.db.deletedEvents) do
            local deletedAt = tonumber(ts) or 0
            if deletedAt > 0 and (now - deletedAt) > maxAge then
                table.insert(keysToRemove, delKey)
            end
        end
        for _, k in ipairs(keysToRemove) do
            self.db.deletedEvents[k] = nil
        end
    end
end

function OneGuild:GetAddonMemberCount()
    if not self.db or not self.db.addonMembers then return 0 end
    local count = 0
    for _ in pairs(self.db.addonMembers) do count = count + 1 end
    return count
end

------------------------------------------------------------------------
-- SendBye  -- notify guild we are going offline
------------------------------------------------------------------------
function OneGuild:SendBye()
    if not isCommReady then return end
    self:SendCommMessage(MSG_BYE, "bye")
end

------------------------------------------------------------------------
-- MarkStaleOffline  -- mark members as offline if not seen recently
-- Called during FullSync / refresh. Members who haven't been seen
-- within the stale window (180 s) are set offline.
------------------------------------------------------------------------
function OneGuild:MarkStaleOffline()
    if not self.db or not self.db.addonMembers then return end
    local now = time()
    local STALE_SECONDS = 180  -- 3 minutes
    local myName  = UnitName("player") or ""
    local myRealm = GetNormalizedRealmName() or GetRealmName() or ""
    local myFull  = myName .. "-" .. myRealm

    for key, member in pairs(self.db.addonMembers) do
        if key ~= myFull and member.online then
            local lastSeen = member.lastSeen or 0
            if (now - lastSeen) > STALE_SECONDS then
                member.online = false
                self:Debug("Stale-Check: " .. key .. " als offline markiert (" ..
                    tostring(now - lastSeen) .. "s inaktiv)")
            end
        end
    end
end

------------------------------------------------------------------------
-- SendBye  -- notify guild we are going offline
------------------------------------------------------------------------
function OneGuild:SendBye()
    if not isCommReady then return end
    self:SendCommMessage(MSG_BYE, "bye")
end

------------------------------------------------------------------------
-- MarkStaleOffline  -- mark members as offline if not seen recently
-- Called during FullSync / refresh. Members who haven't been seen
-- within the stale window (180 s) are set offline.
------------------------------------------------------------------------
function OneGuild:MarkStaleOffline()
    if not self.db or not self.db.addonMembers then return end
    local now = time()
    local STALE_SECONDS = 180  -- 3 minutes
    local myName  = UnitName("player") or ""
    local myRealm = GetNormalizedRealmName() or GetRealmName() or ""
    local myFull  = myName .. "-" .. myRealm

    for key, member in pairs(self.db.addonMembers) do
        if key ~= myFull and member.online then
            local lastSeen = member.lastSeen or 0
            if (now - lastSeen) > STALE_SECONDS then
                member.online = false
                self:Debug("Stale-Check: " .. key .. " als offline markiert (" ..
                    tostring(now - lastSeen) .. "s inaktiv)")
            end
        end
    end
end

------------------------------------------------------------------------
-- VerifyOnlineViaRoster  -- cross-check addonMembers with guild roster
-- If a member is marked online in addonMembers but is NOT online in
-- the actual WoW guild roster, mark them offline immediately.
------------------------------------------------------------------------
function OneGuild:VerifyOnlineViaRoster()
    if not self.db or not self.db.addonMembers then return end
    if not IsInGuild() then return end

    -- Request fresh roster data
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end

    -- Build set of online guild members
    local numTotal = GetNumGuildMembers() or 0
    local onlineSet = {}
    for i = 1, numTotal do
        local name, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
        if name and isOnline then
            -- name is "Name-Realm"
            onlineSet[name] = true
            -- Also store without realm for cross-realm matching
            local shortName = strsplit("-", name)
            if shortName then
                onlineSet[shortName] = true
            end
        end
    end

    -- Cross-check
    local myName  = UnitName("player") or ""
    local myRealm = GetNormalizedRealmName() or GetRealmName() or ""
    local myFull  = myName .. "-" .. myRealm

    for key, member in pairs(self.db.addonMembers) do
        if key ~= myFull and member.online then
            -- Check if this sender is in the guild roster as online
            local senderName = member.sender or key
            local shortName = strsplit("-", senderName)
            if not onlineSet[senderName] and not onlineSet[shortName or ""] then
                member.online = false
                member.lastSeen = member.lastSeen or time()
                self:Debug("Roster-Check: " .. key .. " ist offline (nicht im Gildenroster)")
            end
        end
    end
end

------------------------------------------------------------------------
-- VerifyOnlineViaRoster  -- cross-check addonMembers with guild roster
-- If a member is marked online in addonMembers but is NOT online in
-- the actual WoW guild roster, mark them offline immediately.
------------------------------------------------------------------------
function OneGuild:VerifyOnlineViaRoster()
    if not self.db or not self.db.addonMembers then return end
    if not IsInGuild() then return end

    -- Request fresh roster data
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end

    -- Build set of online guild members
    local numTotal = GetNumGuildMembers() or 0
    local onlineSet = {}
    for i = 1, numTotal do
        local name, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
        if name and isOnline then
            onlineSet[name] = true
            local shortName = strsplit("-", name)
            if shortName then
                onlineSet[shortName] = true
            end
        end
    end

    -- Cross-check
    local myName  = UnitName("player") or ""
    local myRealm = GetNormalizedRealmName() or GetRealmName() or ""
    local myFull  = myName .. "-" .. myRealm

    for key, member in pairs(self.db.addonMembers) do
        if key ~= myFull and member.online then
            local senderName = member.sender or key
            local shortName = strsplit("-", senderName)
            if not onlineSet[senderName] and not onlineSet[shortName or ""] then
                member.online = false
                member.lastSeen = member.lastSeen or time()
                self:Debug("Roster-Check: " .. key .. " ist offline (nicht im Gildenroster)")
            end
        end
    end
end

------------------------------------------------------------------------
-- Get online addon members (with main set)
-- Merges by mainName-mainRealm to avoid duplicates when char-switching
------------------------------------------------------------------------
function OneGuild:GetOnlineAddonMembers()
    local list = {}
    if not self.db or not self.db.addonMembers then return list end

    local byMain = {}   -- [mainKey] = merged entry
    local order  = {}

    for senderKey, member in pairs(self.db.addonMembers) do
        if member.hasMain then
            local mainKey
            if member.mainName and member.mainRealm then
                mainKey = member.mainName .. "-" .. member.mainRealm
            elseif member.mainName then
                mainKey = member.mainName
            else
                mainKey = senderKey
            end

            local existing = byMain[mainKey]
            if not existing then
                byMain[mainKey] = {
                    sender        = member.sender,
                    mainName      = member.mainName,
                    mainRealm     = member.mainRealm,
                    mainClass     = member.mainClass,
                    mainLevel     = member.mainLevel,
                    mainClassName = member.mainClassName,
                    version       = member.version,
                    online        = member.online,
                    lastSeen      = member.lastSeen,
                    hasMain       = member.hasMain,
                }
                table.insert(order, mainKey)
            else
                -- Use the most recently seen entry's online status
                local memberLast = member.lastSeen or 0
                local existLast  = existing.lastSeen or 0
                if memberLast >= existLast then
                    existing.online   = member.online
                    existing.lastSeen = member.lastSeen
                    existing.sender   = member.sender
                end
                if (member.mainLevel or 0) > (existing.mainLevel or 0) then
                    existing.mainLevel = member.mainLevel
                end
                if member.version and member.version ~= "?" then
                    existing.version = member.version
                end
            end
        end
    end

    for _, mainKey in ipairs(order) do
        table.insert(list, byMain[mainKey])
    end

    table.sort(list, function(a, b)
        if a.online ~= b.online then return a.online end
        return (a.mainName or "") < (b.mainName or "")
    end)
    return list
end

------------------------------------------------------------------------
-- RequestSync  (kept for backward compat with old Roster sync button)
------------------------------------------------------------------------
function OneGuild:RequestSync()
    self:FullSync()
end

------------------------------------------------------------------------
-- BroadcastAllDKP  -- send all DKP entries
------------------------------------------------------------------------
function OneGuild:BroadcastAllDKP(startDelay)
    if not self.db or not self.db.dkp then return startDelay or 0 end
    local delay = startDelay or 0

    for memberKey, dkpVal in pairs(self.db.dkp) do
        delay = delay + 0.3
        C_Timer.After(delay, function()
            if not OneGuild:IsAuthorized() then return end
            OneGuild:SendCommMessage(MSG_DKP, memberKey .. "|" .. tostring(dkpVal))
        end)
    end
    return delay
end

------------------------------------------------------------------------
-- BroadcastWhitelist  -- send full whitelist to guild
------------------------------------------------------------------------
function OneGuild:BroadcastWhitelist(startDelay)
    local delay = startDelay or 0
    if not self.db or not self.db.settings or not self.db.settings.whitelist then return delay end
    local wl = self.db.settings.whitelist
    if #wl == 0 then
        delay = delay + 0.2
        C_Timer.After(delay, function()
            if not OneGuild:IsAuthorized() then return end
            OneGuild:SendCommMessage(MSG_WLSYNC, "")
        end)
    else
        delay = delay + 0.2
        C_Timer.After(delay, function()
            if not OneGuild:IsAuthorized() then return end
            OneGuild:SendCommMessage(MSG_WLSYNC, table.concat(wl, ","))
        end)
    end
    return delay
end

------------------------------------------------------------------------
-- SendWhitelistSync -- send whitelist immediately (called on add/remove)
------------------------------------------------------------------------
function OneGuild:SendWhitelistSync()
    if not self.db or not self.db.settings or not self.db.settings.whitelist then return end
    local wl = self.db.settings.whitelist
    self:SendCommMessage(MSG_WLSYNC, table.concat(wl, ","))
end

------------------------------------------------------------------------
-- ProcessWhitelistSync -- receive whitelist from guild leader / admin
------------------------------------------------------------------------
function OneGuild:ProcessWhitelistSync(sender, data)
    if not self.db or not self.db.settings then return end

    -- Only accept whitelist sync from rank 0 or rank 1
    local senderShort = strsplit("-", sender)
    local trusted = false
    if IsInGuild() then
        local numGuild = GetNumGuildMembers() or 0
        for i = 1, numGuild do
            local gName, _, rankIdx = GetGuildRosterInfo(i)
            if gName then
                local gs = strsplit("-", gName)
                if gs == senderShort or gName == sender then
                    if rankIdx <= 1 then trusted = true end
                    break
                end
            end
        end
    end
    -- Also trust ourselves
    local myName = UnitName("player") or ""
    if senderShort == myName then trusted = true end

    if not trusted then
        self:Debug("Whitelist sync abgelehnt von: " .. sender)
        return
    end

    -- Parse
    local newWL = {}
    if data and data ~= "" then
        for name in data:gmatch("[^,]+") do
            local trimmed = strtrim(name)
            if trimmed ~= "" then
                table.insert(newWL, trimmed)
            end
        end
    end

    self.db.settings.whitelist = newWL
    self:LoadWhitelistFromDB()
    self:Debug("Whitelist aktualisiert von " .. sender .. ": " .. (data or "(leer)"))
end

------------------------------------------------------------------------
-- SendDKPUpdate  -- send a single DKP update immediately
------------------------------------------------------------------------
function OneGuild:SendDKPUpdate(memberKey, dkpVal)
    self:SendCommMessage(MSG_DKP, memberKey .. "|" .. tostring(dkpVal))
    -- Save to officer notes immediately
    if self.SaveDKPToOfficerNote then
        self:SaveDKPToOfficerNote(memberKey, dkpVal)
    end
    -- Request roster refresh so all online members get the officer note change
    self:RequestGuildRoster()
end

------------------------------------------------------------------------
-- ProcessDKP  -- receive DKP data
------------------------------------------------------------------------
function OneGuild:ProcessDKP(sender, data)
    if not data or not self.db then return end
    if not self.db.dkp then self.db.dkp = {} end

    -- Only accept DKP from trusted senders
    local senderShort = strsplit("-", sender)
    local isAdmin = false

    -- 1) Accept from self always
    local myName = UnitName("player") or ""
    if sender == myName or senderShort == myName then isAdmin = true end

    -- 2) Check dynamic whitelist
    if not isAdmin and self:IsOnWhitelist(senderShort) then
        isAdmin = true
    end

    -- 3) Check guild roster: guild leader (rank 0) or officers (rank 1)
    if not isAdmin and IsInGuild() then
        local numGuild = GetNumGuildMembers() or 0
        for i = 1, numGuild do
            local gName, _, rankIdx = GetGuildRosterInfo(i)
            if gName then
                local gs = strsplit("-", gName)
                if gs == senderShort or gName == sender then
                    if rankIdx and rankIdx <= 1 then
                        isAdmin = true
                    end
                    break
                end
            end
        end
    end

    -- 4) Check raid RL or Assist
    if not isAdmin and IsInRaid() then
        local numRaid = GetNumGroupMembers() or 0
        for i = 1, numRaid do
            local name, rank = GetRaidRosterInfo(i)
            if name then
                local ns = strsplit("-", name)
                if ns == senderShort or name == sender then
                    if rank and rank >= 1 then isAdmin = true end
                    break
                end
            end
        end
    end

    if not isAdmin then return end  -- ignore DKP from non-admins

    local memberKey, dkpStr = strsplit("|", data)
    if not memberKey then return end
    local dkpVal = tonumber(dkpStr) or 0

    -- Use centralized setter (stores under ALL known keys)
    self:SetDKPForPlayer(memberKey, dkpVal)

    -- Request fresh roster data to pick up the sender's officer note change
    self:RequestGuildRoster()

    if self.RefreshMembers then self:RefreshMembers() end
end

------------------------------------------------------------------------
-- Global Raid Groups sync
-- Format: "g1name1,g1name2;g2name1,g2name2;...;g8name1,g8name2"
-- Each group separated by ";", names within a group by ","
------------------------------------------------------------------------
function OneGuild:BroadcastGlobalGroups()
    if not self.db then return end
    local groups = self.db.raidGroups or {}
    local parts = {}
    for g = 1, 8 do
        local members = groups[g] or {}
        local slots = {}
        for s = 1, 5 do
            slots[s] = members[s] or "_"
        end
        parts[g] = table.concat(slots, ",")
    end
    self:SendCommMessage(MSG_GGROUP, table.concat(parts, ";"))
end

function OneGuild:ProcessGlobalGroups(sender, data)
    if not data or not self.db then return end
    if not self.db.raidGroups then self.db.raidGroups = {} end

    local groupStrs = { strsplit(";", data) }
    for g = 1, 8 do
        local gStr = groupStrs[g] or ""
        if gStr == "" then
            self.db.raidGroups[g] = {}
        else
            local names = { strsplit(",", gStr) }
            self.db.raidGroups[g] = {}
            for s = 1, 5 do
                local n = names[s]
                if n and n ~= "_" and n ~= "" then
                    self.db.raidGroups[g][s] = n
                else
                    self.db.raidGroups[g][s] = nil
                end
            end
        end
    end

    -- Refresh UI if open
    if self.RefreshRaidGroups then self:RefreshRaidGroups() end
end

------------------------------------------------------------------------
-- Global Lootmeister sync
------------------------------------------------------------------------
function OneGuild:BroadcastGlobalLM()
    if not self.db then return end
    local lm = self.db.lootmeister or ""
    self:SendCommMessage(MSG_GLM, lm)
end

function OneGuild:ProcessGlobalLM(sender, data)
    if not self.db then return end
    if data and data ~= "" then
        self.db.lootmeister = data
    else
        self.db.lootmeister = nil
    end
    -- Refresh UI if open
    if self.RefreshRaidGroups then self:RefreshRaidGroups() end
end
