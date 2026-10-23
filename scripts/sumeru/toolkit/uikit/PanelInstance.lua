-- 独立面板的生命周期组件；不读取游戏状态、不决定页面内容和导航。
local UI=require("urhox-libs/UI")
local Json=require("sumeru.toolkit.uikit.Json")
---@class SumeruPanelInstance
---@field key string
---@field def SumeruPanelDefinition
---@field revision integer?
---@field scope any
---@field shell string?
local Panel={};Panel.__index=Panel
-- 复制实例上下文，子面板不能改写父面板的打开参数。
local function copy(source,target)
 target=target or {};for k,v in pairs(source or {}) do target[k]=v end;return target
end
-- 保留最初失败位置，清理失败不会取代原始错误。
local function trace(err) return debug.traceback(tostring(err),2) end
-- 判断输入对象是否属于当前面板。
local function contains(root,widget)
 while widget do if widget==root then return true end;widget=widget.parent end;return false
end
-- 隐藏或销毁前解除焦点、按压和拖动，避免松手事件穿透到下面。
local function detach(root)
 if not root then return end
 if contains(root,UI.GetFocus()) then UI.ClearFocus() end
 local ids={[0]=true};for id in pairs(UI.Input.GetActivePointers()) do ids[id]=true end
 for id in pairs(ids) do
  if contains(root,UI.GetPressedWidgetForPointer(id)) or contains(root,UI.GetHoveredWidgetForPointer(id)) then
   local x,y=UI.Input.GetLastPosition(id)
   UI.HandlePointerCancel(UI.PointerEvent.new("PointerCancel",{pointerId=id,pointerType=id==0 and "mouse" or "touch",x=x,y=y}))
  end
 end
end
-- 创建未挂载的实例；布局、控制器和弹窗命中策略由调用方传入。
---@param definition SumeruPanelDefinition
---@return SumeruPanelInstance
function Panel.new(key,definition,context)
 return setmetatable({key=key,def=definition,context=copy(context),children={},visible=false,mounted=false,destroyed=false},Panel)
end
-- 在异常后完整释放当前子树并记录一次错误。
function Panel:Fail(message)
 if self.failed then return false end
 self.failed=true;self.error=tostring(message);self:Destroy("error")
 print("[UI] "..tostring(self.key)..": "..self.error)
 return false
end
-- 安全调用当前控制器，单个面板失败不打断其他面板刷新。
function Panel:Invoke(name,...)
 if self.destroyed or self.failed then return false end
 local controller=self.controller;local fn=controller and controller[name]
 if not fn then return true end
 local args=table.pack(...)
 local ok,err=xpcall(function() fn(controller,table.unpack(args,1,args.n)) end,trace)
 if not ok then return self:Fail(err) end
 return true
end
-- 首次挂载完成初始化后才允许显示；半初始化实例同样可释放。
function Panel:Mount()
 if self.destroyed or self.failed then return false end
 if self.mounted then return true end
 local ok,err=xpcall(function()
  local def=self.def;local ctx=self.context
  local props=copy(def.props);props.w=ctx.w;props.h=ctx.h
  local json,loadError=Json.Load(def.template,props,def.components,ctx)
  assert(json,"Cannot load UI "..self.key..": "..tostring(loadError))
  self.json=json;self.root=json.root;self.pointerEvents=json.root.props.pointerEvents or "auto"
  self.root:SetVisible(false);self.root:SetProp("pointerEvents","none")
  self.root:SetProp("zIndex",def.layer or 0)
  if def.modal then
   self.pointerEvents="auto"
   self.root.props.onClick=function(_,event) if event then event:StopPropagation() end end
  end
  ctx.frame:AddChild(self.root)
  ctx.json=json;ctx.root=self.root;ctx.panel=def;ctx.panelKey=self.key;ctx.instance=self
  ---@type SumeruPanelControllerModule
  local module=def.controllerModule or (type(def.controller)=="table" and def.controller or require(def.controller))
  self.controller=module.new()
  if self.controller.Init then self.controller:Init(ctx) end
  self.mounted=true
 end,trace)
 if not ok then return self:Fail(err) end
 return true
end
-- 显示本实例；重新打开时显式参数交给所属页面消费。
function Panel:Show(props,refreshOpen)
 if props~=nil then self.context.pageProps=props end
 if not self:Mount() then return false end
 if self.visible and not refreshOpen then return true end
 self.visible=true;self.root:SetVisible(true);self.root:SetProp("pointerEvents",self.pointerEvents)
 return self:Invoke("Show",self.context)
end
-- 隐藏只影响本实例及其直属子树；浏览状态仍由各控制器持有。
function Panel:Hide(reason)
 if not self.visible or self.destroyed then return true end
 self.visible=false
 for _,child in ipairs(self.children) do child:Hide(reason or "parent-hidden") end
 local ok,err=xpcall(function()
  detach(self.root);self.root:SetVisible(false);self.root:SetProp("pointerEvents","none")
 end,trace)
 if not ok then return self:Fail(err) end
 return self:Invoke("Hide",reason or "hidden")
end
-- 仅更新可见实例的数据，不替业务页面保存任何状态。
function Panel:Refresh(data)
 if not self.visible then return true end
 return self:Invoke("Refresh",data or self.context)
end
-- 将尺寸与胶囊位置通知交给自己的控制器和子实例。
function Panel:Resize(context)
 if context then for _,key in ipairs({"w","h","map","capsule","host"}) do self.context[key]=context[key] end end
 if not self.mounted or self.destroyed then return true end
 if not self:Invoke("Resize",self.context) then return false end
 for _,child in ipairs(self.children) do child:Resize(self.context) end
 return true
end
-- 隐藏实例不推进动画，父面板负责驱动其子实例。
function Panel:Update(dt)
 if not self.visible or not self:Invoke("Update",dt,self.context) then return end
 for _,child in ipairs(self.children) do child:Update(dt) end
end
-- 创建页面拥有的子面板；可指定内容容器和独立弹窗层级。
function Panel:CreateChild(key,definition,options)
 assert(not self.destroyed,"Cannot attach child to a destroyed panel")
 local ctx=copy(self.context);ctx.json=nil;ctx.root=nil;ctx.instance=nil
 ctx.frame=self.root;ctx.pageProps={};copy(options,ctx)
 local child=Panel.new(key,definition,ctx);child.parent=self
 self.children[#self.children+1]=child
 return child
end
-- 销毁支持重复调用和半初始化状态；所有清理步骤都执行完后才报告清理错误。
function Panel:Destroy(reason)
 if self.destroyed or self.destroying then return end
 self.destroying=true
 local errors={}
 -- 单项失败不能阻止剩余资源释放。
 local function cleanup(fn)
  local ok,err=xpcall(fn,trace);if not ok then errors[#errors+1]=err end
 end
 cleanup(function() detach(self.root) end)
 if self.root then cleanup(function() self.root:SetVisible(false);self.root:SetProp("pointerEvents","none") end) end
 if self.visible and self.controller and self.controller.Hide then cleanup(function() self.controller:Hide(reason or "destroy") end) end
 self.visible=false
 for i=#self.children,1,-1 do cleanup(function() self.children[i]:Destroy(reason or "parent-destroy") end) end
 if self.json then cleanup(function() self.json:DestroyComponents(reason) end) end
 if self.controller and self.controller.Destroy then cleanup(function() self.controller:Destroy() end) end
 if self.root and self.root.node then cleanup(function() self.root:Destroy() end) end
 self.children={};self.controller=nil;self.json=nil;self.root=nil
 self.context={};self.mounted=false;self.destroyed=true;self.destroying=false
 if #errors>0 then print("[UI] cleanup "..tostring(self.key)..": "..table.concat(errors,"\n")) end
end
return Panel
