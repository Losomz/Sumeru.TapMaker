-- 通用音频 toolkit：缓存 Sound 资源，复用固定 SoundSource 池，并独立管理 BGM。
---@class SumeruAudioKit
---@field settings table
---@field tracks table<string,string>
---@field effects table<string,string>
---@field scene Scene
---@field music SoundSource
---@field sources SoundSource[]
---@field sourceStates table<number,table>
---@field sounds table<string,Sound>
---@field cooldowns table<string,number>
---@field poolSize integer
---@field musicGain number
---@field effectGain number
---@field current string
---@field clock number
---@field sequence integer
local Kit={};Kit.__index=Kit

local DEFAULT_POOL_SIZE=12
local DEFAULT_MUSIC_GAIN=.28
local DEFAULT_EFFECT_GAIN=.5

-- 创建独立音频播放实例；资源表由业务层注入，Kit 本身不依赖具体游戏。
function Kit.new(config)
 local self=setmetatable({},Kit);self:init(config);return self
end

-- 初始化资源映射、音效池和音乐播放源。
function Kit:init(config)
 config=config or {}
 self.settings=config.settings or {music=true,sfx=true}
 self.tracks=config.music or {}
 self.effects=config.sounds or {}
 self.poolSize=math.max(1,math.floor(tonumber(config.poolSize) or DEFAULT_POOL_SIZE))
 self.musicGain=tonumber(config.musicGain) or DEFAULT_MUSIC_GAIN
 self.effectGain=tonumber(config.effectGain) or DEFAULT_EFFECT_GAIN
 self.scene=Scene()
 self.music=self.scene:CreateChild("Music"):CreateComponent("SoundSource")
 self.music:SetSoundType(SOUND_MUSIC)
 self.sources={};self.sourceStates={};self.sounds={};self.cooldowns={}
 self.current="";self.clock=0;self.sequence=0
 self.aliases={victory="ui",defeat="alarm",tower_hit="hit",boss_spawn="boss",boss_buff="boss"}
 self.priorities={boss_spawn=100,boss=90,boss_buff=90,explosion=80,alarm=70,death=60,hit=40,shot=20,electric=20,flame=20}
 self.gains={shot=.2,boss=.5,boss_spawn=.5,boss_buff=.5}
 self.cooldownDefaults={shot=.16,electric=.16,flame=.16,boss=.36,boss_spawn=.36,boss_buff=.36}
 for i=1,self.poolSize do
  local source=self.scene:CreateChild("Effect"..i):CreateComponent("SoundSource")
  source:SetSoundType(SOUND_EFFECT)
  self.sources[i]=source
  self.sourceStates[i]={priority=0,startedAt=0,sequence=0,name=""}
 end
end

-- 更新设置；关闭音乐或音效时立即停止对应播放源。
function Kit:SetSettings(settings)
 self.settings=settings or {music=true,sfx=true}
 if not self.settings.music then self:StopBGM() end
 if not self.settings.sfx then self:StopEffects() end
end

-- 缓存并返回 Sound 资源，避免重复查找和加载。
function Kit:Sound(path)
 if type(path)~="string" or path=="" then return nil end
 if not self.sounds[path] then self.sounds[path]=cache:GetResource("Sound",path) end
 return self.sounds[path]
end

-- 为一次音效播放寻找空闲或可被低优先级回收的池槽。
---@param priority number
---@return integer|false
function Kit:Acquire(priority)
 local candidate=nil;local candidatePriority=math.huge;local candidateSequence=math.huge
 for i=1,self.poolSize do
  local source=self.sources[i]
  if not source:IsPlaying() then return i end
  local state=self.sourceStates[i]
  if state.priority<candidatePriority or (state.priority==candidatePriority and state.sequence<candidateSequence) then
   candidate=i;candidatePriority=state.priority;candidateSequence=state.sequence
  end
 end
 if candidate and priority>=candidatePriority then
  self.sources[candidate]:Stop()
  return candidate
 end
 return false
end

-- 播放一条池化音效；池满时优先保护 Boss 和爆炸等高优先级声音。
function Kit:PlayEffect(name,options)
 options=options or {}
 if not self.settings.sfx then return false end
 local soundName=options.soundName or self.aliases[name] or name
 local path=self.effects[soundName]
 if not path then return false end
 local cooldownKey=options.cooldownKey or (name=="boss_spawn" and "boss" or name)
 local force=options.force==true or name=="boss_spawn"
 if not force and (self.cooldowns[cooldownKey] or 0)>0 then return false end
 local sound=self:Sound(path)
 if not sound then return false end
 local priority=tonumber(options.priority) or self.priorities[name] or self.priorities[soundName] or 10
 local index=self:Acquire(priority)
 if not index then return false end
 local gain=tonumber(options.gain) or self.gains[name] or self.gains[soundName] or self.effectGain
 local panning=tonumber(options.panning) or 0
 local source=self.sources[index]
 source:SetFrequency(0)
 source:Play(sound,0,gain,panning)
 self.sequence=self.sequence+1
 self.sourceStates[index]={priority=priority,startedAt=self.clock,sequence=self.sequence,name=name}
 local duration=tonumber(options.cooldown)
 if duration==nil then duration=self.cooldownDefaults[name] or self.cooldownDefaults[soundName] or .08 end
 self.cooldowns[cooldownKey]=math.max(0,duration)
 return true
end

-- 兼容旧业务入口，统一转发到池化音效播放器。
function Kit:Effect(name,options) return self:PlayEffect(name,options) end

-- 查询指定事件音效是否仍在播放，供业务等待一次性提示自然结束。
function Kit:IsEffectPlaying(name)
 for i,source in ipairs(self.sources) do
  if self.sourceStates[i].name==name and source:IsPlaying() then return true end
 end
 return false
end

-- 只停止指定事件的音效，保留其他池槽与独立 BGM。
function Kit:StopEffect(name)
 for i,source in ipairs(self.sources) do
  if self.sourceStates[i].name==name then
   source:Stop()
   self.sourceStates[i]={priority=0,startedAt=0,sequence=0,name=""}
  end
 end
end

-- 切换循环 BGM；同一曲目仍在播放时保持当前位置，不重新开始。
function Kit:SwitchBGM(name)
 if not self.settings.music then self:StopBGM();return false end
 if self.current==name and self.music:IsPlaying() then return true end
 local path=self.tracks[name]
 if not path then return false end
 local sound=self:Sound(path)
 if not sound then return false end
 sound:SetLooped(true)
 self.music:SetFrequency(0)
 self.music:Play(sound,0,self.musicGain)
 self.current=name
 return true
end

-- 兼容旧业务入口，统一转发到 BGM 切换管理器。
function Kit:Track(name) return self:SwitchBGM(name) end

-- 停止 BGM 并清空当前曲目标记，恢复时会从目标曲目重新播放。
function Kit:StopBGM()
 self.music:Stop()
 self.current=""
end

-- 停止所有池化音效并重置槽位优先级。
function Kit:StopEffects()
 for i=1,self.poolSize do
  self.sources[i]:Stop()
  self.sourceStates[i]={priority=0,startedAt=self.clock,sequence=0,name=""}
 end
end

-- 推进音效限频时钟，不创建临时播放对象。
function Kit:Update(dt)
 local elapsed=math.max(0,tonumber(dt) or 0)
 self.clock=self.clock+elapsed
 for key,remaining in pairs(self.cooldowns) do
  local nextRemaining=remaining-elapsed
  self.cooldowns[key]=nextRemaining>0 and nextRemaining or nil
 end
end

-- 停止所有音频播放并清理池化状态。
function Kit:Stop()
 self:StopBGM();self:StopEffects();self.cooldowns={}
end

return Kit
