-- ============================================================================
-- Framework UI Controls
-- Shared interactive components collected for reuse across the game UI.
-- ============================================================================

local BaseButton = require("urhox-libs/UI/Widgets/Button")
local BaseToggle = require("urhox-libs/UI/Widgets/Toggle")
local Widget = require("urhox-libs/UI/Core/Widget")
local Panel = require("urhox-libs/UI/Widgets/Panel")
local Theme = require("urhox-libs/UI/Core/Theme")

local Controls = {}

Controls.Assets = {
    toggleTrackOff = "image/ui/lightweight/toggle-off.png",
    toggleTrackOn = "image/ui/lightweight/toggle-on.png",
    toggleThumb = "image/ui/lightweight/toggle-thumb.png",
}

Controls.Motion = {
    button = {
        states = {
            normal = { translateY = 0, scale = 1 },
            hover = { translateY = -1.2, scale = 1 },
            pressed = { translateY = 0.6, scale = 0.975 },
        },
        durations = {
            hover = 0.12,
            press = 0.07,
            release = 0.10,
        },
        easing = "easeOut",
    },
    toggle = {
        states = {
            normal = { rootScale = 1, thumbScale = 1 },
            hover = { rootScale = 1, thumbScale = 1.02 },
            pressed = { rootScale = 0.98, thumbScale = 0.96 },
        },
        durations = {
            slide = 0.14,
            hover = 0.12,
            press = 0.07,
            release = 0.10,
        },
        easing = "easeOut",
        disabledOpacity = 0.45,
    },
}

local function motionTransition(properties, duration, easing)
    local parts = {}
    for _, property in ipairs(properties) do
        parts[#parts + 1] = string.format("%s %.2fs %s", property, duration, easing)
    end
    return table.concat(parts, ", ")
end

-- ============================================================================
-- Button
-- ============================================================================

---@class FrameworkButtonProps : ButtonProps
---@field effectTarget? Widget Visual container moved and scaled by the interaction effect.

---@class FrameworkButton : Button
---@overload fun(props?: FrameworkButtonProps): FrameworkButton
---@field props FrameworkButtonProps
local FrameworkButton = BaseButton:Extend("FrameworkButton")

---@param props FrameworkButtonProps
function FrameworkButton:Init(props)
    props = props or {}
    local effectTarget = props.effectTarget

    BaseButton.Init(self, props)

    self.mouseHovered_ = false
    self.enterPointerType_ = nil
    self.motionState_ = "normal"
    ---@type Widget?
    self.effectTarget_ = nil
    self.baseTranslateY_ = 0
    self.baseScale_ = 1

    self:SetEffectTarget(effectTarget or self)
end

---@param stateName "normal"|"hover"|"pressed"
---@param durationName "hover"|"press"|"release"
function FrameworkButton:ApplyMotionState(stateName, durationName)
    local target = self.effectTarget_
    if not target then return end

    local motion = Controls.Motion.button
    local state = motion.states[stateName] or motion.states.normal
    local duration = motion.durations[durationName] or motion.durations.release
    self.motionState_ = stateName

    target:SetStyle({
        transition = motionTransition({ "translateY", "scale" }, duration, motion.easing),
        translateY = self.baseTranslateY_ + state.translateY,
        scale = self.baseScale_ * state.scale,
    })
end

---@param durationName "hover"|"press"|"release"
function FrameworkButton:RestoreMotion(durationName)
    local stateName = self.mouseHovered_ and not self.props.disabled and "hover" or "normal"
    self:ApplyMotionState(stateName, durationName)
end

---@param target Widget?
---@return FrameworkButton self
function FrameworkButton:SetEffectTarget(target)
    local nextTarget = target or self
    local oldTarget = self.effectTarget_
    if oldTarget and oldTarget ~= nextTarget then
        oldTarget:SetStyle({ translateY = self.baseTranslateY_, scale = self.baseScale_ })
    end

    self.effectTarget_ = nextTarget
    self.props.effectTarget = nextTarget ~= self and nextTarget or nil

    local targetProps = nextTarget.props or {}
    self.baseTranslateY_ = tonumber(targetProps.translateY) or 0
    self.baseScale_ = tonumber(targetProps.scale) or 1
    self.motionState_ = "normal"
    nextTarget:SetStyle({
        transformOrigin = targetProps.transformOrigin or "center",
        translateY = self.baseTranslateY_,
        scale = self.baseScale_,
        transition = motionTransition(
            { "translateY", "scale" },
            Controls.Motion.button.durations.release,
            Controls.Motion.button.easing
        ),
    })
    return self
end

---@param event PointerEvent
function FrameworkButton:OnPointerEnter(event)
    self.enterPointerType_ = event and event.pointerType or nil
    Widget.OnPointerEnter(self, event)
    self.enterPointerType_ = nil
end

function FrameworkButton:OnMouseEnter()
    local pointerType = self.enterPointerType_ or "mouse"
    if pointerType ~= "mouse" then return end

    BaseButton.OnMouseEnter(self)
    if not self.props.disabled then
        self.mouseHovered_ = true
        self:ApplyMotionState("hover", "hover")
    end
end

function FrameworkButton:OnMouseLeave()
    BaseButton.OnMouseLeave(self)
    self.mouseHovered_ = false
    self:ApplyMotionState("normal", "release")
end

---@param event PointerEvent
function FrameworkButton:OnPointerDown(event)
    BaseButton.OnPointerDown(self, event)
    if not event or self.props.disabled or not event:IsPrimaryAction() then return end

    if event.pointerType ~= "mouse" then self.mouseHovered_ = false end
    self:ApplyMotionState("pressed", "press")
end

---@param event PointerEvent
function FrameworkButton:OnPointerUp(event)
    BaseButton.OnPointerUp(self, event)
    if event and event:IsPrimaryAction() then self:RestoreMotion("release") end
end

---@param event PointerEvent
function FrameworkButton:OnPointerCancel(event)
    BaseButton.OnPointerCancel(self, event)
    self.mouseHovered_ = false
    self:ApplyMotionState("normal", "release")
end

---@param disabled boolean
---@return FrameworkButton self
function FrameworkButton:SetDisabled(disabled)
    BaseButton.SetDisabled(self, disabled)
    if disabled then
        self.mouseHovered_ = false
        self:ApplyMotionState("normal", "release")
    end
    return self
end

Controls.Button = FrameworkButton

-- ============================================================================
-- Image Toggle
-- ============================================================================

---@class FrameworkToggleProps : ToggleProps
---@field trackImageOff? string Image for the unchecked track.
---@field trackImageOn? string Image for the checked track.
---@field thumbImage? string Image for the moving thumb.
---@field thumbEdgeOffset? number Extra outward offset applied to both thumb endpoints.
---@field trackImageFit? string "contain" | "fill" Track image sizing without changing the hit box.

---@class FrameworkToggle : Toggle
---@overload fun(props?: FrameworkToggleProps): FrameworkToggle
---@field props FrameworkToggleProps
local FrameworkToggle = BaseToggle:Extend("FrameworkToggle")

---@param props FrameworkToggleProps
function FrameworkToggle:Init(props)
    props = props or {}
    props.trackWidth = props.trackWidth or 58
    props.trackHeight = props.trackHeight or 34
    props.thumbSize = props.thumbSize or 26
    props.width = props.width or 64
    props.height = props.height or 44
    props.trackImageOff = props.trackImageOff or Controls.Assets.toggleTrackOff
    props.trackImageOn = props.trackImageOn or Controls.Assets.toggleTrackOn
    props.thumbImage = props.thumbImage or Controls.Assets.toggleThumb

    BaseToggle.Init(self, props)

    self.enterPointerType_ = nil
    self.mouseHovered_ = false
    self.visualRoot_ = nil
    self.trackOffVisual_ = nil
    self.trackOnVisual_ = nil
    self.thumbVisual_ = nil
    self.thumbTravel_ = 0
end

---@return Widget[]
function FrameworkToggle:Build()
    local props = self.props
    local trackWidth = props.trackWidth
    local trackHeight = props.trackHeight
    local thumbSize = props.thumbSize
    local thumbEdgeOffset = props.thumbEdgeOffset or 0
    local trackY = (props.height - trackHeight) / 2
    local thumbPadding = (trackHeight - thumbSize) / 2
    local thumbHorizontalPadding = thumbPadding - thumbEdgeOffset
    local thumbTravel = trackWidth - thumbSize - thumbHorizontalPadding * 2
    local value = props.value == true
    local disabled = props.disabled == true
    local toggleMotion = Controls.Motion.toggle

    local trackOff = Panel {
        position = "absolute",
        left = 0,
        top = trackY,
        width = trackWidth,
        height = trackHeight,
        backgroundImage = props.trackImageOff,
        backgroundFit = props.trackImageFit or "contain",
        opacity = value and 0 or 1,
        transition = motionTransition({ "opacity" }, toggleMotion.durations.slide, toggleMotion.easing),
        pointerEvents = "none",
    }
    local trackOn = Panel {
        position = "absolute",
        left = 0,
        top = trackY,
        width = trackWidth,
        height = trackHeight,
        backgroundImage = props.trackImageOn,
        backgroundFit = props.trackImageFit or "contain",
        opacity = value and 1 or 0,
        transition = motionTransition({ "opacity" }, toggleMotion.durations.slide, toggleMotion.easing),
        pointerEvents = "none",
    }
    local thumb = Panel {
        position = "absolute",
        left = thumbHorizontalPadding,
        top = trackY + thumbPadding,
        width = thumbSize,
        height = thumbSize,
        backgroundImage = props.thumbImage,
        backgroundFit = "contain",
        translateX = value and thumbTravel or 0,
        scale = 1,
        transformOrigin = "center",
        transition = motionTransition(
            { "translateX", "scale" },
            toggleMotion.durations.slide,
            toggleMotion.easing
        ),
        pointerEvents = "none",
    }
    local visualRoot = Panel {
        position = "absolute",
        left = 0,
        top = 0,
        width = trackWidth,
        height = props.height,
        opacity = disabled and toggleMotion.disabledOpacity or 1,
        scale = 1,
        transformOrigin = "center",
        pointerEvents = "none",
        children = { trackOff, trackOn, thumb },
    }

    self.visualRoot_ = visualRoot
    self.trackOffVisual_ = trackOff
    self.trackOnVisual_ = trackOn
    self.thumbVisual_ = thumb
    self.thumbTravel_ = thumbTravel

    return { visualRoot }
end

-- The track and thumb are rendered by child Panels. Preserve only Toggle's
-- optional text-label behavior from the base widget.
function FrameworkToggle:Render(nvg)
    local props = self.props
    local label = props.label
    if not label or #label == 0 then return end

    local l = self:GetAbsoluteLayout()
    local fontFamily = Theme.FontFamily()
    ---@type number[]
    local textColor = props.disabled and Theme.Color("disabledText") or Theme.Color("text")
    local gap = props.gap or 8

    nvgFontFace(nvg, fontFamily)
    nvgFontSize(nvg, Theme.FontSizeOf("body"))
    nvgFillColor(nvg, nvgRGBA(textColor[1], textColor[2], textColor[3], textColor[4] or 255))
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgText(nvg, l.x + props.trackWidth + gap, l.y + l.h / 2, label, nil)
end

---@param durationName "slide"|"hover"|"press"|"release"
function FrameworkToggle:ApplyVisualState(durationName)
    local visualRoot = self.visualRoot_
    local trackOff = self.trackOffVisual_
    local trackOn = self.trackOnVisual_
    local thumb = self.thumbVisual_
    if not visualRoot or not trackOff or not trackOn or not thumb then return end

    local motion = Controls.Motion.toggle
    local disabled = self.props.disabled == true
    local pressed = self.state.pressed and not disabled
    local hovered = self.mouseHovered_ and not disabled
    local stateName = pressed and "pressed" or hovered and "hover" or "normal"
    local state = motion.states[stateName]
    local stateDuration = motion.durations[durationName] or motion.durations.release
    local value = self.props.value == true

    visualRoot:SetStyle({
        transition = motionTransition({ "scale", "opacity" }, stateDuration, motion.easing),
        scale = state.rootScale,
        opacity = disabled and motion.disabledOpacity or 1,
    })
    trackOff:SetStyle({
        transition = motionTransition({ "opacity" }, motion.durations.slide, motion.easing),
        opacity = value and 0 or 1,
    })
    trackOn:SetStyle({
        transition = motionTransition({ "opacity" }, motion.durations.slide, motion.easing),
        opacity = value and 1 or 0,
    })
    thumb:SetStyle({
        transition = string.format(
            "translateX %.2fs %s, scale %.2fs %s",
            motion.durations.slide,
            motion.easing,
            stateDuration,
            motion.easing
        ),
        translateX = value and self.thumbTravel_ or 0,
        scale = state.thumbScale,
    })
end

---@param event PointerEvent
function FrameworkToggle:OnPointerEnter(event)
    self.enterPointerType_ = event and event.pointerType or nil
    Widget.OnPointerEnter(self, event)
    self.enterPointerType_ = nil
end

function FrameworkToggle:OnMouseEnter()
    local pointerType = self.enterPointerType_ or "mouse"
    if pointerType ~= "mouse" then return end

    BaseToggle.OnMouseEnter(self)
    if not self.props.disabled then
        self.mouseHovered_ = true
        self:ApplyVisualState("hover")
    end
end

function FrameworkToggle:OnMouseLeave()
    BaseToggle.OnMouseLeave(self)
    self.mouseHovered_ = false
    self:ApplyVisualState("release")
end

---@param event PointerEvent
function FrameworkToggle:OnPointerDown(event)
    BaseToggle.OnPointerDown(self, event)
    if not event or self.props.disabled or not event:IsPrimaryAction() then return end

    if event.pointerType ~= "mouse" then self.mouseHovered_ = false end
    self:ApplyVisualState("press")
end

---@param event PointerEvent
function FrameworkToggle:OnPointerUp(event)
    BaseToggle.OnPointerUp(self, event)
    if event and event:IsPrimaryAction() then self:ApplyVisualState("release") end
end

---@param event PointerEvent
function FrameworkToggle:OnPointerCancel(event)
    self.mouseHovered_ = false
    self:SetState({ hovered = false, pressed = false })
    Widget.OnPointerCancel(self, event)
    self:ApplyVisualState("release")
end

---@return FrameworkToggle self
function FrameworkToggle:Toggle()
    return self:SetValue(not self.props.value)
end

---@param value boolean
---@return FrameworkToggle self
function FrameworkToggle:SetValue(value)
    value = value == true
    if self.props.value == value then return self end

    self.props.value = value
    self:ApplyVisualState("slide")
    self:DispatchEvent("change", self, value)
    if self.props.onChange then self.props.onChange(self, value) end
    return self
end

---@param disabled boolean
---@return FrameworkToggle self
function FrameworkToggle:SetDisabled(disabled)
    BaseToggle.SetDisabled(self, disabled)
    self.mouseHovered_ = false
    self:ApplyVisualState("release")
    return self
end

Controls.Toggle = FrameworkToggle

return Controls
