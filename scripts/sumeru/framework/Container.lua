-- sumeru IOC 容器：按 key 注册服务实例或惰性工厂，Get 时解析并缓存为单例。
-- 对应 QFramework 的注册查询底座；owner 通常为 Architecture，工厂签名为 function(arch)。
---@class SumeruContainer
---@field owner_ table?
---@field factories_ table<any,fun(owner:table?):any>
---@field instances_ table<any,any>
local Container={}
Container.__index=Container

-- 创建容器；owner 会在工厂求值时作为参数传入。
---@return SumeruContainer
function Container.new(owner)
 local self=setmetatable({},Container)
 self.owner_=owner;self.factories_={};self.instances_={}
 return self
end

-- 注册服务：value 为实例或 function(arch) 工厂；同 key 同值重复注册视为幂等（进程内重启安全）。
function Container:Register(key,value)
 if key==nil or value==nil then error("[sumeru] Container:Register 需要 key 与 value",2) end
 if self.instances_[key]==value or self.factories_[key]==value then return value end
 if self.instances_[key]~=nil or self.factories_[key]~=nil then error("[sumeru] 重复注册: "..tostring(key),2) end
 if type(value)=="function" then self.factories_[key]=value else self.instances_[key]=value end
 return value
end

-- 解析服务：工厂仅在首次 Get 时求值，结果缓存为单例。
function Container:Get(key)
 local instance=self.instances_[key]
 if instance~=nil then return instance end
 local factory=self.factories_[key]
 if factory==nil then error("[sumeru] 未注册的服务: "..tostring(key),2) end
 instance=factory(self.owner_)
 self.instances_[key]=instance;self.factories_[key]=nil
 return instance
end

-- 查询服务是否已注册（含未求值的工厂）。
function Container:Has(key)
 return self.instances_[key]~=nil or self.factories_[key]~=nil
end

-- 注销服务并返回已缓存的实例（不负责销毁实例自身资源）。
function Container:Unregister(key)
 local instance=self.instances_[key]
 self.instances_[key]=nil;self.factories_[key]=nil
 return instance
end
return Container
