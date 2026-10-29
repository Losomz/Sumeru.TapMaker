-- 通用音频 toolkit：缓存 Sound 资源，音源与错开等待记录由 ObjectPool 复用，按声音规则错开、限量，并独立管理 BGM。
local ObjectPool=require("sumeru.toolkit.poolkit.ObjectPool")
---@class SumeruAudioVoice
---@field source SoundSource
---@field name string
---@field key string
---@field priority number
---@field sequence integer
---@field index integer

---@class SumeruAudioPending
---@field name string
---@field key string
---@field sound Sound?
---@field priority number
---@field gain number
---@field falloff number
---@field panning number
---@field at number

---@class SumeruAudioKit
---@field settings table
---@field tracks table<string,string>
---@field effects table<string,string>
---@field scene Scene
---@field music SoundSource
---@field voices SumeruObjectPool
---@field playing SumeruAudioVoice[]
---@field pendingPool SumeruObjectPool
---@field pending SumeruAudioPending[]
---@field sounds table<string,Sound>
---@field cooldowns table<string,number>
---@field nextAt table<string,number>
---@field aliases table<string,string>
---@field priorities table<string,number>
---@field gains table<string,number>
---@field cooldownDefaults table<string,number>
---@field rules table<string,table>
---@field poolSize integer
---@field pendingSize integer
---@field musicGain number
---@field effectGain number
---@field current string
---@field clock number
---@field sequence integer
---@field stats {played:integer,staggered:integer,dropped:integer,stolen:integer}
local Kit={};Kit.__index=Kit

local DEFAULT_POOL_SIZE=12
local DEFAULT_PENDING_SIZE=16
local DEFAULT_MUSIC_GAIN=.28
local DEFAULT_EFFECT_GAIN=.5
local DEFAULT_COOLDOWN=.08
local DEFAULT_QUEUE=2
local DEFAULT_MAX_DELAY=.2
local EMPTY_RULE={}

-- 以框架默认表为底，合并业务传入的同名覆盖项。
local function merge(defaults,overrides)
 local merged={}
 for key,value in pairs(defaults) do merged[key]=value end
 for key,value in pairs(overrides or {}) do merged[key]=value end
 return merged
end

-- 建立一个对象池：传入 PoolKit 时以 name 登记，先释放同名旧池（音源绑定本实例的场景，不能沿用旧对象）；否则建本地池。
---@param pools SumeruPoolKit?
---@return SumeruObjectPool
local function makePool(pools,name,options)
 if not pools then return ObjectPool.new(options) end
 pools:Release(name)
 return pools:Object(name,options)
end

-- 创建独立音频播放实例；资源表由业务层注入，Kit 本身不依赖具体游戏。
function Kit.new(config)
 local self=setmetatable({},Kit);self:init(config);return self
end

-- 初始化资源映射、播放规则、音源池、错开等待池和音乐播放源。
function Kit:init(config)
 config=config or {}
 self.settings=config.settings or {music=true,sfx=true}
 self.tracks=config.music or {}
 self.effects=config.sounds or {}
 self.poolSize=math.max(1,math.floor(tonumber(config.poolSize) or DEFAULT_POOL_SIZE))
 self.pendingSize=math.max(0,math.floor(tonumber(config.pendingSize) or DEFAULT_PENDING_SIZE))
 self.musicGain=tonumber(config.musicGain) or DEFAULT_MUSIC_GAIN
 self.effectGain=tonumber(config.effectGain) or DEFAULT_EFFECT_GAIN
 self.scene=Scene()
 self.music=self.scene:CreateChild("Music"):CreateComponent("SoundSource")
 self.music:SetSoundType(SOUND_MUSIC)
 self.sounds={};self.cooldowns={};self.nextAt={};self.playing={};self.pending={}
 self.current="";self.clock=0;self.sequence=0
 self.stats={played=0,staggered=0,dropped=0,stolen=0}
 self.aliases=merge({victory="ui",defeat="alarm",tower_hit="hit",boss_spawn="boss",boss_buff="boss"},config.aliases)
 self.priorities=merge({boss_spawn=100,boss=90,boss_buff=90,explosion=80,alarm=70,death=60,hit=40,shot=20,electric=20,flame=20},config.priorities)
 self.gains=merge({shot=.2,boss=.5,boss_spawn=.5,boss_buff=.5},config.gains)
 self.cooldownDefaults=merge({shot=.16,electric=.16,flame=.16,boss=.36,boss_spawn=.36,boss_buff=.36},config.cooldowns)
 self.rules=config.rules or {}
 local prefix=config.poolName or "audio";local scene=self.scene;local count=0
 self.voices=makePool(config.pools,prefix..":voices",{prewarm=self.poolSize,limit=self.poolSize,
  create=function()
   count=count+1
   local source=scene:CreateChild("Effect"..count):CreateComponent("SoundSource")
   source:SetSoundType(SOUND_EFFECT)
   return {source=source,name="",key="",priority=0,sequence=0,index=0}
  end,
  reset=function(voice) voice.name="";voice.key="";voice.priority=0;voice.sequence=0;voice.index=0 end})
 self.pendingPool=makePool(config.pools,prefix..":pending",{prewarm=self.pendingSize,limit=self.pendingSize,
  create=function() return {name="",key="",priority=0,gain=0,falloff=1,panning=0,at=0} end,
  reset=function(record) record.sound=nil;record.name="";record.key="" end})
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

-- 取事件的播放规则：先按事件名，再按实际声音名；都没有时返回共享空规则。
function Kit:Rule(name,soundName)
 return self.rules[name] or self.rules[soundName] or EMPTY_RULE
end

-- 统计同一 key 仍在出声的音源数与等待起播的记录数，扫描范围是有界的播放表与等待表。
---@return integer,integer
function Kit:Count(key)
 local playing,waiting=0,0
 for _,voice in ipairs(self.playing) do if voice.key==key and voice.source:IsPlaying() then playing=playing+1 end end
 for _,record in ipairs(self.pending) do if record.key==key then waiting=waiting+1 end end
 return playing,waiting
end

-- 叠加衰减：同 key 每多一路仍在出声的音源，音量乘一次 falloff；falloff 为 1 时不扫描。
function Kit:Falloff(key,gain,falloff)
 if falloff>=1 then return gain end
 local playing=self:Count(key)
 return gain*falloff^playing
end

-- 把音源从稠密播放表交换移除，再放回音源池（池的 reset 清空槽位标记）。
---@param voice SumeruAudioVoice
function Kit:RecycleVoice(voice)
 local list=self.playing;local index=voice.index;local last=list[#list]
 list[index]=last;last.index=index;list[#list]=nil
 self.voices:Recycle(voice)
end

-- 从等待表交换移除第 index 条，再放回等待池（池的 reset 释放 Sound 引用）。
function Kit:RemovePending(index)
 local list=self.pending;local record=list[index]
 list[index]=list[#list];list[#list]=nil
 self.pendingPool:Recycle(record)
end

-- 为一次起播取音源：先从池取空闲音源，再复用已播完未回收的，最后只在新声音优先级严格更高时抢占最低优先级、最旧的一路。
---@param priority number
---@return SumeruAudioVoice?
function Kit:Acquire(priority)
 local voice=self.voices:Allocate()
 if voice then voice.index=#self.playing+1;self.playing[voice.index]=voice;return voice end
 ---@type SumeruAudioVoice?
 local candidate=nil
 for _,active in ipairs(self.playing) do
  if not active.source:IsPlaying() then return active end
  if not candidate or active.priority<candidate.priority
   or (active.priority==candidate.priority and active.sequence<candidate.sequence) then candidate=active end
 end
 if candidate and priority>candidate.priority then
  candidate.source:Stop();self.stats.stolen=self.stats.stolen+1
  return candidate
 end
 return nil
end

-- 在取到的音源上起播并原地写入槽位标记；取不到音源时计入吞掉次数。
---@param sound Sound
function Kit:Start(name,key,sound,priority,gain,panning)
 local voice=self:Acquire(priority)
 if not voice then self.stats.dropped=self.stats.dropped+1;return false end
 voice.source:SetFrequency(0)
 voice.source:Play(sound,0,gain,panning)
 self.sequence=self.sequence+1
 voice.name=name;voice.key=key;voice.priority=priority;voice.sequence=self.sequence
 self.stats.played=self.stats.played+1
 return true
end

-- 播放一条池化音效：force 直接起播；规则配了 gap 的同名声音按间隔错开排队，超过等待条数、推迟上限或同名上限就吞掉；其余沿用冷却限频。
function Kit:PlayEffect(name,options)
 options=options or {}
 if not self.settings.sfx then return false end
 local soundName=options.soundName or self.aliases[name] or name
 local path=self.effects[soundName]
 if not path then return false end
 local key=options.cooldownKey or (name=="boss_spawn" and "boss" or name)
 local force=options.force==true or name=="boss_spawn"
 local rule=self:Rule(name,soundName)
 local gap=not force and tonumber(rule.gap) or nil
 local limit=not force and tonumber(rule.voices) or nil
 if not force and not gap and (self.cooldowns[key] or 0)>0 then return false end
 local sound=self:Sound(path)
 if not sound then return false end
 local priority=tonumber(options.priority) or tonumber(rule.priority) or self.priorities[name] or self.priorities[soundName] or 10
 local gain=tonumber(options.gain) or tonumber(rule.gain) or self.gains[name] or self.gains[soundName] or self.effectGain
 local panning=tonumber(options.panning) or 0
 local falloff=tonumber(rule.falloff) or 1
 if gap or limit then
  local playing,waiting=self:Count(key)
  if limit and playing+waiting>=limit then self.stats.dropped=self.stats.dropped+1;return false end
  local at=gap and self.nextAt[key] or nil
  if gap and at and at>self.clock then
   if waiting>=(tonumber(rule.queue) or DEFAULT_QUEUE) or at-self.clock>(tonumber(rule.maxDelay) or DEFAULT_MAX_DELAY) then
    self.stats.dropped=self.stats.dropped+1;return false
   end
   local record=self.pendingPool:Allocate()
   if not record then self.stats.dropped=self.stats.dropped+1;return false end
   record.name=name;record.key=key;record.sound=sound;record.priority=priority
   record.gain=gain;record.falloff=falloff;record.panning=panning;record.at=at
   self.pending[#self.pending+1]=record
   self.nextAt[key]=at+gap;self.stats.staggered=self.stats.staggered+1
   return true
  end
 end
 if not self:Start(name,key,sound,priority,self:Falloff(key,gain,falloff),panning) then return false end
 if gap then self.nextAt[key]=self.clock+gap;return true end
 local duration=tonumber(options.cooldown)
 if duration==nil then duration=tonumber(rule.cooldown) or self.cooldownDefaults[name] or self.cooldownDefaults[soundName] or DEFAULT_COOLDOWN end
 self.cooldowns[key]=math.max(0,duration)
 return true
end

-- 兼容旧业务入口，统一转发到池化音效播放器。
function Kit:Effect(name,options) return self:PlayEffect(name,options) end

-- 查询指定事件音效是否仍在播放或等待错开起播，供业务等待一次性提示自然结束。
function Kit:IsEffectPlaying(name)
 for _,voice in ipairs(self.playing) do
  if voice.name==name and voice.source:IsPlaying() then return true end
 end
 for _,record in ipairs(self.pending) do if record.name==name then return true end end
 return false
end

-- 只停止指定事件的音效与其等待记录，保留其他音源与独立 BGM。
function Kit:StopEffect(name)
 for i=#self.playing,1,-1 do
  local voice=self.playing[i]
  if voice.name==name then voice.source:Stop();self:RecycleVoice(voice) end
 end
 for i=#self.pending,1,-1 do if self.pending[i].name==name then self:RemovePending(i) end end
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

-- 停止全部池化音效，回收全部音源与等待记录，并清空错开时刻。
function Kit:StopEffects()
 for i=#self.playing,1,-1 do
  local voice=self.playing[i];voice.source:Stop();self:RecycleVoice(voice)
 end
 for i=#self.pending,1,-1 do self:RemovePending(i) end
 for key in pairs(self.nextAt) do self.nextAt[key]=nil end
end

-- 推进时钟：倒数冷却，回收已播完的音源，并起播到点的错开记录；不创建临时播放对象。
function Kit:Update(dt)
 local elapsed=math.max(0,tonumber(dt) or 0)
 self.clock=self.clock+elapsed
 for key,remaining in pairs(self.cooldowns) do
  local nextRemaining=remaining-elapsed
  self.cooldowns[key]=nextRemaining>0 and nextRemaining or nil
 end
 for i=#self.playing,1,-1 do
  local voice=self.playing[i]
  if not voice.source:IsPlaying() then self:RecycleVoice(voice) end
 end
 local i=1
 while i<=#self.pending do
  local record=self.pending[i] --[[@as SumeruAudioPending]]
  if record.at<=self.clock then
   local name,key,sound,priority=record.name,record.key,record.sound,record.priority
   local gain,falloff,panning=record.gain,record.falloff,record.panning
   self:RemovePending(i)
   if sound then self:Start(name,key,sound,priority,self:Falloff(key,gain,falloff),panning) end
  else
   i=i+1
  end
 end
end

-- 返回音效调度统计快照（新表，供调试面板低频读取，不在每帧调用）。
function Kit:GetStats()
 local s=self.stats
 return {played=s.played,staggered=s.staggered,dropped=s.dropped,stolen=s.stolen,
  voices=#self.playing,voicePeak=self.voices:Stats().peak,pending=#self.pending,pendingPeak=self.pendingPool:Stats().peak}
end

-- 停止所有音频播放并清理池化状态。
function Kit:Stop()
 self:StopBGM();self:StopEffects();self.cooldowns={}
end

return Kit
