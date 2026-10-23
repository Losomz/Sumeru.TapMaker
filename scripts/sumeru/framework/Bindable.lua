-- sumeru BindableProperty：带变更通知的值容器。
-- 对应 QFramework 的 BindableProperty<T>；Set 仅在值变化时通知订阅者（新值, 旧值）。
---@class SumeruBindable<T>
---@field value_ T
---@field subs_ (fun(value:T,old:T))[]
local Bindable={}
Bindable.__index=Bindable

-- 创建绑定属性并指定初值。
---@generic T
---@param value T
---@return SumeruBindable<T>
function Bindable.new(value)
 local self=setmetatable({},Bindable)
 self.value_=value;self.subs_={}
 return self
end

-- 读取当前值。
function Bindable:Get()
 return self.value_
end

-- 写入值：与旧值相同则不通知。
function Bindable:Set(value)
 if self.value_==value then return end
 local old=self.value_;self.value_=value
 local snapshot={}
 for i=1,#self.subs_ do snapshot[i]=self.subs_[i] end
 for i=1,#snapshot do snapshot[i](value,old) end
end

-- 订阅变更通知，返回反订阅函数。
function Bindable:Subscribe(fn)
 self.subs_[#self.subs_+1]=fn
 local bind=self
 return function()
  for i=#bind.subs_,1,-1 do
   if bind.subs_[i]==fn then table.remove(bind.subs_,i) end
  end
 end
end
return Bindable
