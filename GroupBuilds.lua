GroupBuilds = {}

GroupBuilds.name = 'GroupBuilds'
GroupBuilds.builds = {}
GroupBuilds.rowControls = {}

local PROTOCOL_ID = 200
local PROTOCOL_NAME = 'GroupBuildsData'
local RESYNC_EVENT_ID = 20
local RESYNC_EVENT_NAME = 'GroupBuildsResync'

local ROW_HEIGHT = 26
local HEADER_TITLE = 36
local HEADER_SHARE = 34
local BOTTOM_PADDING = 8
local MIN_WIDTH = 200
local MAX_WIDTH = 420
local NAME_LEFT_ROLE = 30
local NAME_LEFT_CLASS = 54
local WIDTH_PADDING = 28
local SEND_DEBOUNCE = 400

local ROLE_ORDER = {
    [LFG_ROLE_TANK] = 1,
    [LFG_ROLE_HEAL] = 2,
    [LFG_ROLE_DPS] = 3,
}

local ROLE_ICON = {
    [LFG_ROLE_TANK] = '/esoui/art/lfg/lfg_icon_tank.dds',
    [LFG_ROLE_HEAL] = '/esoui/art/lfg/lfg_icon_healer.dds',
    [LFG_ROLE_DPS] = '/esoui/art/lfg/lfg_icon_dps.dds',
}

local ROLE_NAME = {
    [LFG_ROLE_TANK] = 'Tank',
    [LFG_ROLE_HEAL] = 'Healer',
    [LFG_ROLE_DPS] = 'DPS',
}

local EM = GetEventManager()
local LGB = LibGroupBroadcast

local protocol
local fireResync

function GroupBuilds:GetRoleOrder(role)
    return ROLE_ORDER[role] or 4
end

function GroupBuilds:FormatName(tag)
    local name = GetUnitName(tag)
    local account = GetUnitDisplayName(tag)
    local format = self.sv.groupWindow.nameFormat

    if format == 'account' then
        return account
    elseif format == 'name_account' then
        return string.format('%s (%s)', name, account)
    elseif format == 'account_name' then
        return string.format('%s (%s)', account, name)
    end

    return name
end

function GroupBuilds:RoleIcon(role)
    return ROLE_ICON[role] or ROLE_ICON[LFG_ROLE_DPS]
end

function GroupBuilds:RoleName(role)
    return ROLE_NAME[role] or ''
end

function GroupBuilds:ClassName(classId)
    if not classId or classId == 0 then
        return ''
    end

    return zo_strformat('<<1>>', GetClassName(GENDER_MALE, classId))
end

function GroupBuilds:Schedule(key, delay, callback)
    EM:UnregisterForUpdate(key)
    EM:RegisterForUpdate(key, delay, function()
        EM:UnregisterForUpdate(key)
        callback()
    end)
end

function GroupBuilds:GetMyPayload()
    if not SuperStar or not SuperStar.fetchShareLink then
        return nil
    end

    local link = SuperStar:fetchShareLink()
    if not link then
        return nil
    end

    return link:match(':sss:(.-)|h')
end

function GroupBuilds:SendMyBuild(force)
    if not self:IsSharing() then
        return
    end

    if not IsUnitGrouped('player') then
        return
    end

    local payload = self:GetMyPayload()
    if not payload then
        return
    end

    if not force and payload == self.lastSentPayload then
        return
    end

    self.lastSentPayload = payload
    protocol:Send({ build = payload })
end

function GroupBuilds:ClearMyBuild()
    if not IsUnitGrouped('player') then
        return
    end

    self.lastSentPayload = nil
    protocol:Send({ build = '' })
end

function GroupBuilds:QueueSendMyBuild(force)
    self:Schedule('GroupBuilds_Send', SEND_DEBOUNCE, function()
        self:SendMyBuild(force)
    end)
end

function GroupBuilds:QueueResyncResponse()
    local delay = 500 + zo_floor(zo_random() * 3000)
    self:Schedule('GroupBuilds_ResyncResponse', delay, function()
        self:SendMyBuild(true)
    end)
end

function GroupBuilds:RequestResync()
    if not IsUnitGrouped('player') then
        return
    end

    if fireResync then
        fireResync()
    end
end

function GroupBuilds:StartRefreshTimer()
    EM:UnregisterForUpdate('GroupBuilds_Refresh')

    local interval = self.sv.sharing.refreshInterval
    if not interval or interval <= 0 then
        return
    end

    EM:RegisterForUpdate('GroupBuilds_Refresh', interval * 1000, function()
        if IsUnitInCombat('player') then
            return
        end
        self:SendMyBuild(false)
    end)
end

function GroupBuilds:OnBuildReceived(unitTag, data)
    local displayName = GetUnitDisplayName(unitTag)
    if not displayName or displayName == '' then
        return
    end

    if data.build == '' then
        self.builds[displayName] = nil
    else
        self.builds[displayName] = data.build
    end
    self:RefreshList()
end

function GroupBuilds:MakeRow(tag, payload)
    return {
        name = self:FormatName(tag),
        role = GetGroupMemberSelectedRole(tag),
        class = GetUnitClassId(tag),
        payload = payload,
    }
end

function GroupBuilds:RefreshList()
    self:RefreshToggle()

    local rows = {}

    if IsUnitGrouped('player') then
        if self:IsSharing() then
            local payload = self:GetMyPayload()
            if payload then
                table.insert(rows, self:MakeRow('player', payload))
            end
        end

        for i = 1, GetGroupSize() do
            local tag = GetGroupUnitTagByIndex(i)
            if not AreUnitsEqual('player', tag) then
                local payload = self.builds[GetUnitDisplayName(tag)]
                if payload then
                    table.insert(rows, self:MakeRow(tag, payload))
                end
            end
        end
    end

    table.sort(rows, function(a, b)
        local ra = self:GetRoleOrder(a.role)
        local rb = self:GetRoleOrder(b.role)
        if ra ~= rb then
            return ra < rb
        end
        return a.name < b.name
    end)

    self:RenderRows(rows)
    self:UpdateVisibility()
end

function GroupBuilds:RenderRows(rows)
    local container = GroupBuildsWindowRows

    if not self.measureLabel then
        self.measureLabel = WINDOW_MANAGER:CreateControl(nil, GroupBuildsWindow, CT_LABEL)
        self.measureLabel:SetFont('ZoFontGame')
        self.measureLabel:SetHidden(true)
    end

    local contentWidth = 0
    local showClass = self.sv.groupWindow.showClassIcon
    local nameLeft = showClass and NAME_LEFT_CLASS or NAME_LEFT_ROLE

    for i, row in ipairs(rows) do
        local rowControl = self.rowControls[i]
        if not rowControl then
            rowControl = CreateControlFromVirtual('GroupBuildsRow', container, 'GroupBuildsRow', i)
            rowControl:SetAnchor(TOPLEFT, container, TOPLEFT, 0, (i - 1) * ROW_HEIGHT)
            rowControl:SetAnchor(TOPRIGHT, container, TOPRIGHT, 0, (i - 1) * ROW_HEIGHT)
            self.rowControls[i] = rowControl
        end

        rowControl.payload = row.payload
        rowControl.ownerName = row.name
        rowControl.saveClass = row.class
        rowControl.saveRole = row.role

        rowControl:GetNamedChild('_Role'):SetTexture(self:RoleIcon(row.role))

        local classControl = rowControl:GetNamedChild('_Class')
        classControl:SetHidden(not showClass)
        if showClass then
            classControl:SetTexture(GetClassIcon(row.class) or '')
        end

        local nameControl = rowControl:GetNamedChild('_Name')
        nameControl:ClearAnchors()
        if showClass then
            nameControl:SetAnchor(LEFT, classControl, RIGHT, 6, 0)
        else
            nameControl:SetAnchor(LEFT, rowControl:GetNamedChild('_Role'), RIGHT, 6, 0)
        end
        nameControl:SetAnchor(RIGHT, rowControl, RIGHT, -4, 0)
        nameControl:SetText(row.name)

        rowControl:SetHidden(false)

        self.measureLabel:SetText(row.name)
        local nameWidth = self.measureLabel:GetTextWidth()
        if nameWidth > contentWidth then
            contentWidth = nameWidth
        end
    end

    for i = #rows + 1, #self.rowControls do
        self.rowControls[i]:SetHidden(true)
    end

    GroupBuildsWindowTitle:SetText(string.format('Group Builds (%d)', #rows))
    GroupBuildsWindow:SetHeight((self.headerHeight or HEADER_TITLE) + (#rows * ROW_HEIGHT) + BOTTOM_PADDING)
    GroupBuildsWindow:SetWidth(zo_clamp(contentWidth + nameLeft + WIDTH_PADDING, MIN_WIDTH, MAX_WIDTH))
end

function GroupBuilds:OpenBuild(payload)
    if not payload or payload == '' then
        return
    end

    local link = ZO_LinkHandler_CreateLink('SuperStar', nil, 'sss', payload)
    ZO_LinkHandler_OnLinkClicked(link, MOUSE_BUTTON_INDEX_LEFT)
end

function GroupBuilds:ShareToChat(payload)
    if not payload or payload == '' then
        return
    end

    local link = ZO_LinkHandler_CreateLink('SuperStar', nil, 'sss', payload)
    CHAT_SYSTEM.textEntry:InsertLink(link)
end

function GroupBuilds:OnRowMouse(rowControl, entered)
    rowControl:GetNamedChild('_Highlight'):SetHidden(not entered)
end

function GroupBuilds:OnRowClicked(rowControl, button, upInside)
    if not upInside then
        return
    end

    if button == MOUSE_BUTTON_INDEX_LEFT then
        self.displayed = {
            payload = rowControl.payload,
            class = rowControl.saveClass,
            role = rowControl.saveRole,
            name = rowControl.ownerName,
        }
        self:OpenBuild(rowControl.payload)
    elseif button == MOUSE_BUTTON_INDEX_RIGHT then
        ClearMenu()
        AddMenuItem('Save build', function()
            self:SaveBuild(rowControl)
        end)
        ShowMenu(rowControl)
    end
end

function GroupBuilds:StoreBuild(payload, name, class, role)
    if not payload or payload == '' then
        return
    end

    if name == '' then
        name = nil
    end

    self.savedCounter = self.savedCounter + 1
    local id = GetTimeStamp() .. '-' .. self.savedCounter

    self.sv.saved[id] = {
        payload = payload,
        name = name,
        class = class,
        role = role,
        note = '',
        timestamp = GetTimeStamp(),
    }

    self.browser:RefreshData()
end

function GroupBuilds:OpenSaveDialog(payload, role, class, suggestedName)
    if not payload or payload == '' then
        return
    end

    self.pendingSave = { payload = payload, suggestedName = suggestedName }
    GroupBuildsRolePickerNameBox:SetText('')
    GroupBuildsRolePickerNameInsert:SetHidden(not suggestedName)
    self:SelectRole(role)
    self:SelectClass(class)
    self:SetClassLocked(class ~= nil)
    GroupBuildsRolePicker:SetHidden(false)
end

function GroupBuilds:SetClassLocked(locked)
    for classId, button in pairs(self.classButtons) do
        button:SetMouseEnabled(not locked)
        if locked then
            button:SetAlpha(classId == self.pickClass and 0.5 or 0.1)
        end
    end
end

function GroupBuilds:InsertSuggestedName()
    if self.pendingSave and self.pendingSave.suggestedName then
        GroupBuildsRolePickerNameBox:SetText(self.pendingSave.suggestedName)
    end
end

function GroupBuilds:SaveBuild(rowControl)
    self:OpenSaveDialog(rowControl.payload, rowControl.saveRole, rowControl.saveClass, rowControl.ownerName)
end

function GroupBuilds:SaveDisplayedPrompt()
    local src = self.displayed
    if src then
        self:OpenSaveDialog(src.payload, src.role, src.class, src.name)
    else
        self:OpenSaveDialog(self:GetMyPayload(), GetSelectedLFGRole(), GetUnitClassId('player'), self:FormatName('player'))
    end
end

function GroupBuilds:SelectRole(role)
    self.pickRole = role
    for r, button in pairs(self.roleButtons) do
        button:SetAlpha(r == role and 1 or 0.3)
    end
    self:UpdateSaveButton()
end

function GroupBuilds:SelectClass(classId)
    self.pickClass = classId
    for c, button in pairs(self.classButtons) do
        button:SetAlpha(c == classId and 1 or 0.3)
    end
    self:UpdateSaveButton()
end

function GroupBuilds:UpdateSaveButton()
    GroupBuildsRolePickerSave:SetEnabled(self.pickRole ~= nil and self.pickClass ~= nil)
end

function GroupBuilds:ConfirmSave()
    if not self.pickRole or not self.pickClass then
        return
    end

    local p = self.pendingSave
    if p then
        self:StoreBuild(p.payload, GroupBuildsRolePickerNameBox:GetText(), self.pickClass, self.pickRole)
        self.pendingSave = nil
    end

    GroupBuildsRolePicker:SetHidden(true)
end

function GroupBuilds:CancelSave()
    self.pendingSave = nil
    GroupBuildsRolePicker:SetHidden(true)
end

function GroupBuilds:DeleteSaved(id)
    self.sv.saved[id] = nil
    self.browser:RefreshData()
end

function GroupBuilds:SetNote(id, note)
    local entry = self.sv.saved[id]
    if not entry then
        return
    end

    entry.note = note or ''
    self.browser:RefreshData()
end

function GroupBuilds:SetBuildName(id, name)
    local entry = self.sv.saved[id]
    if not entry then
        return
    end

    if name == '' then
        name = nil
    end

    entry.name = name
    self.browser:RefreshData()
end

function GroupBuilds:ToggleBrowser()
    self.browserOpen = not self.browserOpen
    if self.browserOpen then
        self.browser:RefreshData()
    end
    self:UpdateBrowserVisibility()
end

function GroupBuilds:UpdateBrowserVisibility()
    GroupBuildsBrowser:SetHidden(not (self.browserOpen and self:IsOnHud()))
end

function GroupBuilds:OnBrowserMoved()
    self.sv.savedWindowRect.left = GroupBuildsBrowser:GetLeft()
    self.sv.savedWindowRect.top = GroupBuildsBrowser:GetTop()
end

function GroupBuilds:OnBrowserResized()
    self.sv.savedWindowRect.left = GroupBuildsBrowser:GetLeft()
    self.sv.savedWindowRect.top = GroupBuildsBrowser:GetTop()
    self.sv.savedWindowRect.width = GroupBuildsBrowser:GetWidth()
    self.sv.savedWindowRect.height = GroupBuildsBrowser:GetHeight()

    self.browser:RefreshData()
end

function GroupBuilds:RestoreBrowserState()
    GroupBuildsBrowser:SetDimensionConstraints(560, 320, 0, 0)

    if self.sv.savedWindowRect.width and self.sv.savedWindowRect.height then
        GroupBuildsBrowser:SetDimensions(self.sv.savedWindowRect.width, self.sv.savedWindowRect.height)
    end

    if self.sv.savedWindowRect.left and self.sv.savedWindowRect.top then
        GroupBuildsBrowser:ClearAnchors()
        GroupBuildsBrowser:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, self.sv.savedWindowRect.left, self.sv.savedWindowRect.top)
    end
end

function GroupBuilds:OnBrowserRowMouse(rowControl, entered)
    if entered then
        self.browser:Row_OnMouseEnter(rowControl)
    else
        self.browser:Row_OnMouseExit(rowControl)
    end
end

function GroupBuilds:OnNoteEnter(noteControl)
    if not noteControl.noteText or noteControl.noteText == '' then
        return
    end

    InitializeTooltip(InformationTooltip, noteControl, RIGHT, -5, 0, LEFT)
    SetTooltipText(InformationTooltip, noteControl.noteText)
end

function GroupBuilds:OnNoteExit(noteControl)
    ClearTooltip(InformationTooltip)
end

function GroupBuilds:OnBrowserRowClicked(rowControl, button, upInside)
    if not upInside then
        return
    end

    local data = rowControl.data
    if not data then
        return
    end

    if button == MOUSE_BUTTON_INDEX_LEFT then
        self.displayed = {
            payload = data.payload,
            class = data.class,
            role = data.role,
            name = data.name,
        }
        self:OpenBuild(data.payload)
    elseif button == MOUSE_BUTTON_INDEX_RIGHT then
        ClearMenu()
        AddMenuItem('Open', function()
            self:OpenBuild(data.payload)
        end)
        AddMenuItem('Share to chat', function()
            self:ShareToChat(data.payload)
        end)
        AddMenuItem('Edit name', function()
            ZO_Dialogs_ShowDialog('GROUP_BUILDS_EDIT_NAME', { id = data.id }, { initialEditText = data.name })
        end)
        AddMenuItem('Edit note', function()
            ZO_Dialogs_ShowDialog('GROUP_BUILDS_RENAME', { id = data.id }, { initialEditText = data.note })
        end)
        AddMenuItem('Delete', function()
            ZO_Dialogs_ShowDialog('GROUP_BUILDS_DELETE', { id = data.id })
        end)
        ShowMenu(rowControl)
    end
end

function GroupBuilds:IsSharing()
    return self.sv.sharing.alwaysShare or self.sharing
end

function GroupBuilds:RefreshToggle()
    local shareButton = GroupBuildsWindowShare
    local headerHeight

    if self.sv.sharing.alwaysShare or not IsUnitGrouped('player') then
        shareButton:SetHidden(true)
        headerHeight = HEADER_TITLE
    else
        shareButton:SetHidden(false)
        if self.sharing then
            shareButton:SetText('Sharing: ON')
        else
            shareButton:SetText('Sharing: OFF')
        end
        headerHeight = HEADER_TITLE + HEADER_SHARE
    end

    self.headerHeight = headerHeight

    local container = GroupBuildsWindowRows
    container:ClearAnchors()
    container:SetAnchor(TOPLEFT, GroupBuildsWindow, TOPLEFT, 8, headerHeight)
    container:SetAnchor(TOPRIGHT, GroupBuildsWindow, TOPRIGHT, -8, headerHeight)
end

function GroupBuilds:OnShareToggled()
    self.sharing = not self.sharing
    self:RefreshList()
    if self.sharing then
        self:QueueSendMyBuild(true)
    else
        self:ClearMyBuild()
    end
end

function GroupBuilds:OpenSettings()
    LibAddonMenu2:OpenToPanel(GroupBuildsSettings.panel)
end

function GroupBuilds:UpdateGroupState()
    local grouped = IsUnitGrouped('player')
    if grouped and not self.wasGrouped then
        self.sharing = false
        self:RefreshToggle()
        if self:IsSharing() then
            self:QueueSendMyBuild(true)
        end
    elseif not grouped and self.wasGrouped then
        self.builds = {}
        self.sharing = false
        self:RefreshToggle()
    end
    self.wasGrouped = grouped
end

function GroupBuilds:IsOnHud()
    local hud = HUD_SCENE:GetState()
    local hudui = HUD_UI_SCENE:GetState()
    return hud == SCENE_SHOWN or hud == SCENE_SHOWING or hudui == SCENE_SHOWN or hudui == SCENE_SHOWING
end

function GroupBuilds:UpdateVisibility()
    local show = self.sv.groupWindow.shown and self:IsOnHud() and (IsUnitGrouped('player') or self.sv.groupWindow.showSolo)
    GroupBuildsWindow:SetHidden(not show)
end

function GroupBuilds:ApplyWindowStyle()
    GroupBuildsWindowBG:SetAlpha(self.sv.groupWindow.bgOpacity)

    local hidden = not self.sv.groupWindow.showBorder
    GroupBuildsWindowBorderTop:SetHidden(hidden)
    GroupBuildsWindowBorderBottom:SetHidden(hidden)
    GroupBuildsWindowBorderLeft:SetHidden(hidden)
    GroupBuildsWindowBorderRight:SetHidden(hidden)
end

function GroupBuilds:Toggle()
    self.sv.groupWindow.shown = not self.sv.groupWindow.shown
    self:UpdateVisibility()
end

function GroupBuilds:OnWindowMoved()
    self.sv.groupWindowPosition.left = GroupBuildsWindow:GetLeft()
    self.sv.groupWindowPosition.top = GroupBuildsWindow:GetTop()
end

function GroupBuilds:RestorePosition()
    if self.sv.groupWindowPosition.left and self.sv.groupWindowPosition.top then
        GroupBuildsWindow:ClearAnchors()
        GroupBuildsWindow:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, self.sv.groupWindowPosition.left, self.sv.groupWindowPosition.top)
    end
end

function GroupBuilds:RegisterProtocol()
    local handler = LGB:RegisterHandler(self.name)
    handler:SetDisplayName('Group Builds')
    handler:SetDescription('Shares SuperStar builds between group members')

    protocol = handler:DeclareProtocol(PROTOCOL_ID, PROTOCOL_NAME)
    protocol:AddField(LGB.CreateStringField('build', { maxLength = 400 }))
    protocol:OnData(function(unitTag, data)
        self:OnBuildReceived(unitTag, data)
    end)
    protocol:Finalize({ isRelevantInCombat = false })

    fireResync = handler:DeclareCustomEvent(RESYNC_EVENT_ID, RESYNC_EVENT_NAME, { isRelevantInCombat = false })
    LGB:RegisterForCustomEvent(RESYNC_EVENT_NAME, function()
        self:QueueResyncResponse()
    end)
end

function GroupBuilds:RegisterEvents()
    EM:RegisterForEvent(self.name, EVENT_PLAYER_ACTIVATED, function()
        self:UpdateGroupState()
        self:RefreshList()
        self:RequestResync()
    end)

    EM:RegisterForEvent(self.name, EVENT_GROUP_MEMBER_JOINED, function()
        self:QueueSendMyBuild(true)
    end)

    EM:RegisterForEvent(self.name, EVENT_GROUP_UPDATE, function()
        self:UpdateGroupState()
        self:RefreshList()
    end)

    EM:RegisterForEvent(self.name, EVENT_GROUP_MEMBER_LEFT, function()
        self:RefreshList()
    end)

    EM:RegisterForEvent(self.name, EVENT_GROUP_MEMBER_ROLE_CHANGED, function()
        self:RefreshList()
    end)

    EM:RegisterForEvent(self.name, EVENT_INVENTORY_SINGLE_SLOT_UPDATE, function()
        self:QueueSendMyBuild(false)
    end)
    EM:AddFilterForEvent(self.name, EVENT_INVENTORY_SINGLE_SLOT_UPDATE, REGISTER_FILTER_BAG_ID, BAG_WORN)

    EM:RegisterForEvent(self.name, EVENT_ACTION_SLOTS_FULL_UPDATE, function()
        self:QueueSendMyBuild(false)
    end)

    EM:RegisterForEvent(self.name, EVENT_ACTION_SLOT_UPDATED, function()
        self:QueueSendMyBuild(false)
    end)

    EM:RegisterForEvent(self.name, EVENT_CHAMPION_PURCHASE_RESULT, function()
        self:QueueSendMyBuild(false)
    end)

    HUD_SCENE:RegisterCallback('StateChange', function()
        self:UpdateVisibility()
        self:UpdateBrowserVisibility()
    end)
    HUD_UI_SCENE:RegisterCallback('StateChange', function()
        self:UpdateVisibility()
        self:UpdateBrowserVisibility()
    end)
end

function GroupBuilds:TrackDisplayedBuild()
    local function onLink(_, button, _, _, linkType, dataString)
        if button ~= MOUSE_BUTTON_INDEX_LEFT or linkType ~= 'sss' then
            return
        end

        if not self.displayed or self.displayed.payload ~= dataString then
            self.displayed = { payload = dataString }
        end
    end

    LINK_HANDLER:RegisterCallback(LINK_HANDLER.LINK_CLICKED_EVENT, onLink)
    LINK_HANDLER:RegisterCallback(LINK_HANDLER.LINK_MOUSE_UP_EVENT, onLink)

    self.saveKeybind = {
        alignment = KEYBIND_STRIP_ALIGN_CENTER,
        {
            name = 'Save to Group Builds',
            keybind = 'GROUP_BUILDS_SAVE_DISPLAYED',
            callback = function()
                self:SaveDisplayedPrompt()
            end,
        },
    }

    local scene = SCENE_MANAGER:GetScene('SuperStarMain')
    if scene then
        scene:RegisterCallback('StateChange', function(_, newState)
            if newState == SCENE_SHOWING then
                KEYBIND_STRIP:AddKeybindButtonGroup(self.saveKeybind)
            elseif newState == SCENE_HIDDEN then
                KEYBIND_STRIP:RemoveKeybindButtonGroup(self.saveKeybind)
                self.displayed = nil
            end
        end)
    end
end

function GroupBuilds:BuildSaveDialog()
    self.roleButtons = {}
    local x = 0
    for _, role in ipairs({ LFG_ROLE_TANK, LFG_ROLE_HEAL, LFG_ROLE_DPS }) do
        local button = WINDOW_MANAGER:CreateControl(nil, GroupBuildsRolePickerRoles, CT_BUTTON)
        button:SetDimensions(36, 36)
        button:SetAnchor(LEFT, GroupBuildsRolePickerRoles, LEFT, x, 0)
        button:SetNormalTexture(self:RoleIcon(role))
        button:SetAlpha(0.3)
        button:SetHandler('OnClicked', function()
            self:SelectRole(role)
        end)
        self.roleButtons[role] = button
        x = x + 42
    end

    self.classButtons = {}
    x = 0
    for classIndex = 1, GetNumClasses() do
        local classId = GetClassInfo(classIndex)
        local button = WINDOW_MANAGER:CreateControl(nil, GroupBuildsRolePickerClasses, CT_BUTTON)
        button:SetDimensions(36, 36)
        button:SetAnchor(LEFT, GroupBuildsRolePickerClasses, LEFT, x, 0)
        button:SetNormalTexture(GetClassIcon(classId))
        button:SetAlpha(0.3)
        button:SetHandler('OnClicked', function()
            self:SelectClass(classId)
        end)
        self.classButtons[classId] = button
        x = x + 42
    end
end

function GroupBuilds:Initialize()
    self.sv = ZO_SavedVars:NewAccountWide('GroupBuildsSavedVariables', 1, nil, {
        sharing = {
            alwaysShare = false,
            refreshInterval = 10,
        },
        groupWindow = {
            shown = true,
            nameFormat = 'account_name',
            showClassIcon = true,
            showSolo = false,
            showBorder = true,
            bgOpacity = 0.85,
        },
        groupWindowPosition = {},
        savedWindowRect = {},
        saved = {},
    })

    self.sharing = false
    self.wasGrouped = false
    self.browserOpen = false
    self.savedCounter = 0

    GroupBuildsSettings:Setup()

    ESO_Dialogs['GROUP_BUILDS_RENAME'] = {
        canQueue = true,
        title = { text = 'Note' },
        mainText = { text = 'Enter a note:' },
        editBox = {},
        buttons = {
            {
                text = SI_DIALOG_ACCEPT,
                callback = function(dialog)
                    GroupBuilds:SetNote(dialog.data.id, ZO_Dialogs_GetEditBoxText(dialog))
                end,
            },
            {
                text = SI_DIALOG_CANCEL,
            },
        },
    }

    ESO_Dialogs['GROUP_BUILDS_EDIT_NAME'] = {
        canQueue = true,
        title = { text = 'Name' },
        mainText = { text = 'Enter a name:' },
        editBox = {},
        buttons = {
            {
                text = SI_DIALOG_ACCEPT,
                callback = function(dialog)
                    GroupBuilds:SetBuildName(dialog.data.id, ZO_Dialogs_GetEditBoxText(dialog))
                end,
            },
            {
                text = SI_DIALOG_CANCEL,
            },
        },
    }

    ESO_Dialogs['GROUP_BUILDS_DELETE'] = {
        title = { text = 'Delete build' },
        mainText = { text = 'Delete this saved build?' },
        buttons = {
            {
                text = SI_DIALOG_CONFIRM,
                callback = function(dialog)
                    GroupBuilds:DeleteSaved(dialog.data.id)
                end,
            },
            {
                text = SI_DIALOG_CANCEL,
            },
        },
    }

    self:BuildSaveDialog()

    self.browser = ZO_SortFilterList.New(GroupBuildsBrowserClass, GroupBuildsBrowser)
    self.browser:InitializeInterface()

    self:RestorePosition()
    self:RestoreBrowserState()
    self:ApplyWindowStyle()

    self:RegisterProtocol()
    self:RegisterEvents()
    self:TrackDisplayedBuild()
    self:RefreshList()
    self:StartRefreshTimer()
end

function GroupBuilds.OnAddOnLoaded(_, addOnName)
    if addOnName ~= GroupBuilds.name then
        return
    end

    EM:UnregisterForEvent(GroupBuilds.name, EVENT_ADD_ON_LOADED)
    GroupBuilds:Initialize()
end

ZO_CreateStringId('SI_BINDING_NAME_GROUP_BUILDS_TOGGLE', 'Toggle Group Builds')
ZO_CreateStringId('SI_BINDING_NAME_GROUP_BUILDS_SAVED', 'Toggle Saved Builds')
ZO_CreateStringId('SI_BINDING_NAME_GROUP_BUILDS_SAVE_DISPLAYED', 'Save Displayed Build')

EM:RegisterForEvent(GroupBuilds.name, EVENT_ADD_ON_LOADED, GroupBuilds.OnAddOnLoaded)
