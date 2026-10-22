local UI = require("urhox-libs/UI")
local BaseScrollView = require("urhox-libs/UI/Widgets/ScrollView")
local GestureTypes = UI.GestureEvent.Types

---@class FrameworkScrollView : ScrollView
---@field panPointerId_ number|nil
---@field dragScaleX_ number
---@field dragScaleY_ number
---@field panListeners_ table<string, number>
local ScrollView = BaseScrollView:Extend("FrameworkScrollView")

-- 初始化拖动状态，并让移出滚动区域后的手势继续交给原容器。
function ScrollView:Init(props)
    BaseScrollView.Init(self, props)
    self.panPointerId_ = nil
    self.dragScaleX_ = 1
    self.dragScaleY_ = 1
    self.panListeners_ = {}
    for _, eventType in ipairs({ GestureTypes.PanMove, GestureTypes.PanEnd }) do
        self.panListeners_[eventType] = UI.Gesture.On(eventType, function(event)
            if self.state.isDragging and self.panPointerId_ == event.pointerId then
                event.target = self
            end
        end, 100)
    end
end

-- 鼠标左键与触摸共用拖动；超过框架手势阈值后取消子节点点击。
---@param event GestureEvent
---@return boolean
function ScrollView:OnPanStart(event)
    if self.state.isDragging or self.isDraggingScrollbarV_ or self.isDraggingScrollbarH_ then return false end
    if not self.props.scrollX and not self.props.scrollY then return false end
    if event.pointerType == "mouse" then
        local pointer = UI.Input.GetPointer(event.pointerId)
        if not pointer or ((pointer.buttons or 0) & UI.PointerEvent.Buttons.Primary) == 0 then return false end
    elseif event.pointerType ~= "touch" then
        return false
    end

    self:CancelSnap_()
    UI.CancelPointer(event.pointerId, event.pointerType)
    self.panPointerId_ = event.pointerId
    self.state.isDragging = true
    self.dragStartScrollX_, self.dragStartScrollY_ = self:GetScroll()
    self.state.velocityX, self.state.velocityY = 0, 0
    self.dragScaleX_, self.dragScaleY_ = 1, 1
    ---@type Widget?
    local widget = self
    while widget do
        local props = widget.props
        self.dragScaleX_ = self.dragScaleX_ * (props.scaleX or props.scale or 1)
        self.dragScaleY_ = self.dragScaleY_ * (props.scaleY or props.scale or 1)
        widget = widget.parent
    end
    return true
end

-- 按页面缩放换算拖动距离，沿用框架滚动边界与惯性计算。
---@param event GestureEvent
function ScrollView:OnPanMove(event)
    if not self.state.isDragging or self.panPointerId_ ~= event.pointerId then return end
    local scaled = UI.GestureEvent.new(event.type, event)
    scaled.totalDeltaX = event.totalDeltaX / self.dragScaleX_
    scaled.totalDeltaY = event.totalDeltaY / self.dragScaleY_
    scaled.deltaX = event.deltaX / self.dragScaleX_
    scaled.deltaY = event.deltaY / self.dragScaleY_
    BaseScrollView.OnPanMove(self, scaled)
    if not self.props.scrollX then self.state.velocityX = 0 end
    if not self.props.scrollY then self.state.velocityY = 0 end
    self.scrollbarOpacity_, self.scrollbarFadeTimer_ = 1, 1
end

-- 只结束发起拖动的指针，松手后保留惯性滚动。
function ScrollView:OnPanEnd(event)
    if self.panPointerId_ ~= event.pointerId then return end
    BaseScrollView.OnPanEnd(self, event)
    self.panPointerId_ = nil
end

-- 隐藏页面时停止内容与滚动条拖动，清除遗留惯性。
function ScrollView:CancelDrag()
    self.panPointerId_ = nil
    self.state.isDragging = false
    self.state.velocityX, self.state.velocityY = 0, 0
    self.isDraggingScrollbarV_, self.isDraggingScrollbarH_ = false, false
end

-- 释放手势监听与框架控件，避免销毁后残留输入回调。
function ScrollView:Destroy()
    self:CancelDrag()
    for eventType, listener in pairs(self.panListeners_) do UI.Gesture.Off(eventType, listener) end
    self.panListeners_ = {}
    BaseScrollView.Destroy(self)
end

return ScrollView
