-- Lazy panel registry. Declarations are metadata only; JSON and controller load on first use.
---@class SumeruPanelRegistry
---@field declarations table<string,SumeruPanelDefinition>
---@field resolved table<string,SumeruPanelDefinition>
---@field root string
local Registry = {}
Registry.__index = Registry

local function copy(source, target)
    for key, value in pairs(source or {}) do target[key] = value end
    return target
end

-- 创建空的声明与解析缓存，实例不共享可变数据；root 为面板约定根路径，默认 ui/panels。
---@return SumeruPanelRegistry
function Registry.new(root)
    return setmetatable({ declarations = {}, resolved = {}, root = root or "ui/panels" }, Registry)
end

-- 设置面板约定根路径，之后登记的面板按此推导默认模板与控制器。
function Registry:SetRoot(root)
    self.root = root or "ui/panels"
end

-- 按约定返回面板模板路径与控制器模块名：<root>/<key>/<key>.ui.json 与 <root 点分>.<key>.<key>。
---@return string template
---@return string controller
function Registry:Paths(key)
    local module = self.root:gsub("/", ".")
    return self.root .. "/" .. key .. "/" .. key .. ".ui.json", module .. "." .. key .. "." .. key
end

-- 登记 JSON 页面和独立 Controller，不接受原生场景旁路。
---@param definition SumeruPanelDefinition
function Registry:Register(key, definition)
    assert(type(key) == "string" and key ~= "", "PanelRegistry key must be a non-empty string")
    assert(type(definition) == "table", "PanelRegistry definition must be a table")
    local item = copy(definition, { key = key })
    item.owner = item.owner or "global"
    item.layer = item.layer or 40
    local template, controller = self:Paths(key)
    item.template = item.template or template
    item.controller = item.controller or controller
    self.declarations[key] = item
    self.resolved[key] = nil
    return item
end

-- 只解析声明；模块加载交由面板实例隔离，避免单页依赖错误中断整个宿主。
---@return SumeruPanelDefinition
function Registry:Resolve(key)
    local cached = self.resolved[key]
    if cached then return cached end
    local declaration = self.declarations[key]
    if not declaration then
        error("PanelRegistry: unknown panel '" .. tostring(key) .. "'")
    end
    local resolved = copy(declaration, {})
    self.resolved[key] = resolved
    return resolved
end

function Registry:Get(key)
    return self.declarations[key]
end

function Registry:List()
    local result = {}
    for key, definition in pairs(self.declarations) do
        result[#result + 1] = definition
    end
    table.sort(result, function(a, b)
        return (a.index or 0) < (b.index or 0)
    end)
    return result
end

return Registry

---@class SumeruPanelControllerModule
---@field new fun():table

---@class SumeruPanelDefinition
---@field key string?
---@field index integer?
---@field owner string?
---@field shell string?
---@field layer integer?
---@field template string?
---@field controller string|SumeruPanelControllerModule?
---@field controllerModule SumeruPanelControllerModule?
---@field props table?
---@field components string[]?
---@field modal boolean?
---@field keepMounted boolean?
---@field scope (fun(app:table):any)?
---@field visible (fun(app:table,kit:table):boolean)?
