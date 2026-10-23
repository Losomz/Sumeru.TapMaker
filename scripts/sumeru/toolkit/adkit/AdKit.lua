-- 激励视频适配层：统一 Maker sdk 的异步回调、忙状态与失败兜底。
---@class SumeruAdKit
---@field sdk table?
---@field busy boolean
---@field simulate boolean
local Kit={};Kit.__index=Kit

function Kit.new(config)
 local self=setmetatable({},Kit);self:init(config);return self
end

-- simulate=true 时不调用宿主广告，直接按完整观看回调，只给本地开发走通奖励链路。
function Kit:init(config)
 config=config or {};self.sdk=config.sdk;self.busy=false;self.simulate=config.simulate==true
end

function Kit:IsBusy() return self.busy end
-- 模拟模式总是可请求；正式环境需要宿主提供广告接口。
function Kit:CanRequest() return not self.busy and (self.simulate or self.sdk~=nil and type(self.sdk.ShowRewardVideoAd)=="function") end

-- 完整观看才把 success 交给业务；返回 false 且没有回调时也必须收尾一次。模拟模式立即按成功回调。
function Kit:ShowRewardVideo(done)
 if self.busy then return false,"广告正在播放" end
 self.busy=true
 local finished=false
 local function finish(result)
  if finished then return end
  finished=true;self.busy=false
  if done then done(type(result)=="table" and result or {success=false,msg="广告暂不可用"}) end
 end
 if self.simulate then
  print("[AdKit] 本地开发模拟激励广告：按完整观看发放")
  finish({success=true,msg="local simulate"});return true
 end
 if not self.sdk or type(self.sdk.ShowRewardVideoAd)~="function" then finish({success=false,msg="当前平台不支持广告"});return false end
 local ok,accepted=pcall(function() return self.sdk:ShowRewardVideoAd(finish) end)
 if not ok then finish({success=false,msg="广告暂不可用"});return false end
 if accepted==false then finish({success=false,msg="广告暂不可用"});return false end
 return true
end

return Kit
