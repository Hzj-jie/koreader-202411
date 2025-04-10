-- Start with a empty stub, because 99.9% of users won't actually need this.
local ReaderActivityIndicator = {}

function ReaderActivityIndicator:isStub() return true end
function ReaderActivityIndicator:onStartActivityIndicator() end
function ReaderActivityIndicator:onStopActivityIndicator() end

-- Now, if we're on Kindle, and we haven't actually murdered Pillow, see what we can do...
local Device = require("device")

if Device:isKindle() then
    if os.getenv("PILLOW_HARD_DISABLED") or os.getenv("PILLOW_SOFT_DISABLED") then
        -- Pillow is dead, bye!
        return ReaderActivityIndicator
    end

    if not Device:isTouchDevice() then
        -- No lipc, bye!
        return ReaderActivityIndicator
    end
else
    -- Not on Kindle, bye!
    return ReaderActivityIndicator
end


-- Okay, if we're here, it's basically because we're running on a Kindle on FW 5.x under KPV
local EventListener = require("ui/widget/eventlistener")
local LibLipcs = require("liblipcs")

ReaderActivityIndicator = EventListener:extend{
    lipc_handle = nil,
}

function ReaderActivityIndicator:isStub() return false end

function ReaderActivityIndicator:_lipc()
    return LibLipcs:of("com.github.koreader.activityindicator")
end

function ReaderActivityIndicator:onStartActivityIndicator()
    if LibLipcs:isFake(self:_lipc()) then return true end
    -- check if activity indicator is needed
    if self.document.configurable.text_wrap == 1 then
        -- start indicator depends on pillow being enabled
        self:_lipc():set_string_property(
            "com.lab126.pillow", "activityIndicator",
            '{"activityIndicator":{ \
                "action":"start","timeout":10000, \
                "clientId":"com.github.koreader.activityindicator", \
                "priority":true}}')
        self.indicator_started = true
    end
    return true
end

function ReaderActivityIndicator:onStopActivityIndicator()
    if LibLipcs:isFake(self:_lipc()) then return true end
    if self.indicator_started then
        -- stop indicator depends on pillow being enabled
        self:_lipc():set_string_property(
            "com.lab126.pillow", "activityIndicator",
            '{"activityIndicator":{ \
                "action":"stop","timeout":10000, \
                "clientId":"com.github.koreader.activityindicator", \
                "priority":true}}')
        self.indicator_started = false
    end
    return true
end

return ReaderActivityIndicator
