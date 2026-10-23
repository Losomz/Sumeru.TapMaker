-- 通用资源分包下载 toolkit：按名字登记资源包，按需确保就绪，空闲时在后台顺序预取。
---@class SumeruLoadPack
---@field name string
---@field refs string[]
---@field state string
---@field done integer
---@field total integer
---@field failed integer
---@field token integer
---@field group integer

---@class SumeruLoadRequest
---@field names string[]
---@field packs SumeruLoadPack[]
---@field handlers table
---@field done boolean

---@class SumeruLoadKit
---@field packs table<string,SumeruLoadPack>
---@field requests SumeruLoadRequest[]
---@field queue string[]
---@field prefetching SumeruLoadPack|false
---@field lastFailed SumeruLoadRequest|false
local Kit={};Kit.__index=Kit

-- 创建独立的分包下载实例；资源清单由业务层注入。
function Kit.new()
 local self=setmetatable({},Kit);self:init();return self
end

-- 初始化资源包表、等待中的请求和后台预取队列。
function Kit:init()
 self.packs={};self.requests={};self.queue={}
 self.prefetching=false;self.lastFailed=false
end

-- 登记或替换一个资源包；同包内重复路径只保留一份。
function Kit:Define(name,refs)
 local seen={};local list={}
 for _,path in ipairs(refs or {}) do
  if not seen[path] then seen[path]=true;list[#list+1]=path end
 end
 self.packs[name]={name=name,refs=list,state="idle",done=0,total=#list,failed=0,token=0,group=0}
end

-- 取消进行中的下载并清空请求与预取队列；之后到达的回调全部丢弃。
function Kit:Stop()
 for _,pack in pairs(self.packs) do
  if pack.state=="loading" then
   pack.token=pack.token+1;pack.state="idle"
   if pack.group>0 then cache:CancelDownloadGroup(pack.group) end
  end
 end
 self.requests={};self.queue={};self.prefetching=false;self.lastFailed=false
end

-- 查询资源包是否已全部下载完成。
function Kit:IsReady(name)
 local pack=self.packs[name]
 return pack~=nil and pack.state=="ready"
end

-- 确保若干资源包就绪：已全部就绪时同步回调 onReady，否则下载缺失的包并汇总进度。
---@param names string[]
---@param handlers? {onReady:fun()?, onProgress:fun(completed:integer,total:integer)?, onFail:fun(failedCount:integer)?}
function Kit:Ensure(names,handlers)
 handlers=handlers or {}
 ---@type SumeruLoadRequest
 local req={names=names,packs={},handlers=handlers,done=false}
 for _,name in ipairs(names) do
  local pack=assert(self.packs[name],"Unknown load pack: "..tostring(name))
  if pack.state~="ready" then req.packs[#req.packs+1]=pack end
 end
 if #req.packs==0 then
  if handlers.onReady then handlers.onReady() end
  return
 end
 print("[LoadKit] Ensure "..table.concat(names,","))
 self.requests[#self.requests+1]=req
 for _,pack in ipairs(req.packs) do
  if pack.state~="loading" then self:Start(pack) end
 end
 if not req.done then self:Report(req) end
end

-- 追加后台预取；只在没有 Ensure 等待时启动，每次只下载一个包。
---@param names string[]
function Kit:Prefetch(names)
 for _,name in ipairs(names) do
  if self.packs[name] then self.queue[#self.queue+1]=name end
 end
 self:Pump()
end

-- 重放最近一次失败的 Ensure 请求。
function Kit:Retry()
 local req=self.lastFailed
 if not req then return false end
 self.lastFailed=false
 self:Ensure(req.names,req.handlers)
 return true
end

-- 开始下载单个资源包；旧回调通过 token 丢弃。
---@param pack SumeruLoadPack
function Kit:Start(pack)
 pack.token=pack.token+1;local token=pack.token
 pack.state="loading";pack.done=0;pack.total=#pack.refs;pack.failed=0
 if #pack.refs==0 then return self:Finish(pack,true,0) end
 print("[LoadKit] Start "..pack.name.." ("..#pack.refs.." refs)")
 pack.group=cache:DownloadResources(pack.refs,function(success,failedCount)
  if pack.token~=token then return end
  self:Finish(pack,success,failedCount)
 end,function(completed,total)
  if pack.token~=token then return end
  pack.done=completed;pack.total=math.max(total,1)
  self:Progress(pack)
 end)
end

-- 资源包下载结束：更新状态，结算相关请求，再继续后台预取。
---@param pack SumeruLoadPack
function Kit:Finish(pack,success,failedCount)
 pack.state=success and "ready" or "failed";pack.failed=success and 0 or (failedCount or 0)
 if success then pack.done=pack.total end
 print("[LoadKit] "..pack.name.." ready="..tostring(success).." failed="..tostring(pack.failed))
 if self.prefetching==pack then self.prefetching=false end
 local pending={}
 for _,req in ipairs(self.requests) do pending[#pending+1]=req end
 for _,req in ipairs(pending) do self:Settle(req) end
 self:Pump()
end

-- 请求的全部包都结束后回调；任一包失败则记为可重试的失败请求。
---@param req SumeruLoadRequest
function Kit:Settle(req)
 if req.done then return end
 local failed,loading=0,false
 for _,pack in ipairs(req.packs) do
  if pack.state=="loading" then loading=true elseif pack.state=="failed" then failed=failed+math.max(1,pack.failed) end
 end
 if loading then return self:Report(req) end
 req.done=true
 for i=#self.requests,1,-1 do if self.requests[i]==req then table.remove(self.requests,i) end end
 if failed>0 then
  self.lastFailed=req
  if req.handlers.onFail then req.handlers.onFail(failed) end
 elseif req.handlers.onReady then req.handlers.onReady() end
end

-- 单包进度变化时刷新包含它的请求。
---@param pack SumeruLoadPack
function Kit:Progress(pack)
 for _,req in ipairs(self.requests) do
  for _,p in ipairs(req.packs) do
   if p==pack then self:Report(req);break end
  end
 end
end

-- 汇总请求内各包的已完成数与总数并回调进度。
---@param req SumeruLoadRequest
function Kit:Report(req)
 if not req.handlers.onProgress then return end
 local completed,total=0,0
 for _,pack in ipairs(req.packs) do completed=completed+pack.done;total=total+pack.total end
 req.handlers.onProgress(completed,math.max(total,1))
end

-- 有 Ensure 等待时让路；否则取队列中下一个未就绪的包在后台下载。
function Kit:Pump()
 if self.prefetching or #self.requests>0 then return end
 while #self.queue>0 do
  local pack=self.packs[table.remove(self.queue,1)]
  if pack and pack.state~="ready" and pack.state~="loading" then
   self.prefetching=pack
   self:Start(pack)
   return
  end
 end
end

return Kit
