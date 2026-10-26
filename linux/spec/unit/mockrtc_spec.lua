describe("MockRTC", function()
  local MockRTC

  setup(function()
    require("commonrequire")
    MockRTC = require("device/kindle/mockrtc")
  end)

  before_each(function()
    MockRTC:unsetWakeupAlarm()
  end)

  it("should schedule wakeup alarm when enabled is true or nil", function()
    assert.is_false(MockRTC:isWakeupAlarmScheduled())
    assert.is_nil(MockRTC:getWakeupAlarmEpoch())

    MockRTC:setWakeupAlarm(1000)
    assert.is_true(MockRTC:isWakeupAlarmScheduled())
    assert.equals(1000, MockRTC:getWakeupAlarmEpoch())

    MockRTC:setWakeupAlarm(2000, true)
    assert.is_true(MockRTC:isWakeupAlarmScheduled())
    assert.equals(2000, MockRTC:getWakeupAlarmEpoch())
  end)

  it("should validate wakeup alarm by proximity", function()
    local now = os.time()
    MockRTC:setWakeupAlarm(now, true)

    assert.is_true(MockRTC:validateWakeupAlarmByProximity(now, 5))
    assert.is_nil(MockRTC:validateWakeupAlarmByProximity(now + 100, 5))
    assert.is_nil(MockRTC:validateWakeupAlarmByProximity(nil, 5))
  end)
end)
