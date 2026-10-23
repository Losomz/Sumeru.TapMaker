-- 纯 Lua FSM：定义保留在模块中，运行记录可以直接序列化。
local F={}
-- 复制状态数据，避免恢复或创建时共享存档中的可变 table。
local function copy(value)
 if type(value)~="table" then return value end
 local result={};for k,v in pairs(value) do result[k]=copy(v) end;return result
end
-- 检查状态是否存在，错误定义在调用处立即暴露。
local function state(definitions,name)
 return assert(definitions[name],"Unknown FSM state: "..tostring(name))
end
-- 切换状态；重复切换不退出、不进入，也不重置已过时间。
function F.Change(definitions,record,name,data,context)
 local nextState=state(definitions,name)
 if record.state==name then return false end
 local previous=state(definitions,record.state)
 if previous.onExit then previous.onExit(record,context,name) end
 record.state=name;record.elapsed=0;record.revision=record.revision+1;record.data=copy(data or {})
 if nextState.onEnter then nextState.onEnter(record,context) end
 return true
end
-- 创建运行记录并执行首次进入回调。
function F.Create(definitions,name,data,context)
 local initial=state(definitions,name)
 local record={state=name,elapsed=0,revision=1,data=copy(data or {})}
 if initial.onEnter then initial.onEnter(record,context) end
 return record
end
-- 执行回调返回的转换；回调已经主动转换时不覆盖它。
local function dispatch(definitions,record,callback,context,...)
 if not callback then return end
 local revision=record.revision
 local name,data=callback(record,context,...)
 if name and record.revision==revision then F.Change(definitions,record,name,data,context) end
end
-- 分发事件；优先使用具名 events 回调，否则交给 onEvent。
function F.Send(definitions,record,event,payload,context)
 local current=state(definitions,record.state)
 local handler=current.events and current.events[event]
 if handler then dispatch(definitions,record,handler,context,payload)
 else dispatch(definitions,record,current.onEvent,context,event,payload) end
end
-- 推进模拟时间；零时间不触发更新，暂停由调用者停止步进。
function F.Update(definitions,record,dt,context)
 assert(type(dt)=="number" and dt==dt and dt>=0 and dt<math.huge,"Invalid FSM time step")
 if dt==0 then return end
 record.elapsed=record.elapsed+dt
 dispatch(definitions,record,state(definitions,record.state).onUpdate,context,dt)
end
-- 显式重置，允许同状态重新进入；与普通 Change 的幂等语义分开。
function F.Reset(definitions,record,name,data,context)
 local initial=state(definitions,name)
 local previous=state(definitions,record.state)
 if previous.onExit then previous.onExit(record,context,name) end
 record.state=name;record.elapsed=0;record.revision=record.revision+1;record.data=copy(data or {})
 if initial.onEnter then initial.onEnter(record,context) end
 return record
end
-- 恢复存档的精确进度，不执行进入或退出回调，也不恢复函数引用。
function F.Restore(definitions,snapshot)
 state(definitions,snapshot.state)
 assert(type(snapshot.elapsed)=="number" and snapshot.elapsed>=0 and snapshot.elapsed<math.huge,"Invalid FSM elapsed")
 assert(type(snapshot.revision)=="number" and snapshot.revision>=1 and snapshot.revision%1==0,"Invalid FSM revision")
 assert(type(snapshot.data)=="table","Invalid FSM data")
 return {state=snapshot.state,elapsed=snapshot.elapsed,revision=snapshot.revision,data=copy(snapshot.data)}
end
return F
