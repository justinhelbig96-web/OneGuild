------------------------------------------------------------------------
-- OneGuild - Notes.lua
-- MOTD display & guild notes system
------------------------------------------------------------------------
print("|cFFFFB800[OneGuild]|r Notes.lua wird geladen...")

local _, OneGuild = ...

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local NOTE_ROW_HEIGHT = 44
local MAX_NOTE_ROWS   = 10

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local noteRows = {}

------------------------------------------------------------------------
-- Build Notes Tab
------------------------------------------------------------------------
function OneGuild:BuildNotesTab()
    local parent = self.tabFrames[4]
    if not parent then return end

    -- MOTD Section
    local motdHeader = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    motdHeader:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -10)
    motdHeader:SetText(OneGuild.COLORS.GUILD .. "Nachricht des Tages (MOTD)|r")

    -- MOTD display box
    local motdBg = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    motdBg:SetHeight(50)
    motdBg:SetPoint("TOPLEFT", motdHeader, "BOTTOMLEFT", 0, -4)
    motdBg:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, 0)
    motdBg:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    motdBg:SetBackdropColor(0.05, 0.1, 0.05, 0.8)
    motdBg:SetBackdropBorderColor(0.2, 0.5, 0.2, 0.5)

    local motdText = motdBg:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    motdText:SetPoint("TOPLEFT", motdBg, "TOPLEFT", 8, -8)
    motdText:SetPoint("BOTTOMRIGHT", motdBg, "BOTTOMRIGHT", -8, 8)
    motdText:SetJustifyH("LEFT")
    motdText:SetJustifyV("TOP")
    motdText:SetWordWrap(true)
    motdText:SetText(OneGuild.COLORS.MUTED .. "Lade MOTD...|r")
    parent.motdText = motdText

    -- Separator
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(0.3, 0.3, 0.4, 0.3)
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", motdBg, "BOTTOMLEFT", 0, -10)
    sep:SetPoint("TOPRIGHT", motdBg, "BOTTOMRIGHT", 0, -10)

    -- Notes Section Header
    local notesHeader = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    notesHeader:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 0, -8)
    notesHeader:SetText(OneGuild.COLORS.INFO .. "Gilden-Notizen|r")

    -- Add Note button
    local addBtn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    addBtn:SetSize(110, 22)
    addBtn:SetPoint("LEFT", notesHeader, "RIGHT", 12, 0)
    addBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    addBtn:SetBackdropColor(0, 0.3, 0.5, 0.7)
    addBtn:SetBackdropBorderColor(0, 0.6, 0.8, 0.5)
    local addBtnText = addBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addBtnText:SetPoint("CENTER")
    addBtnText:SetText("|cFF88DDFF+ Notiz|r")
    addBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0, 0.5, 0.7, 0.9)
    end)
    addBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0, 0.3, 0.5, 0.7)
    end)
    addBtn:SetScript("OnClick", function()
        OneGuild:ShowAddNoteDialog()
    end)

    -- Note count
    local noteCount = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noteCount:SetPoint("LEFT", addBtn, "RIGHT", 10, 0)
    noteCount:SetTextColor(0.5, 0.5, 0.5)
    parent.noteCountText = noteCount

    -- Notes list container
    local notesList = CreateFrame("Frame", nil, parent)
    notesList:SetPoint("TOPLEFT", notesHeader, "BOTTOMLEFT", 0, -6)
    notesList:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -12, 8)

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, notesList, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", notesList, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", notesList, "BOTTOMRIGHT", -20, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth() or 500)
    scrollChild:SetHeight(1)  -- will grow dynamically
    scrollFrame:SetScrollChild(scrollChild)
    parent.scrollChild = scrollChild
    parent.scrollFrame = scrollFrame

    -- Pre-create note rows
    for i = 1, MAX_NOTE_ROWS do
        local row = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
        row:SetHeight(NOTE_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -((i - 1) * (NOTE_ROW_HEIGHT + 4)))
        row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -((i - 1) * (NOTE_ROW_HEIGHT + 4)))
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        row:SetBackdropColor(0.06, 0.06, 0.1, 0.7)
        row:SetBackdropBorderColor(0.25, 0.25, 0.3, 0.4)

        -- Author & timestamp
        row.metaText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.metaText:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -4)
        row.metaText:SetTextColor(0.5, 0.7, 0.9)

        -- Note text
        row.noteText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.noteText:SetPoint("TOPLEFT", row.metaText, "BOTTOMLEFT", 0, -2)
        row.noteText:SetPoint("RIGHT", row, "RIGHT", -30, 0)
        row.noteText:SetJustifyH("LEFT")
        row.noteText:SetWordWrap(true)

        -- Delete button
        row.deleteBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
        row.deleteBtn:SetSize(14, 14)
        row.deleteBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -4)
        row.deleteBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
        })
        row.deleteBtn:SetBackdropColor(0.4, 0, 0, 0.5)
        local delT = row.deleteBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        delT:SetPoint("CENTER")
        delT:SetText("|cFFFF6666x|r")
        row.deleteBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.7, 0, 0, 0.8)
        end)
        row.deleteBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.4, 0, 0, 0.5)
        end)

        row:Hide()
        noteRows[i] = row
    end

    parent.emptyNotesText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    parent.emptyNotesText:SetPoint("CENTER", notesList, "CENTER", 0, 0)
    parent.emptyNotesText:SetText(OneGuild.COLORS.MUTED .. "Keine Notizen vorhanden.|r")
    parent.emptyNotesText:Hide()
end

------------------------------------------------------------------------
-- Update MOTD display
------------------------------------------------------------------------
function OneGuild:UpdateMOTDDisplay()
    local parent = self.tabFrames[4]
    if not parent or not parent.motdText then return end

    local motd = GetGuildRosterMOTD and GetGuildRosterMOTD() or ""
    if motd and motd ~= "" then
        parent.motdText:SetText("|cFFFFFFFF" .. motd .. "|r")
    else
        parent.motdText:SetText(OneGuild.COLORS.MUTED .. "Kein MOTD gesetzt.|r")
    end
end

------------------------------------------------------------------------
-- Refresh notes list
------------------------------------------------------------------------
function OneGuild:RefreshNotes()
    if not self.db then return end

    -- Update MOTD
    self:UpdateMOTDDisplay()

    local notes = self.db.notes or {}
    local parent = self.tabFrames[4]

    -- Update count
    if parent and parent.noteCountText then
        parent.noteCountText:SetText(OneGuild.COLORS.MUTED ..
            "(" .. #notes .. " Notizen)|r")
    end

    -- Sort newest first
    local sorted = {}
    for i, n in ipairs(notes) do
        table.insert(sorted, { index = i, data = n })
    end
    table.sort(sorted, function(a, b)
        return (a.data.timestamp or 0) > (b.data.timestamp or 0)
    end)

    -- Update rows
    for i = 1, MAX_NOTE_ROWS do
        local row = noteRows[i]
        if i <= #sorted then
            local note = sorted[i]

            row.metaText:SetText(
                OneGuild.COLORS.INFO .. (note.data.author or "?") .. "|r" ..
                OneGuild.COLORS.MUTED .. "  •  " ..
                self:FormatTime(note.data.timestamp or 0) .. "|r"
            )

            row.noteText:SetText(note.data.text or "")

            local noteIdx = note.index
            row.deleteBtn:SetScript("OnClick", function()
                OneGuild:DeleteNote(noteIdx)
            end)

            row:Show()
        else
            row:Hide()
        end
    end

    -- Scroll child height
    if parent and parent.scrollChild then
        local count = math.min(#sorted, MAX_NOTE_ROWS)
        parent.scrollChild:SetHeight(count * (NOTE_ROW_HEIGHT + 4) + 10)
    end

    -- Empty state
    if parent and parent.emptyNotesText then
        if #notes == 0 then
            parent.emptyNotesText:Show()
        else
            parent.emptyNotesText:Hide()
        end
    end
end

------------------------------------------------------------------------
-- Delete a note
------------------------------------------------------------------------
function OneGuild:DeleteNote(index)
    if not self.db or not self.db.notes[index] then return end
    table.remove(self.db.notes, index)
    self:Print("Notiz gelöscht.")
    self:RefreshNotes()
end

------------------------------------------------------------------------
-- Add Note Dialog
------------------------------------------------------------------------
function OneGuild:ShowAddNoteDialog()
    if self.addNoteFrame and self.addNoteFrame:IsShown() then
        self.addNoteFrame:Hide()
        return
    end

    if not self.addNoteFrame then
        local f = CreateFrame("Frame", "OneGuildAddNote", UIParent, "BackdropTemplate")
        f:SetSize(360, 180)
        f:SetPoint("CENTER")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:SetFrameStrata("DIALOG")
        f:SetFrameLevel(200)
        f:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14,
            insets   = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0.08, 0.08, 0.12, 0.98)
        f:SetBackdropBorderColor(0, 0.6, 0.8, 0.7)

        -- Drag
        local dragArea = CreateFrame("Frame", nil, f)
        dragArea:SetHeight(30)
        dragArea:SetPoint("TOPLEFT")
        dragArea:SetPoint("TOPRIGHT")
        dragArea:EnableMouse(true)
        dragArea:RegisterForDrag("LeftButton")
        dragArea:SetScript("OnDragStart", function() f:StartMoving() end)
        dragArea:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 14, -10)
        title:SetText(OneGuild.COLORS.INFO .. "Neue Notiz|r")

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -2, -2)

        -- Text input
        local scrollArea = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        scrollArea:SetSize(320, 80)
        scrollArea:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -40)

        local textBox = CreateFrame("EditBox", nil, scrollArea)
        textBox:SetMultiLine(true)
        textBox:SetFontObject("ChatFontNormal")
        textBox:SetWidth(300)
        textBox:SetAutoFocus(false)
        textBox:SetMaxLetters(500)
        scrollArea:SetScrollChild(textBox)
        f.textBox = textBox

        -- Save button
        local saveBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        saveBtn:SetSize(100, 26)
        saveBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
        saveBtn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        saveBtn:SetBackdropColor(0, 0.4, 0.6, 0.9)
        saveBtn:SetBackdropBorderColor(0, 0.7, 1, 0.7)
        local saveBtnText = saveBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        saveBtnText:SetPoint("CENTER")
        saveBtnText:SetText("|cFFFFFFFFSpeichern|r")
        saveBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0, 0.6, 0.8, 1)
        end)
        saveBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0, 0.4, 0.6, 0.9)
        end)
        saveBtn:SetScript("OnClick", function()
            OneGuild:SaveNoteFromDialog()
        end)

        f:Hide()
        self.addNoteFrame = f
        table.insert(UISpecialFrames, "OneGuildAddNote")
    end

    self.addNoteFrame.textBox:SetText("")
    self.addNoteFrame:Show()
    self.addNoteFrame.textBox:SetFocus()
end

------------------------------------------------------------------------
-- Save note
------------------------------------------------------------------------
function OneGuild:SaveNoteFromDialog()
    local f = self.addNoteFrame
    if not f then return end

    local text = strtrim(f.textBox:GetText() or "")
    if text == "" then
        self:PrintError("Bitte gib einen Text ein!")
        return
    end

    table.insert(self.db.notes, {
        author    = self:GetPlayerName(),
        text      = text,
        timestamp = time(),
    })

    self:PrintSuccess("Notiz gespeichert!")
    f:Hide()
    self:RefreshNotes()
end
