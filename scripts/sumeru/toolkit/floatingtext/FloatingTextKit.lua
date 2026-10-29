-- 固定容量飘字调度器：数据与控件复用，渲染器可替换，不依赖游戏实体；各分组槽位由 PoolKit 的 ObjectPool 管理。
local ObjectPool=require("sumeru.toolkit.poolkit.ObjectPool")
---@class SumeruFloatingTextKit
---@field active SumeruFloatingTextSlot[]
---@field stats {emitted:integer,merged:integer,dropped:integer,evicted:integer,peak:integer}
local Kit={};Kit.__index=Kit
-- 拒绝无效数值，避免坏事件污染动画和累计数值。
local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end
-- 建立一个分组的槽位池：初始化时按容量一次建好槽位与控件，limit 等于容量，运行中不再新建。
-- 传入 config.pools（PoolKit）时以 "poolName:分组id" 登记，先释放同名旧池（槽位绑定本实例的控件层，不能沿用旧控件）；否则建本地池。
local function groupPool(self,group,capacity)
 local options={prewarm=capacity,limit=capacity,create=function()
  local slot={index=#self.slots+1,group=group,pose={},active=false}
  self.slots[slot.index]=slot;self.renderer:Create(slot);return slot
 end}
 ---@type SumeruPoolKit?
 local pools=self.config.pools
 if not pools then return ObjectPool.new(options) end
 local name=(self.config.poolName or "floating-text")..":"..tostring(group.id)
 pools:Release(name)
 local pool=pools:Object(name,options);self.registered[name]=pool;return pool
end
-- 初始化分组配额、槽位池和稠密活动表，运行中不创建槽位或动画对象。
---@return SumeruFloatingTextKit
function Kit.new(config)
 config=config or {}
 local self=setmetatable({config=config,presets=config.presets or {},slots={},active={},groups={},merge={},registered={},
  serial=0,randomState=13579,paused=false,destroyed=false,stats={emitted=0,merged=0,dropped=0,evicted=0,peak=0}},Kit)
 self.renderer=config.renderer or require("sumeru.toolkit.floatingtext.UIRenderer").new(config)
 for _,def in ipairs(config.groups or {{id="default",capacity=config.capacity or 48}}) do
  assert(not self.groups[def.id],"Duplicate floating text group")
  local group={id=def.id};self.groups[def.id]=group
  group.pool=groupPool(self,group,math.max(0,math.floor(def.capacity)))
 end
 for name in pairs(self.presets) do self.merge[name]={} end
 return self
end
-- 使用实例私有随机序列生成出生偏移，不消耗玩法随机数，也不逐帧抖动。
function Kit:NextRandom()
 self.randomState=(self.randomState*48271)%2147483647
 return self.randomState/2147483647*2-1
end
-- O(1) 交换移除活动槽，回收时断开合并索引和业务引用，再放回所属分组的槽位池。
function Kit:Release(slot)
 if not slot.active then return end
 local index=slot.activeIndex;local last=self.active[#self.active]
 self.active[index]=last;last.activeIndex=index;self.active[#self.active]=nil
 if slot.mergeKey~=nil and self.merge[slot.preset][slot.mergeKey]==slot then self.merge[slot.preset][slot.mergeKey]=nil end
 self.renderer:Hide(slot)
 slot.active=false;slot.profile=nil;slot.groupKey=nil;slot.mergeKey=nil;slot.icon=nil;slot.followKey=nil
 slot.group.pool:Recycle(slot)
end
-- 从分组槽位池取槽；配额用满时只替换不高于新事件优先级的最旧显示后再取，扫描范围始终有界。
function Kit:Acquire(group,priority)
 local slot=group.pool:Allocate()
 if slot then return slot end
 local oldest
 for _,active in ipairs(self.active) do
  if active.group==group and active.priority<=priority and (not oldest or active.priority<oldest.priority
   or active.priority==oldest.priority and active.serial<oldest.serial) then oldest=active end
 end
 if not oldest then return nil end
 self.stats.evicted=self.stats.evicted+1;self:Release(oldest)
 return group.pool:Allocate()
end
-- 接收纯显示数据；同类短窗合并，每条新数字只随机一次小幅出生偏移。
function Kit:Emit(event)
 if self.destroyed then return false end
 if type(event)~="table" then self.stats.dropped=self.stats.dropped+1;return false end
 local profile=self.presets[event.preset]
 if not profile or not finite(event.value) or event.value<=0 or not finite(event.x) or not finite(event.y) then
  self.stats.dropped=self.stats.dropped+1;return false
 end
 local group=self.groups[profile.pool or "default"]
 if not group then self.stats.dropped=self.stats.dropped+1;return false end
 local key=event.mergeKey;local map=self.merge[event.preset]
 local existing=key~=nil and map[key]
 local icon=event.icon or profile.icon
 if existing and existing.active and existing.icon==icon and (existing.delay>0
  or existing.age<(profile.mergeWindow or 0)) then
  local total=existing.value+event.value
  if not finite(total) then self.stats.dropped=self.stats.dropped+1;return false end
  existing.value=total;existing.x=event.x;existing.y=event.y;existing.dirty=true
  self.stats.merged=self.stats.merged+1
  if event.flush then self:Flush(event.groupKey or key) end
  return true
 end
 local priority=profile.priority or 0;local groupKey=event.groupKey or key
 local count,oldest=0,nil
 if groupKey~=nil then
  for _,slot in ipairs(self.active) do if slot.groupKey==groupKey then
   count=count+1
   if slot.priority<=priority and (not oldest or slot.priority<oldest.priority
    or slot.priority==oldest.priority and slot.serial<oldest.serial) then oldest=slot end
  end end
 end
 if count>=(self.config.maxPerTarget or 3) then
  if not oldest then self.stats.dropped=self.stats.dropped+1;return false end
  if oldest.group==group then self.stats.evicted=self.stats.evicted+1;self:Release(oldest) end
 end
 local slot=self:Acquire(group,priority)
 if not slot then self.stats.dropped=self.stats.dropped+1;return false end
 if count>=(self.config.maxPerTarget or 3) and oldest.active then
  self.stats.evicted=self.stats.evicted+1;self:Release(oldest)
 end
 self.serial=self.serial+1
 slot.preset=event.preset;slot.profile=profile;slot.value=event.value;slot.icon=icon
 slot.x=event.x;slot.y=event.y;slot.priority=priority;slot.serial=self.serial
 slot.randomX=self:NextRandom();slot.randomY=self:NextRandom();slot.followKey=event.followKey
 slot.groupKey=groupKey;slot.mergeKey=key;slot.age=0;slot.fresh=true;slot.dirty=true
 slot.delay=event.flush and 0 or profile.delay or 0;slot.active=true
 slot.activeIndex=#self.active+1;self.active[slot.activeIndex]=slot
 if key~=nil then map[key]=slot end
 self.stats.emitted=self.stats.emitted+1;self.stats.peak=math.max(self.stats.peak,#self.active)
 if event.flush and groupKey~=nil then self:Flush(groupKey) end
 return true
end
-- 目标死亡时立即显示其尚在汇总的持续伤害，不等待下一次命中。
function Kit:Flush(groupKey)
 if groupKey==nil then return end
 for _,slot in ipairs(self.active) do if slot.groupKey==groupKey and slot.delay>0 then
  slot.delay=0;slot.age=0;slot.fresh=true
 end end
end
-- 保留弹出回弹，随后向上飘并逐渐缩至终点比例；随机出生偏移全程固定。
function Kit:Sample(slot)
 local p=slot.profile;local age=slot.age;local duration=p.duration or .6
 local u=math.min(1,age/duration);local pop=p.pop or .08;local settle=p.settle or .1
 local scale
 if age<pop then
  local t=age/pop;scale=(p.startScale or .75)+((p.peakScale or 1.15)-(p.startScale or .75))*(1-(1-t)^3)
 elseif age<pop+settle then
  local t=(age-pop)/settle;scale=1+((p.peakScale or 1.15)-1)*(1-t)^2
 else
  local progress=math.min(1,(age-pop-settle)/math.max(.001,duration-pop-settle))
  scale=1+((p.endScale or .9)-1)*progress
 end
 local pose=slot.pose
 pose.x=slot.x;pose.y=slot.y
 pose.dx=slot.randomX*(p.spread or 0)
 pose.dy=slot.randomY*(p.spreadY or 0)-(p.offsetY or 0)-(p.rise or 24)*(1-(1-u)^2)
 pose.scale=scale;pose.rotate=slot.randomX*(p.tilt or 0)*(1-u)^2
 local fade=p.fadeAt or math.min(.99,(pop+settle)/duration)
 pose.opacity=u<=fade and 1 or math.max(0,(1-u)/(1-fade))
 pose.visible=slot.delay<=0
 return pose
end
-- 同步宿主提供的主体锚点并推进动画；主体消失后保留最后位置，累计结束才排版。
function Kit:Update(dt)
 if self.destroyed then return end
 dt=finite(dt) and math.max(0,math.min(dt,.2)) or 0
 if self.paused then dt=0 end
 for i=#self.active,1,-1 do
  local slot=self.active[i]
  if slot.followKey~=nil and self.config.resolveAnchor then
   local x,y=self.config.resolveAnchor(slot.followKey)
   if finite(x) and finite(y) then slot.x=x;slot.y=y end
  end
  local elapsed=slot.fresh and 0 or dt;slot.fresh=false
  if slot.delay>0 then
   local wait=math.min(slot.delay,elapsed);slot.delay=slot.delay-wait;elapsed=elapsed-wait
  end
  slot.age=slot.age+elapsed
  if slot.age>=(slot.profile.duration or .6) then self:Release(slot)
  else
   if slot.dirty and slot.delay<=0 then self.renderer:Bind(slot);slot.dirty=false end
   self.renderer:Draw(slot,self:Sample(slot))
  end
 end
end
-- 暂停不累积后台时间，恢复时继续当前姿态。
function Kit:Pause(paused) self.paused=paused==true end
-- 清空所有显示和索引，保留已分配的控件及槽位供下一局复用。
function Kit:Clear()
 for i=#self.active,1,-1 do self:Release(self.active[i]) end
 self.serial=0
end
-- 只在主动查询时创建统计快照，不推测渲染后端的绘制批次数。
function Kit:GetStats()
 local pending=0;for _,slot in ipairs(self.active) do if slot.delay>0 then pending=pending+1 end end
 return {capacity=#self.slots,active=#self.active,pending=pending,visible=#self.active-pending,
  peak=self.stats.peak,emitted=self.stats.emitted,merged=self.stats.merged,dropped=self.stats.dropped,evicted=self.stats.evicted}
end
-- 幂等销毁本实例，调用者负责在所属显示层销毁前调用；注销本实例登记且仍归本实例的 PoolKit 槽位池。
function Kit:Destroy()
 if self.destroyed then return end
 self:Clear();self.renderer:Destroy();self.renderer=nil;self.destroyed=true
 ---@type SumeruPoolKit?
 local pools=self.config.pools
 if pools then
  for name,pool in pairs(self.registered) do if pools:Get(name)==pool then pools:Release(name) end end
 end
 self.slots={};self.groups={};self.merge={};self.presets={};self.registered={};self.config=nil
end
return Kit

---@class SumeruFloatingTextSlot
---@field index integer
---@field active boolean
---@field activeIndex integer
---@field priority number
---@field serial integer
---@field group {id:any,pool:SumeruObjectPool}
---@field pose table
---@field profile table?
---@field preset string
---@field mergeKey any
---@field groupKey any
---@field followKey any
---@field icon string?
---@field value number
---@field x number
---@field y number
---@field randomX number
---@field randomY number
---@field delay number
---@field age number
---@field fresh boolean
---@field dirty boolean
