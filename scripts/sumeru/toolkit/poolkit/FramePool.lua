-- 帧槽位池：每帧重画的固定容量对象（UI 图形、弹体精灵等）只在创建时分配，Begin/Next/Finish 按顺序复用并隐藏未用槽位。
---@class SumeruFramePool
---@field items any[]
---@field hide fun(obj:any)?
---@field used integer
---@field last integer
---@field stats {peak:integer,overflow:integer}
local Pool={};Pool.__index=Pool

-- 创建帧槽位池：create(i) 一次性创建第 i 个对象；hide(obj) 隐藏本帧未用到的对象。
---@return SumeruFramePool
function Pool.new(options)
 local self=setmetatable({},Pool);self:init(options);return self
end

-- 一次性创建全部槽位，运行中不再新增对象。
function Pool:init(options)
 local create=assert(options and options.create,"FramePool needs create")
 self.items={};self.hide=options.hide;self.used=0;self.last=0
 self.stats={peak=0,overflow=0}
 for i=1,math.max(0,math.floor(options.capacity or 0)) do self.items[i]=create(i) end
end

-- 开始一帧：从第一个槽位重新分配。
function Pool:Begin() self.used=0 end

-- 取本帧下一个槽位及序号；容量用完时返回 nil, 0 并计入 overflow，调用方先判断 obj。
---@return any? obj
---@return integer index
function Pool:Next()
 local index=self.used+1;local obj=self.items[index]
 if obj==nil then self.stats.overflow=self.stats.overflow+1;return nil,0 end
 self.used=index
 if index>self.stats.peak then self.stats.peak=index end
 return obj,index
end

-- 结束一帧：只隐藏上一帧用过、本帧没用到的槽位。
function Pool:Finish()
 if self.hide then for i=self.used+1,self.last do self.hide(self.items[i]) end end
 self.last=self.used
end

-- 本帧已用槽位数。
function Pool:Used() return self.used end

-- 槽位总数。
function Pool:Capacity() return #self.items end

-- 返回统计快照（新表，供调试面板读取，不在每帧调用）。
function Pool:Stats()
 return {kind="frame",capacity=#self.items,active=self.last,peak=self.stats.peak,overflow=self.stats.overflow}
end

-- 隐藏全部槽位，换局或面板隐藏时使用。
function Pool:Clear()
 self.used=0
 if self.hide then for i=1,self.last do self.hide(self.items[i]) end end
 self.last=0
end
return Pool
