# FSM kit

`require("sumeru.toolkit.fsm")` 返回纯 Lua API，不依赖 UI 或引擎。

| API | 参数与作用 |
| --- | --- |
| Create | `(definitions, initialState, data?, context?)` 创建并进入状态 |
| Change | `(definitions, record, state, data?, context?)` 转换；同状态不重启 |
| Send | `(definitions, record, event, payload?, context?)` 分发事件 |
| Update | `(definitions, record, dt, context?)` 推进时间并调用更新 |
| Reset | `(definitions, record, initialState, data?, context?)` 显式退出并重新进入 |
| Restore | `(definitions, snapshot)` 复制进度，不调用进入/退出 |

状态支持 `onEnter(record, context)`、`onExit(record, context, nextState)`、
`onUpdate(record, context, dt)`、`onEvent(record, context, event, payload)`，
或 `events[event](record, context, payload)`。更新/事件回调可返回
`nextState, nextData`；回调中主动 Change 后，返回值不再覆盖该转换。

```lua
local FSM=require("sumeru.toolkit.fsm")
local definitions={
 idle={events={start=function() return "working" end}},
 working={onUpdate=function(record)
  if record.elapsed>=1 then return "idle" end
 end},
}
local record=FSM.Create(definitions,"idle")
FSM.Send(definitions,record,"start")
FSM.Update(definitions,record,.25)
local restored=FSM.Restore(definitions,record)
```

记录仅含 `state / elapsed / revision / data`。状态数据应为无循环引用的可序列化值；
定义和 context 不写入记录。修订号只在转换或显式 Reset 时增加。
暂停时不调用 Update（或传 0）。优先级、终止状态、动画、命中时机由业务定义。
