--[[--
A FrameContainer is some graphics content (1 widget) that is surrounded by a
frame

Example:

    local frame
    frame = FrameContainer:new{
        radius = Size.radius.window,
        bordersize = Size.border.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            -- etc
        }
    }

--]]

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Size = require("ui/size")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

local FrameContainer = WidgetContainer:extend({
  background = nil,
  color = Blitbuffer.COLOR_BLACK,
  margin = 0,
  radius = nil,
  inner_bordersize = 0,
  bordersize = Size.border.window,
  padding = Size.padding.default,
  padding_top = nil,
  padding_right = nil,
  padding_bottom = nil,
  padding_left = nil,
  width = nil,
  height = nil,
  invert = false,
  allow_mirroring = true,
  focusable = false,
  focus_border_size = Size.border.window * 2,
  focus_border_color = Blitbuffer.COLOR_BLACK,
  -- paint hatched background if provided
  stripe_color = nil,
  stripe_width = nil,
  stripe_over = nil, -- draw stripes *after* content is drawn
  stripe_over_alpha = 1,
})

function FrameContainer:_containerSize()
  local content_size = self[1]:getSize()
  self._padding_top = self.padding_top or self.padding
  self._padding_right = self.padding_right or self.padding
  self._padding_bottom = self.padding_bottom or self.padding
  self._padding_left = self.padding_left or self.padding
  if BD.mirroredUILayout() and self.allow_mirroring then
    self._padding_left, self._padding_right =
      self._padding_right, self._padding_left
  end
  local width = content_size.w
    + (self.margin + self.bordersize) * 2
    + self._padding_left
    + self._padding_right
  local height = content_size.h
    + (self.margin + self.bordersize) * 2
    + self._padding_top
    + self._padding_bottom
  return width, height
end

function FrameContainer:getSize()
  local width, height = self:_containerSize()
  if self.width and self.width < width then
    logger.warn(
      "FixMe: FrameContainer self.width ",
      self.width,
      " < content.width ",
      width
    )
    self.width = width
  end
  if self.height and self.height < height then
    logger.warn(
      "FixMe: FrameContainer self.height ",
      self.height,
      " < content.height ",
      height
    )
    self.height = height
  end
  self:mergeSize(self.width or width, self.height or height)
  return self.dimen
end

function FrameContainer:onFocus()
  if not self.focusable then
    return false
  end
  self._origin_bordersize = self.bordersize
  self._origin_border_color = self.color
  self.bordersize = self.focus_border_size
  self.color = self.focus_border_color
  self._focused = true
  return true
end

function FrameContainer:onUnfocus()
  if not self.focusable then
    return false
  end
  if self._focused then
    self.bordersize = self._origin_bordersize
    self.color = self._origin_border_color
    self._focused = nil
    return true
  end
  return false
end

function FrameContainer:paintTo(bb, x, y)
  self:mergePosition(x, y)
  local width, height = self:_containerSize()
  -- TODO: Remove. Expose self.dimen, it's wrong, but some uses are not calling
  -- :getSize()
  self:getSize()
  local container_width = self.width or width
  local container_height = self.height or height

  local shift_x = 0
  if BD.mirroredUILayout() and self.allow_mirroring then
    shift_x = container_width - width
  end

  if self.background then
    if not self.radius or not self.bordersize then
      bb:paintRoundedRect(
        x,
        y,
        container_width,
        container_height,
        self.background,
        self.radius
      )
    else
      bb:paintRoundedRect(
        x,
        y,
        container_width,
        container_height,
        self.background,
        self.radius + self.bordersize
      )
    end
  end
  if self.stripe_width and self.stripe_color and not self.stripe_over then
    -- (No support for radius when hatched/stripe)
    bb:hatchRect(
      x,
      y,
      container_width,
      container_height,
      self.stripe_width,
      self.stripe_color
    )
  end
  if self.inner_bordersize > 0 then
    --- @warning This doesn't actually support radius, it'll always be a square.
    bb:paintInnerBorder(
      x + self.margin,
      y + self.margin,
      container_width - self.margin * 2,
      container_height - self.margin * 2,
      self.inner_bordersize,
      self.color,
      self.radius
    )
  end
  if self.bordersize > 0 then
    local anti_alias = G_reader_settings:nilOrTrue("anti_alias_ui")
    bb:paintBorder(
      x + self.margin,
      y + self.margin,
      container_width - self.margin * 2,
      container_height - self.margin * 2,
      self.bordersize,
      self.color,
      self.radius,
      anti_alias
    )
  end
  if self[1] then
    self[1]:paintTo(
      bb,
      x + self.margin + self.bordersize + self._padding_left + shift_x,
      y + self.margin + self.bordersize + self._padding_top
    )
  end
  if self.stripe_width and self.stripe_color and self.stripe_over then
    -- (No support for radius when hatched/stripe)
    -- We don't want to draw the stripes over any border
    local pad = self.margin + math.max(self.bordersize, self.inner_bordersize)
    bb:hatchRect(
      x + pad,
      y + pad,
      container_width - pad * 2,
      container_height - pad * 2,
      self.stripe_width,
      self.stripe_color,
      self.stripe_over_alpha
    )
  end
  if self.invert then
    bb:invertRect(
      x + self.bordersize,
      y + self.bordersize,
      container_width - 2 * self.bordersize,
      container_height - 2 * self.bordersize
    )
  end
  if self.dim then
    bb:lightenRect(
      x + self.bordersize,
      y + self.bordersize,
      container_width - 2 * self.bordersize,
      container_height - 2 * self.bordersize
    )
  end
end

return FrameContainer
