-- 序列帧派生类：只负责循环、终帧和选帧，不引用引擎或 UI。
local Animation=require("sumeru.toolkit.animation.Animation")
local Sequence=setmetatable({},{__index=Animation});Sequence.__index=Sequence
-- 为一段共享帧数据创建独立播放实例。
function Sequence.new(definition)
 local self=setmetatable({},Sequence);self:init(definition);return self
end
-- 校验帧序列，错误在绑定时暴露。
function Sequence:init(definition)
 Animation.init(self,definition)
 assert(type(definition.frames)=="table" and #definition.frames>0,"Empty animation sequence")
 assert(type(definition.fps)=="number" and definition.fps>0,"Invalid animation fps")
 assert(type(definition.loop)=="boolean","Missing animation loop rule")
end
-- 已绑定序列始终有可显示的帧。
function Sequence:IsAvailable() return true end
-- 播放时长由序列长度和帧率决定。
function Sequence:Duration() return #self.definition.frames/self.definition.fps end
-- 循环取模；单次播放停在最后一帧，不额外复制尾帧。
function Sequence:Sample()
 local d=self.definition;local count=#d.frames;local index=math.floor(self.elapsed*d.fps+1e-8)
 index=d.loop and index%count or math.min(count-1,index)
 return {visible=true,source=d,frame=d.frames[index+1],index=index+1,count=count,finished=self:IsFinished()}
end
return Sequence
