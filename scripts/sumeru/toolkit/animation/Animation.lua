-- 纯 Lua 动画基类；缺少素材时输出空姿态，派生类实现具体采样方式。
local Animation={};Animation.__index=Animation
-- 创建独立播放实例，定义与运行时间分离。
function Animation.new(definition)
 local self=setmetatable({},Animation);self:init(definition);return self
end
-- 初始化实例字段，动画定义只读共享。
function Animation:init(definition)
 self.definition=definition or {};self.elapsed=0;self.revision=nil;self.playing=false;self.paused=false
end
-- 同一次播放命令幂等；修订号变化或显式重播才重新开始。
function Animation:Play(options)
 options=options or {}
 if self.playing and self.revision==options.revision and not options.restart then return false end
 self.playing=true;self.revision=options.revision;self:Seek(options.elapsed or 0);return true
end
-- 从外部模拟时间恢复姿态，不执行任何进入事件。
function Animation:Seek(elapsed)
 assert(type(elapsed)=="number" and elapsed==elapsed and elapsed>=0 and elapsed<math.huge,"Invalid animation time")
 self.elapsed=elapsed
end
-- 独立播放时推进时间；由 FSM 驱动的实例只调用 Seek。
function Animation:Update(dt)
 assert(type(dt)=="number" and dt==dt and dt>=0 and dt<math.huge,"Invalid animation step")
 if self.playing and not self.paused then self:Seek(self.elapsed+dt) end
 return dt
end
-- 暂停不累计后台时间。
function Animation:Pause(paused) self.paused=paused==true end
-- 停止当前实例，不改共享定义。
function Animation:Stop() self.playing=false end
-- 清理对象池中的上一次播放进度。
function Animation:Reset() self.playing=false;self.elapsed=0;self.revision=nil;self.paused=false end
-- 基类代表空动作，不自动替换成其他素材。
function Animation:IsAvailable() return false end
-- 读取动作时长，供行为决定何时结束动作。
function Animation:Duration() return self.definition.duration or 0 end
-- 查询单次播放是否结束，循环片段不会自行结束。
function Animation:IsFinished() return not self.definition.loop and self.elapsed+1e-8>=self:Duration() end
-- 空动作保持不可见；渲染层只消费统一姿态结果。
function Animation:Sample() return {visible=false,index=0,count=0,finished=self:IsFinished()} end
return Animation
