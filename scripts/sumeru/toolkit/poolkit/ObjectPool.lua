-- 通用对象池：对应 QFramework 的 SimpleObjectPool，Allocate 取空闲对象，Recycle 重置后放回；不依赖引擎、UI 或业务。
---@class SumeruObjectPool
---@field create fun():any
---@field reset fun(obj:any)?
---@field limit integer?
---@field cache integer?
---@field free_ any[]
---@field freeSet_ table<any,boolean>
---@field stats {created:integer,active:integer,peak:integer,reused:integer,misses:integer}
local Pool={};Pool.__index=Pool

-- 创建对象池：create 构造新对象；reset 回收时清理；prewarm 预先创建；limit 限制对象总数（含使用中）；cache 限制空闲栈长度，多余的交给 GC。
---@return SumeruObjectPool
function Pool.new(options)
 local self=setmetatable({},Pool);self:init(options);return self
end

-- 初始化空闲栈与统计；空闲集合使用弱键，只用于识别重复回收。
function Pool:init(options)
 options=options or {}
 self.create=assert(options.create,"ObjectPool needs create")
 self.reset=options.reset;self.limit=options.limit;self.cache=options.cache
 self.free_={};self.freeSet_=setmetatable({},{__mode="k"})
 self.stats={created=0,active=0,peak=0,reused=0,misses=0}
 self:Prewarm(options.prewarm or 0)
end

-- 预先创建对象放入空闲栈，不超过 limit。
function Pool:Prewarm(count)
 for _=1,count do
  if self.limit and self.stats.created>=self.limit then return end
  local obj=self.create();self.stats.created=self.stats.created+1
  self.free_[#self.free_+1]=obj;self.freeSet_[obj]=true
 end
end

-- 取一个对象：优先复用空闲对象，否则新建；达到 limit 时返回 nil 并计入 misses。
function Pool:Allocate()
 local free=self.free_;local n=#free;local obj
 if n>0 then
  obj=free[n];free[n]=nil;self.freeSet_[obj]=nil;self.stats.reused=self.stats.reused+1
 else
  if self.limit and self.stats.created>=self.limit then self.stats.misses=self.stats.misses+1;return nil end
  obj=self.create();self.stats.created=self.stats.created+1
 end
 local stats=self.stats;stats.active=stats.active+1
 if stats.active>stats.peak then stats.peak=stats.active end
 return obj
end

-- 回收对象：先调用 reset 再放回空闲栈；同一对象重复回收返回 false；空闲栈已满时丢弃交给 GC。
function Pool:Recycle(obj)
 if obj==nil or self.freeSet_[obj] then return false end
 if self.reset then self.reset(obj) end
 self.stats.active=math.max(0,self.stats.active-1)
 if self.cache and #self.free_>=self.cache then return true end
 self.free_[#self.free_+1]=obj;self.freeSet_[obj]=true
 return true
end

-- 当前空闲对象数。
function Pool:Count() return #self.free_ end

-- 返回统计快照（新表，供调试面板读取，不在每帧调用）。
function Pool:Stats()
 local s=self.stats
 return {kind="object",created=s.created,active=s.active,free=#self.free_,peak=s.peak,reused=s.reused,misses=s.misses}
end

-- 丢弃全部空闲对象；使用中的对象回收时仍可放回。
function Pool:Clear()
 for i=#self.free_,1,-1 do self.freeSet_[self.free_[i]]=nil;self.free_[i]=nil end
end
return Pool
