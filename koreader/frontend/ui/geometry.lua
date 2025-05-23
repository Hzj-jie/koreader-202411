--[[--
Utilities for 2D geometry.

All of these apply to full rectangles:

    local Geom = require("ui/geometry")
    Geom:new{ x = 1, y = 0, w = Screen:scaleBySize(100), h = Screen:scaleBySize(200), }

Some behaviour is defined for points:

    Geom:new{ x = 0, y = 0, }

Some behaviour is defined for dimensions:

    Geom:new{ w = Screen:scaleBySize(600), h = Screen:scaleBySize(800), }

Just use it on simple tables that have x, y and/or w, h
or define your own types using this as a metatable.

Where @{ffi.blitbuffer|BlitBuffer} is concerned, a point at (0, 0) means the top-left corner.

]]

local Math = require("optmath")

--[[--
Represents a full rectangle (all fields are set), a point (x & y are set), or a dimension (w & h are set).
@table Geom
]]
local Geom = {
  x = 0, -- left origin
  y = 0, -- top origin
  w = 0, -- width
  h = 0, -- height
}

function Geom:new(o)
  if not o then
    o = {
      x = 0,
      y = 0,
      w = 0,
      h = 0,
    }
  end
  setmetatable(o, self)
  self.__index = self
  return o
end

--[[--
Makes a deep copy of itself.
@treturn Geom
]]
function Geom:copy()
  local n = Geom:new()
  n.x = self.x
  n.y = self.y
  n.w = self.w
  n.h = self.h
  return n
end

function Geom:__tostring()
  return self.w .. "x" .. self.h .. "+" .. self.x .. "+" .. self.y
end

--[[--
Offsets rectangle or point by relative values
@int dx x delta
@int dy y delta
]]
function Geom:offsetBy(dx, dy)
  self.x = self.x + dx
  self.y = self.y + dy
  return self
end

--[[--
Offsets rectangle or point to certain coordinates
@int x new x
@int y new y
]]
function Geom:offsetTo(x, y)
  self.x = x
  self.y = y
  return self
end

--[[--
Scales rectangle (top-left corner is rounded down, bottom-right corner is rounded up) or dimension

If a single factor is given, it is applied to both width and height

@int zx scale for x axis
@int zy scale for y axis
]]
function Geom:scaleBy(zx, zy)
  self.w = math.ceil(self.w * zx - 0.001)
  self.h = math.ceil(self.h * (zy or zx) - 0.001)
  return self
end

--[[--
This method also takes care of x and y on top of @{Geom:scaleBy},
c.f., fz_round_rect in MµPDF,
      <https://github.com/ArtifexSoftware/mupdf/blob/d00de0e96a4a5ec90ffc30837d40cd624a6a89e0/source/fitz/geometry.c#L400-L416>

@int zx scale for x axis
@int zy scale for y axis
]]
function Geom:transformByScale(zx, zy)
  self.x = math.floor(self.x * zx + 0.001)
  self.y = math.floor(self.y * (zy or zx) + 0.001)
  self:scaleBy(zx, zy)
end

--[[--
Returns area of itself.

@treturn int
]]
function Geom:area()
  if not self.w or not self.h then
    return 0
  else
    return self.w * self.h
  end
end

--[[--
Enlarges or shrinks dimensions or rectangles

Note that for rectangles the offset stays the same

@int dw width delta
@int dh height delta
]]
function Geom:changeSizeBy(dw, dh)
  self.w = self.w + dw
  self.h = self.h + dh
  return self
end

--[[--
Returns a new outer rectangle that contains both us and a given rectangle

Works for rectangles, dimensions and points

@tparam Geom rect_b
@treturn Geom
]]
function Geom:combine(rect_b)
  return Geom.boundingBox({ self, rect_b })
end

--[[--
Returns a new rectangle for the part that we and a given rectangle share

@tparam Geom rect_b
@treturn Geom
]]
--
--- @todo what happens if there is no rectangle shared? currently behaviour is undefined.
function Geom:intersect(rect_b)
  local intersected = self:copy()
  if not rect_b or rect_b:area() == 0 then
    return intersected
  end

  if self.x < rect_b.x then
    intersected.x = rect_b.x
  end
  if self.y < rect_b.y then
    intersected.y = rect_b.y
  end
  if self.x + self.w < rect_b.x + rect_b.w then
    intersected.w = self.x + self.w - intersected.x
  else
    intersected.w = rect_b.x + rect_b.w - intersected.x
  end
  if self.y + self.h < rect_b.y + rect_b.h then
    intersected.h = self.y + self.h - intersected.y
  else
    intersected.h = rect_b.y + rect_b.h - intersected.y
  end
  return intersected
end

--[[--
Returns true if self does not share any area or edge with rect_b

@tparam Geom rect_b
]]
function Geom:notIntersectWith(rect_b)
  if not rect_b or rect_b:area() == 0 then
    return true
  end

  if
    (self.x >= (rect_b.x + rect_b.w))
    or (self.y >= (rect_b.y + rect_b.h))
    or (rect_b.x >= (self.x + self.w))
    or (rect_b.y >= (self.y + self.h))
  then
    return true
  end
  return false
end

--[[--
Returns true if self geom shares area with rect_b.

@tparam Geom rect_b
]]
function Geom:intersectWith(rect_b)
  return not self:notIntersectWith(rect_b)
end

--[[--
Returns true if self does not share any area with rect_b

@tparam Geom rect_b
]]
function Geom:notOpenIntersectWith(rect_b)
  if not rect_b or rect_b:area() == 0 then
    return true
  end

  if
    (self.x > (rect_b.x + rect_b.w))
    or (self.y > (rect_b.y + rect_b.h))
    or (rect_b.x > (self.x + self.w))
    or (rect_b.y > (self.y + self.h))
  then
    return true
  end
  return false
end

--[[--
Returns true if self geom shares area or an edge with rect_b.

@tparam Geom rect_b
]]
function Geom:openIntersectWith(rect_b)
  return not self:notOpenIntersectWith(rect_b)
end

--[[--
Set size of dimension or rectangle to size of given dimension/rectangle.

@tparam Geom rect_b
]]
function Geom:setSizeTo(rect_b)
  self.w = rect_b.w
  self.h = rect_b.h
  return self
end

--[[--
Checks whether geom is within current rectangle

Works for dimensions, too. For points, it is basically an equality check.

@tparam Geom geom
]]
function Geom:contains(geom)
  if not geom then
    return false
  end

  if
    self.x <= geom.x
    and self.y <= geom.y
    and self.x + self.w >= geom.x + geom.w
    and self.y + self.h >= geom.y + geom.h
  then
    return true
  end
  return false
end

--[[--
Checks for equality.

Works for rectangles, points, and dimensions.

@tparam Geom rect_b
]]
function Geom:__eq(rect_b)
  if self.x == rect_b.x and self.y == rect_b.y and self:equalSize(rect_b) then
    return true
  end
  return false
end

--[[--
Checks the size of a dimension/rectangle for equality.

@tparam Geom rect_b
]]
function Geom:equalSize(rect_b)
  if self.w == rect_b.w and self.h == rect_b.h then
    return true
  end
  return false
end

--[[--
Checks if our size is smaller than the size of the given dimension/rectangle.

@tparam Geom rect_b
]]
function Geom:__lt(rect_b)
  if self.w < rect_b.w and self.h < rect_b.h then
    return true
  end
  return false
end

--[[--
Checks if our size is smaller or equal to the size of the given dimension/rectangle.
@tparam Geom rect_b
]]
function Geom:__le(rect_b)
  if self.w <= rect_b.w and self.h <= rect_b.h then
    return true
  end
  return false
end

--[[--
Offsets the current rectangle by dx, dy while fitting it into the space
of a given rectangle.

This can also be called with dx=0 and dy=0, which will fit the current
rectangle into the given rectangle.

@tparam Geom rect_b
@int dx
@int dy
]]
function Geom:offsetWithin(rect_b, dx, dy)
  -- check size constraints and shrink us when we're too big
  if self.w > rect_b.w then
    self.w = rect_b.w
  end
  if self.h > rect_b.h then
    self.h = rect_b.h
  end
  -- offset
  self.x = self.x + dx
  self.y = self.y + dy
  -- check offsets
  if self.x < rect_b.x then
    self.x = rect_b.x
  end
  if self.y < rect_b.y then
    self.y = rect_b.y
  end
  if self.x + self.w > rect_b.x + rect_b.w then
    self.x = rect_b.x + rect_b.w - self.w
  end
  if self.y + self.h > rect_b.y + rect_b.h then
    self.y = rect_b.y + rect_b.h - self.h
  end
end

--[[--
Centers the current rectangle at position x and y of a given rectangle.

@tparam Geom rect_b
@int dx
@int dy
]]
function Geom:centerWithin(rect_b, x, y)
  -- check size constraints and shrink us when we're too big
  if self.w > rect_b.w then
    self.w = rect_b.w
  end
  if self.h > rect_b.h then
    self.h = rect_b.h
  end
  -- place to center
  self.x = x - self.w / 2
  self.y = y - self.h / 2
  -- check boundary
  if self.x < rect_b.x then
    self.x = rect_b.x
  end
  if self.y < rect_b.y then
    self.y = rect_b.y
  end
  if self.x + self.w > rect_b.x + rect_b.w then
    self.x = rect_b.x + rect_b.w - self.w
  end
  if self.y + self.h > rect_b.y + rect_b.h then
    self.y = rect_b.y + rect_b.h - self.h
  end
end

function Geom:shrinkInside(rect_b, dx, dy)
  self:offsetBy(dx, dy)
  return self:intersect(rect_b)
end

--[[--
Returns the Euclidean distance between two geoms.

@tparam Geom rect_b
]]
function Geom:distance(geom)
  return math.sqrt((self.x - geom.x) ^ 2 + (self.y - geom.y) ^ 2)
end

--[[--
Returns the midpoint of two geoms.

@tparam Geom geom
@treturn Geom
]]
function Geom:midpoint(geom)
  return Geom:new({
    x = Math.round((self.x + geom.x) / 2),
    y = Math.round((self.y + geom.y) / 2),
    w = 0,
    h = 0,
  })
end

--[[--
Returns the center point of this geom.
@treturn Geom
]]
function Geom:center()
  return Geom:new({
    x = self.x + Math.round(self.w / 2),
    y = self.y + Math.round(self.h / 2),
    w = 0,
    h = 0,
  })
end

--[[--
Resets an existing Geom object to zero.
@treturn Geom
]]
function Geom:clear()
  self.x = 0
  self.y = 0
  self.w = 0
  self.h = 0
  return self
end

--[[--
Checks if a dimension or rectangle is empty.
@treturn bool
]]
function Geom:isEmpty()
  if self.w == 0 or self.h == 0 then
    return true
  end
  return false
end

--[[--
Returns a bounding box which encompasses all passed rectangles.
@tparam Geom rectangles to encompass
@treturn Geom bounding box or nil if no rectangles passed
]]
function Geom.boundingBox(boxes)
  local bounding_box
  for _, geom in ipairs(boxes) do
    -- Easier to work with (x0,x0)+(x1,y1) pairs.
    local box = {
      x0 = geom.x,
      y0 = geom.y,
      x1 = geom.x + geom.w,
      y1 = geom.y + geom.h,
    }
    if not bounding_box then
      bounding_box = box
    else
      if box.x0 < bounding_box.x0 then
        bounding_box.x0 = box.x0
      end
      if box.y0 < bounding_box.y0 then
        bounding_box.y0 = box.y0
      end
      if box.x1 > bounding_box.x1 then
        bounding_box.x1 = box.x1
      end
      if box.y1 > bounding_box.y1 then
        bounding_box.y1 = box.y1
      end
    end
  end
  if bounding_box then
    return Geom:new({
      x = bounding_box.x0,
      y = bounding_box.y0,
      w = bounding_box.x1 - bounding_box.x0,
      h = bounding_box.y1 - bounding_box.y0,
    })
  end
end

return Geom
