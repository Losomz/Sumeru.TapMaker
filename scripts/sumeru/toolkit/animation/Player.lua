-- 通用播放控制器：绑定 ID 与多态动画，主动作和代码反馈分层。
local Player={};Player.__index=Player
-- 创建互不共享运行时间的控制器。
function Player.new()
 local self=setmetatable({},Player);self:init();return self
end
-- 初始化绑定表及当前动作；pose_ 与 feedback_ 是本控制器复用的采样结果表。
function Player:init()
 self.bindings={};self.overlays={};self.current=nil;self.id=nil;self.paused=false
 self.feedback_={flashAmount=0,flashAlpha=0,scale=1,frozen=false};self.pose_={visible=false,index=0,count=0,feedback=self.feedback_}
end
-- 绑定枚举值与动画实例；覆盖层不会抢占主动作。
function Player:Bind(id,animation,overlay)
 assert(type(id)=="string" or type(id)=="number","Invalid animation ID")
 assert(not self.bindings[id],"Duplicate animation ID: "..tostring(id))
 assert(type(animation.Play)=="function" and type(animation.Sample)=="function","Invalid animation instance")
 self.bindings[id]={animation=animation,overlay=overlay==true}
 if overlay then self.overlays[#self.overlays+1]=animation end
 return self
end
-- 状态机只发播放命令；具体类型由绑定的派生实例处理。
function Player:Play(id,options)
 local binding=assert(self.bindings[id],"Unbound animation ID: "..tostring(id))
 if binding.overlay then return binding.animation:Play(options) end
 if self.current~=binding.animation then
  if self.current then self.current:Stop() end
  self.current=binding.animation;self.id=id
 end
 return self.current:Play(options)
end
-- 接入唯一模拟时间；不再启动另一套序列帧计时。
function Player:Seek(elapsed) if self.current then self.current:Seek(elapsed) end end
-- 独立预览可推进自身时钟，覆盖层的短停余量控制主动作。
function Player:Update(dt)
 if self.paused then return end
 local available=dt
 for _,animation in ipairs(self.overlays) do available=math.min(available,animation:Update(dt) or dt) end
 if self.current then self.current:Update(available) end
end
-- 查询绑定的数据，行为和 UI 无需辨别具体播放类型。
function Player:Definition(id)
 local binding=self.bindings[id];return binding and binding.animation.definition
end
-- 缺失动作保留绑定但不可见。
function Player:IsAvailable(id)
 local binding=self.bindings[id];return binding and binding.animation:IsAvailable() or false
end
-- 查询当前动作结束，不检查帧率或素材实现。
function Player:IsFinished() return self.current and self.current:IsFinished() or false end
-- 读取当前动作时长。
function Player:Duration() return self.current and self.current:Duration() or 0 end
-- 合成姿态和代码表现；当前仅一层受击反馈，后续可继续派生动画类。
-- 返回本控制器复用的表（feedback 子表同样复用），下次 Sample 前有效；需要跨帧保存时复制字段。
function Player:Sample()
 local pose,feedback=self.pose_,self.feedback_
 local current=self.current and self.current:Sample()
 if current then
  pose.visible=current.visible;pose.source=current.source;pose.frame=current.frame
  pose.index=current.index;pose.count=current.count;pose.finished=current.finished
 else
  pose.visible=false;pose.source=nil;pose.frame=nil;pose.index=0;pose.count=0;pose.finished=nil
 end
 feedback.flashAmount=0;feedback.flashAlpha=0;feedback.scale=1;feedback.frozen=false
 for _,animation in ipairs(self.overlays) do
  local effect=animation:Sample()
  feedback.flashAmount=math.max(feedback.flashAmount,effect.flashAmount or 0)
  feedback.flashAlpha=math.max(feedback.flashAlpha,effect.flashAlpha or 0)
  feedback.scale=feedback.scale*(effect.scale or 1)
  feedback.frozen=feedback.frozen or effect.frozen==true
 end
 pose.feedback=feedback
 return pose
end
-- 暂停冻结主动作和覆盖层；恢复时不重播。
function Player:Pause(paused)
 self.paused=paused==true
 for _,binding in pairs(self.bindings) do binding.animation:Pause(self.paused) end
end
-- 对象池复用时清除进度和反馈，保留绑定定义。
function Player:Reset()
 for _,binding in pairs(self.bindings) do binding.animation:Reset() end
 self.current=nil;self.id=nil;self.paused=false
end
return Player
