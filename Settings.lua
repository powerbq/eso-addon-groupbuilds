GroupBuildsSettings = {}

function GroupBuildsSettings:Setup()
    local panelName = 'GroupBuildsOptions'

    local panelData = {
        type = 'panel',
        name = 'Group Builds',
        author = '@f1rex',
        registerForDefaults = true,
        registerForRefresh = true,
    }
    self.panel = LibAddonMenu2:RegisterAddonPanel(panelName, panelData)

    local optionsData = {
        {
            type = 'header',
            name = 'Sharing',
        },
        {
            type = 'checkbox',
            name = 'Always share my build',
            tooltip = 'When on, your build is shared automatically in every group and the in-window toggle is hidden. When off, sharing starts disabled each time you join a new group.',
            getFunc = function()
                return GroupBuilds.sv.sharing.alwaysShare
            end,
            setFunc = function(value)
                GroupBuilds.sv.sharing.alwaysShare = value
                GroupBuilds:RefreshList()
                if GroupBuilds:IsSharing() then
                    GroupBuilds:QueueSendMyBuild(true)
                else
                    GroupBuilds:ClearMyBuild()
                end
            end,
            default = false,
        },
        {
            type = 'slider',
            name = 'Auto-refresh interval (s)',
            tooltip = '0 = off. Periodically re-check your build out of combat and resend it only if it changed. Catches changes not detected automatically (mundus, food, champion points, etc.).',
            min = 0,
            max = 120,
            step = 5,
            getFunc = function()
                return GroupBuilds.sv.sharing.refreshInterval
            end,
            setFunc = function(value)
                GroupBuilds.sv.sharing.refreshInterval = value
                GroupBuilds:StartRefreshTimer()
            end,
            default = 10,
        },
        {
            type = 'header',
            name = 'Group window',
        },
        {
            type = 'dropdown',
            name = 'Name format',
            choices = { 'Character name', 'Account ID', 'Name (ID)', 'ID (Name)' },
            choicesValues = { 'name', 'account', 'name_account', 'account_name' },
            getFunc = function()
                return GroupBuilds.sv.groupWindow.nameFormat
            end,
            setFunc = function(value)
                GroupBuilds.sv.groupWindow.nameFormat = value
                GroupBuilds:RefreshList()
            end,
            default = 'account_name',
        },
        {
            type = 'checkbox',
            name = 'Show class icon',
            getFunc = function()
                return GroupBuilds.sv.groupWindow.showClassIcon
            end,
            setFunc = function(value)
                GroupBuilds.sv.groupWindow.showClassIcon = value
                GroupBuilds:RefreshList()
            end,
            default = true,
        },
        {
            type = 'checkbox',
            name = 'Show window without a group',
            tooltip = 'When not in a group, keep the window open. It stays empty — builds are only shown while in a group.',
            getFunc = function()
                return GroupBuilds.sv.groupWindow.showSolo
            end,
            setFunc = function(value)
                GroupBuilds.sv.groupWindow.showSolo = value
                GroupBuilds:RefreshList()
            end,
            default = false,
        },
        {
            type = 'checkbox',
            name = 'Show window border',
            getFunc = function()
                return GroupBuilds.sv.groupWindow.showBorder
            end,
            setFunc = function(value)
                GroupBuilds.sv.groupWindow.showBorder = value
                GroupBuilds:ApplyWindowStyle()
            end,
            default = true,
        },
        {
            type = 'slider',
            name = 'Background opacity',
            min = 0,
            max = 100,
            step = 5,
            getFunc = function()
                return GroupBuilds.sv.groupWindow.bgOpacity * 100
            end,
            setFunc = function(value)
                GroupBuilds.sv.groupWindow.bgOpacity = value / 100
                GroupBuilds:ApplyWindowStyle()
            end,
            default = 85,
        },
    }
    LibAddonMenu2:RegisterOptionControls(panelName, optionsData)
end
