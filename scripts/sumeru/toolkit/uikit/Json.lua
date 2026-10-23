-- Project-side JSON loader and component-controller lifecycle adapter.
local UI=require("urhox-libs/UI")
local Components=require("sumeru.toolkit.uikit.ComponentRegistry")
local Json={}
local function walk(widget,fn)
 if not widget then return end
 fn(widget)
 for _,child in ipairs(widget.children or {}) do walk(child,fn) end
end
-- 加载单份布局，初始化失败时回收已经创建的组件和控件。
function Json.Load(template,props,components,context)
 Components:Ensure(components)
 local instance,loadError=UI.LoadJSON(template,props)
 if not instance then return nil,loadError end
 local root=instance:GetRoot()
 if not root then return nil,"JSON root was destroyed: "..template end
 local seen={};local duplicates={}
 walk(root,function(widget)
  local id=widget.props and widget.props.id
  if id then if seen[id] then duplicates[#duplicates+1]=id else seen[id]=true end end
 end)
 if #duplicates>0 then root:Destroy();return nil,"duplicate widget id '"..duplicates[1].."' in "..template end
 local result={template=template,instance=instance,root=root,componentControllers={}}
 function result:Find(id)
  local widget=self.instance:Find(id)
  if not widget then error("JSON panel '"..self.template.."' is missing widget id '"..tostring(id).."'") end
  return widget
 end
 function result:TryFind(id) return self.instance:Find(id) end
 function result:Walk(fn) walk(self.root,fn) end
 -- 即使一个组件清理失败，也继续清理其他已创建组件。
 function result:DestroyComponents(reason)
  local errors={}
  for i=#self.componentControllers,1,-1 do
   local c=self.componentControllers[i]
   if c.Hide then local ok,message=pcall(c.Hide,c,reason or "destroy");if not ok then errors[#errors+1]=tostring(message) end end
   if c.Destroy then local ok,message=pcall(c.Destroy,c);if not ok then errors[#errors+1]=tostring(message) end end
   self.componentControllers[i]=nil
  end
  if #errors>0 then error(table.concat(errors,"\n")) end
 end
 if context then
  local ok,message=xpcall(function() result:Walk(function(widget)
   local kind=widget.props and widget.props.component
   if kind then
    local def=Components:Resolve(kind)
    if def.controllerModule then
     local module=def.controllerModule
     local controller=module.new and module.new() or setmetatable({},{__index=module})
     result.componentControllers[#result.componentControllers+1]=controller
     controller:Init(widget,context,widget.props)
     if controller.Show then controller:Show(widget.props) end
    end
   end
  end) end,function(err) return debug.traceback(tostring(err),2) end)
  if not ok then
   pcall(result.DestroyComponents,result,"init-error")
   pcall(function() root:Destroy() end)
   error(message,0)
  end
 end
 return result
end
return Json
