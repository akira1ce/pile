local layouts = {
    ["1"] = { 0.60, 0.72 },
    ["2"] = { 0.72, 0.78 },
    ["3"] = { 0.98, 0.98 },
}

local stackOffset = 36
local frameTolerance = 4
local layoutStates = {}

local pendingKey
local pendingWindowId
local pendingShouldCollapse
local pendingTimer

local function getContext(screen)
    local spaceId = hs.spaces.activeSpaceOnScreen(screen) or "unknown"
    return screen:getUUID() .. ":" .. tostring(spaceId)
end

local function isUsable(win, screen)
    return win
        and win:isVisible()
        and win:isStandard()
        and not win:isFullScreen()
        and not win:isMinimized()
        and win:screen():getUUID() == screen:getUUID()
end

local function getWindows(screen, focused)
    local windows = {}
    local seen = {}

    if isUsable(focused, screen) then
        table.insert(windows, focused)
        seen[focused:id()] = true
    end

    for _, win in ipairs(hs.window.orderedWindows()) do
        if not seen[win:id()] and isUsable(win, screen) then
            table.insert(windows, win)
            seen[win:id()] = true
        end
    end

    return windows
end

local function getOffset(count, screenFrame, width, height, stacked)
    if not stacked or count < 2 then return 0 end

    return math.max(0, math.min(
        stackOffset,
        (screenFrame.w - width) / (count - 1),
        (screenFrame.h - height) / (count - 1)
    ))
end

local function centerWindow(widthScale, heightScale)
    local win = hs.window.focusedWindow()
    if not win or win:isFullScreen() or win:isMinimized() then return end

    local frame = win:screen():frame()
    local width = frame.w * widthScale
    local height = frame.h * heightScale

    win:setFrame({
        x = frame.x + (frame.w - width) / 2,
        y = frame.y + (frame.h - height) / 2,
        w = width,
        h = height,
    })
end

local function arrangeWindows(widthScale, heightScale, stacked)
    local focused = hs.window.focusedWindow()
    if not focused then return end

    local screen = focused:screen()
    local screenFrame = screen:frame()
    local windows = getWindows(screen, focused)
    local count = #windows

    local width = screenFrame.w * widthScale
    local height = screenFrame.h * heightScale
    local offset = getOffset(count, screenFrame, width, height, stacked)

    for i = count, 1, -1 do
        local shift = (i - 1) * offset
        windows[i]:setFrame({
            x = screenFrame.x + (screenFrame.w - width) / 2 + shift,
            y = screenFrame.y + (screenFrame.h - height) / 2 + shift,
            w = width,
            h = height,
        })
    end

    focused:raise()

    local ids = {}
    for _, win in ipairs(windows) do
        table.insert(ids, win:id())
    end

    layoutStates[getContext(screen)] = {
        mode = stacked and "stacked" or "overlap",
        ids = ids,
        widthScale = widthScale,
        heightScale = heightScale,
    }
end

local function isCurrentStackIntact(screen, focused, state, widthScale, heightScale)
    if not state
        or state.mode ~= "stacked"
        or state.widthScale ~= widthScale
        or state.heightScale ~= heightScale then
        return false
    end

    local windows = getWindows(screen, focused)
    if #windows ~= #state.ids then return false end

    local byId = {}
    for _, win in ipairs(windows) do
        byId[win:id()] = win
    end

    local screenFrame = screen:frame()
    local width = screenFrame.w * widthScale
    local height = screenFrame.h * heightScale
    local offset = getOffset(#state.ids, screenFrame, width, height, true)

    for i, id in ipairs(state.ids) do
        local win = byId[id]
        if not win then return false end

        local frame = win:frame()
        local shift = (i - 1) * offset
        local expectedX = screenFrame.x + (screenFrame.w - width) / 2 + shift
        local expectedY = screenFrame.y + (screenFrame.h - height) / 2 + shift

        if math.abs(frame.x - expectedX) > frameTolerance
            or math.abs(frame.y - expectedY) > frameTolerance
            or math.abs(frame.w - width) > frameTolerance
            or math.abs(frame.h - height) > frameTolerance then
            return false
        end
    end

    return true
end

local function handleLayout(key, size)
    local focused = hs.window.focusedWindow()
    if not focused then return end

    local windowId = focused:id()

    if pendingKey == key
        and pendingWindowId == windowId
        and pendingTimer then
        pendingTimer:stop()
        pendingKey = nil
        pendingWindowId = nil
        pendingTimer = nil

        arrangeWindows(size[1], size[2], not pendingShouldCollapse)
        pendingShouldCollapse = nil
        return
    end

    if pendingTimer then pendingTimer:stop() end

    local screen = focused:screen()
    local state = layoutStates[getContext(screen)]

    -- 在第一次单击居中之前检查原布局是否仍是完整堆叠。
    pendingShouldCollapse = isCurrentStackIntact(
        screen, focused, state, size[1], size[2]
    )

    pendingKey = key
    pendingWindowId = windowId
    centerWindow(size[1], size[2])

    pendingTimer = hs.timer.doAfter(0.45, function()
        if pendingKey == key and pendingWindowId == windowId then
            pendingKey = nil
            pendingWindowId = nil
            pendingShouldCollapse = nil
            pendingTimer = nil
        end
    end)
end

for key, size in pairs(layouts) do
    hs.hotkey.bind({ "option" }, key, function()
        handleLayout(key, size)
    end)
end
