-- sumeru 类型事件总线：按事件 key 订阅/派发，支持对象级批量解绑。
-- 对应 QFramework 的 TypeEventSystem；Lua 无泛型，用字符串 key 代替事件类型。
---@class SumeruTypeEvent
---@field handlers_ table<string,SumeruEventHandler[]>
local TypeEvent={}
TypeEvent.__index=TypeEvent

-- 创建空总线。
---@return SumeruTypeEvent
function TypeEvent.new()
 local self=setmetatable({},TypeEvent)
 self.handlers_={}
 return self
end

-- 订阅事件：On(key, fn) 或 On(key, owner, fn)。
-- 带 owner 的订阅可被 OffAll(owner) 批量解绑；fn 建议用闭包捕获 owner 自身。
function TypeEvent:On(key,a,b)
 local owner,fn
 if b==nil then owner=false;fn=a else owner=a;fn=b end
 if type(fn)~="function" then error("[sumeru] TypeEvent:On 需要 function 处理器",2) end
 local list=self.handlers_[key]
 if not list then list={};self.handlers_[key]=list end
 list[#list+1]={owner=owner,fn=fn}
end

-- 解绑指定订阅（owner 与 fn 需与 On 时一致）。
function TypeEvent:Off(key,a,b)
 local owner,fn
 if b==nil then owner=false;fn=a else owner=a;fn=b end
 local list=self.handlers_[key]
 if not list then return end
 for i=#list,1,-1 do
  if list[i].owner==owner and list[i].fn==fn then table.remove(list,i) end
 end
 if #list==0 then self.handlers_[key]=nil end
end

-- 解绑某 owner 通过 On(key, owner, fn) 注册过的全部事件。
function TypeEvent:OffAll(owner)
 for key,list in pairs(self.handlers_) do
  for i=#list,1,-1 do
   if list[i].owner==owner then table.remove(list,i) end
  end
  if #list==0 then self.handlers_[key]=nil end
 end
end

-- 派发事件：快照遍历并校验订阅仍存活，允许回调中增删订阅。
function TypeEvent:Fire(key,...)
 local list=self.handlers_[key]
 if not list then return end
 local snapshot={}
 for i=1,#list do snapshot[i]=list[i] end
 for i=1,#snapshot do
  local h=snapshot[i]
  local alive=false
  local current=self.handlers_[key]
  if current then
   for j=1,#current do if current[j]==h then alive=true;break end end
  end
  if alive then h.fn(...) end
 end
end
return TypeEvent

---@class SumeruEventHandler
---@field owner any
---@field fn fun(...:any)
