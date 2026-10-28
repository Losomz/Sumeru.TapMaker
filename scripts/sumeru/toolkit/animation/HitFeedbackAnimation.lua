-- 代码动画派生类：叠加闪白、当前动作短停和轴心缩放，不替换主动作。
local Animation=require("sumeru.toolkit.animation.Animation")
local Feedback=setmetatable({},{__index=Animation});Feedback.__index=Feedback
-- 可绑定已有可序列化时钟；实例自身不写入存档。
function Feedback.new(definition,clock)
 local self=setmetatable({},Feedback);self:init(definition,clock);return self
end
-- 沿用现有剩余时间字段，旧存档恢复不会重新触发受击。
function Feedback:init(definition,clock)
 Animation.init(self,definition)
 assert(definition.duration>=0 and definition.flashDuration>0 and definition.immunity>=0,"Invalid hit feedback")
 self:Rebind(clock)
end
-- 换绑可序列化时钟：对象池复用播放器时接到新实体，沿用该时钟已有的剩余时间。
function Feedback:Rebind(clock)
 self.clock=clock or {}
 self.clock.hitStop=math.min(self.definition.duration,self.clock.hitStop or 0)
 self.clock.hitImmune=self.clock.hitImmune or 0;self.clock.flash=self.clock.flash or 0
end
-- 重复命中不延长短停；战斗可单独允许再次刷新闪白。
function Feedback:Play(options)
 options=options or {};if options.disabled then return false end
 local c,d=self.clock,self.definition
 if options.refreshFlash then c.flash=d.flashDuration end
 if c.hitStop>1e-8 or c.hitImmune>1e-8 then return false end
 c.flash=d.flashDuration;c.hitStop=d.duration;self.playing=true;return true
end
-- 闪白按完整时间消退；只有未被冻结的余量交给移动与主动作。
function Feedback:Update(dt)
 assert(type(dt)=="number" and dt==dt and dt>=0 and dt<math.huge,"Invalid feedback step")
 if self.paused then return 0 end
 local c,d=self.clock,self.definition;c.flash=math.max(0,c.flash-dt)
 local held=math.min(c.hitStop,dt);c.hitStop=math.max(0,c.hitStop-held)
 local available=dt-held
 if held>0 and c.hitStop<=1e-8 then c.hitStop=0;c.hitImmune=d.immunity end
 c.hitImmune=math.max(0,c.hitImmune-available)
 return available>1e-8 and available or 0
end
-- 从外部反馈时间读取表现，不推进模拟，也不重新启动硬直。
function Feedback:Seek(elapsed)
 Animation.Seek(self,elapsed);local c,d=self.clock,self.definition
 c.flash=math.max(0,d.flashDuration-elapsed);c.hitStop=math.max(0,d.duration-elapsed)
end
-- 代码动画始终可绑定，是否可触发由调用者的存活状态决定。
function Feedback:IsAvailable() return true end
-- 反馈可见时长取闪白和短停中的较长者，免疫不占用播放时长。
function Feedback:Duration() return math.max(self.definition.duration,self.definition.flashDuration) end
-- 可见反馈消退后结束，硬直免疫仍独立保留。
function Feedback:IsFinished() return self.clock.flash<=1e-8 and self.clock.hitStop<=1e-8 end
-- 返回纯表现参数，渲染层无需再计算闪白与缩放曲线。返回本实例复用的表，下次 Sample 前有效。
function Feedback:Sample()
 local amount=math.max(0,math.min(1,self.clock.flash/self.definition.flashDuration))
 local s=self.sample_
 s.flashAmount=amount;s.flashAlpha=math.min(1,amount*2);s.scale=1+self.definition.scale*amount;s.frozen=self.clock.hitStop>1e-8
 return s
end
-- 终止反馈时清除所有剩余时间，死亡不被短停拖延。
function Feedback:Reset()
 Animation.Reset(self);self.clock.flash=0;self.clock.hitStop=0;self.clock.hitImmune=0
end
-- 显式停止取消覆盖效果，不停止主动作。
function Feedback:Stop() self:Reset() end
return Feedback
