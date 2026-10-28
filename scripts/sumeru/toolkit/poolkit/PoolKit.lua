-- 对象池 System：按名称登记 ObjectPool 与 FramePool，统一查询、释放和统计；经 Architecture:RegisterSystem("PoolKit") 管理。
local ObjectPool=require("sumeru.toolkit.poolkit.ObjectPool")
local FramePool=require("sumeru.toolkit.poolkit.FramePool")
---@class SumeruPoolKit
---@field pools_ table<string,SumeruObjectPool|SumeruFramePool>
local Kit={};Kit.__index=Kit
Kit.ObjectPool=ObjectPool
Kit.FramePool=FramePool

-- 创建独立的池登记表；一个架构通常只注册一个实例。
---@return SumeruPoolKit
function Kit.new()
 local self=setmetatable({},Kit);self:init();return self
end

-- 初始化空登记表。
function Kit:init() self.pools_={} end

-- 取或建对象池：同名已存在时直接返回，选项只在首次创建时生效。
---@return SumeruObjectPool
function Kit:Object(name,options)
 local pool=self.pools_[name]
 if pool then return pool --[[@as SumeruObjectPool]] end
 local created=ObjectPool.new(options);self.pools_[name]=created;return created
end

-- 新建帧槽位池并替换同名池：帧池绑定具体控件层，宿主重建时旧池先隐藏再丢弃。
---@return SumeruFramePool
function Kit:Frame(name,options)
 self:Release(name)
 local created=FramePool.new(options);self.pools_[name]=created;return created
end

-- 按名称查询池，不存在时返回 nil。
function Kit:Get(name) return self.pools_[name] end

-- 注销并清空指定池；不销毁池里的控件，控件随宿主树释放。
function Kit:Release(name)
 local pool=self.pools_[name];if not pool then return end
 self.pools_[name]=nil;pool:Clear()
end

-- 汇总全部池的统计，按名称排序；供调试面板低频读取。
function Kit:Stats()
 local rows={}
 for name,pool in pairs(self.pools_) do local row=pool:Stats();row.name=name;rows[#rows+1]=row end
 table.sort(rows,function(a,b) return a.name<b.name end)
 return rows
end

-- 清空记录表的全部键，供 ObjectPool 的 reset 复用数据表。
function Kit.Wipe(t) for k in pairs(t) do t[k]=nil end end
return Kit
