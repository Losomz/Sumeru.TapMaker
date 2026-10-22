-- Lazy component registry for JSON templates and framework widgets.
-- A declaration stores a factory; the widget class/template is installed only when used.
local UI = require("urhox-libs/UI")

local Registry = {}
Registry.__index = Registry

function Registry.new()
    return setmetatable({ declarations = {}, resolved = {} }, Registry)
end

function Registry:RegisterWidget(typeName, factory)
    assert(type(typeName) == "string" and typeName ~= "", "Component widget type must be non-empty")
    assert(type(factory) == "function", "Component widget factory is required for " .. typeName)
    self.declarations[typeName] = { kind = "widget", factory = factory }
    self.resolved[typeName] = nil
end

function Registry:RegisterTemplate(typeName, template, controller)
    assert(type(typeName) == "string" and typeName ~= "", "Component template type must be non-empty")
    assert(type(template) == "string" and template ~= "", "Component template path is required for " .. typeName)
    self.declarations[typeName] = { kind = "template", template = template, controller = controller }
    self.resolved[typeName] = nil
end

function Registry:Resolve(typeName)
    local cached = self.resolved[typeName]
    if cached then return cached end
    local declaration = self.declarations[typeName]
    if not declaration then
        local slug = typeName:gsub("(%u)", "-%1"):sub(2):lower()
        local resource = "game/ui/components/" .. slug .. "/" .. slug .. ".ui.json"
        local file = cache and cache:GetFile(resource)
        if not file then error("ComponentRegistry: unknown component '" .. tostring(typeName) .. "' (tried " .. resource .. ")") end
        file:Close()
        self:RegisterTemplate(typeName, resource, "game.ui.components." .. slug .. "." .. slug)
        declaration = self.declarations[typeName]
    end
    if declaration.kind == "widget" then
        declaration.widgetClass = declaration.factory()
        assert(declaration.widgetClass, "ComponentRegistry: factory returned nil for '" .. typeName .. "'")
        UI[typeName] = declaration.widgetClass
    else
        UI.UILoader.RegisterComponent(typeName, declaration.template)
        if declaration.controller then
            local ok, controller = pcall(require, declaration.controller)
            if not ok then error("ComponentRegistry: failed to load controller '" .. declaration.controller .. "' for '" .. typeName .. "': " .. tostring(controller)) end
            declaration.controllerModule = controller
        end
    end
    self.resolved[typeName] = declaration
    return declaration
end

function Registry:Ensure(list)
    for _, typeName in ipairs(list or {}) do self:Resolve(typeName) end
end

-- A JSON component instance owns its own controller and widget subtree.
function Registry:Instantiate(typeName, props, context)
    local definition = self:Resolve(typeName)
    assert(definition.kind == "template", "ComponentRegistry: '" .. typeName .. "' is not a JSON component")
    local Json = require("sumeru.toolkit.uikit.Json")
    local json, err = Json.Load(definition.template, props.layoutProps or props, definition.components, context)
    if not json then error("ComponentRegistry: '" .. typeName .. "': " .. tostring(err)) end
    local module = definition.controllerModule
    local controller = module and (module.new and module.new() or setmetatable({}, { __index = module })) or nil
    local instance = { json = json, root = json.root, controller = controller, props = props, context = context }
    if controller and controller.Init then controller:Init(json, context, props) end
    if controller and controller.Show then controller:Show(props) end
    function instance:Refresh(nextProps)
        self.props = nextProps
        if self.controller and self.controller.Refresh then self.controller:Refresh(nextProps) end
    end
    function instance:Destroy()
        if self.controller and self.controller.Hide then self.controller:Hide("destroy") end
        if self.json and self.json.DestroyComponents then self.json:DestroyComponents("destroy") end
        if self.controller and self.controller.Destroy then self.controller:Destroy() end
        if self.root and self.root.node then self.root:Destroy() end
        self.controller = nil; self.root = nil; self.json = nil
    end
    return instance
end
local defaultRegistry = Registry.new()
defaultRegistry:RegisterWidget("FrameworkButton", function() return require("sumeru.toolkit.uikit.components.Controls").Button end)
-- 轻量化面板与导航专用按压效果，不影响设置和结算控件。
defaultRegistry:RegisterWidget("LightButton", function() return require("game.ui.LightButton") end)
-- 收起与关闭共用固定触区和框架悬浮动效，各自使用独立图形。
defaultRegistry:RegisterWidget("CollapseButton", function() return require("game.ui.PanelIconButton").Collapse end)
defaultRegistry:RegisterWidget("CloseButton", function() return require("game.ui.PanelIconButton").Close end)
defaultRegistry:RegisterWidget("FrameworkToggle", function() return require("sumeru.toolkit.uikit.components.Controls").Toggle end)
-- 按需注册支持鼠标与触摸拖动的滚动容器。
defaultRegistry:RegisterWidget("FrameworkScrollView", function() return require("sumeru.toolkit.uikit.components.DragScrollView") end)
defaultRegistry:RegisterWidget("MineArt", function() return require("game.ui.MineArt") end)
defaultRegistry:RegisterTemplate("EntryButton", "game/ui/components/entry-button/entry-button.ui.json", "game.ui.components.entry-button.entry-button")
defaultRegistry:RegisterTemplate("BottomNavButton", "game/ui/components/bottom-nav-button/bottom-nav-button.ui.json", "game.ui.components.bottom-nav-button.bottom-nav-button")

return defaultRegistry
