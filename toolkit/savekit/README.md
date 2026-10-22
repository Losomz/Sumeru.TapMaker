# 通用存档 Kit

`require("sumeru.toolkit.savekit")` 返回通用存档管理器。Kit 负责读写后端、JSON 编解码、版本判断以及按结构合并。业务层只声明一份带默认值的数据结构。

```lua
local SaveKit=require("sumeru.toolkit.savekit")
local list,map=SaveKit.list,SaveKit.map

local schema={
    player={crystal=0,research=map(0),slots=list(false)},
    run={wave=1,gold=0,towers=list({kind="basic",level=1,lines=map(0)})},
}

local kit=SaveKit.new({key="game.json",version=1,schema=schema,codec=cjson,backend="local"})
kit:Load(function(data,isNew) --[[ data 一定是完整结构 ]] end)
kit:Save(data)
```

## 结构声明

- 普通值：默认值同时规定类型，如 `gold=0`、`guide="grab"`、`active=false`。
- 嵌套表：作为记录，按字段逐层合并。
- `SaveKit.list(item)`：数组，每个元素都按 `item` 合并。
- `SaveKit.map(item)`：任意键的表，每个值都按 `item` 合并。
- `SaveKit.build(decl)`：按声明新建一份默认数据，业务重置某个分区时使用。

## 读档规则

- 先按结构建一份默认数据，再用存档里同名且同类型的字段覆盖。
- 结构里没有的字段直接丢弃，类型不同的字段保留默认值。
- 没有存档、JSON 解析失败或版本号不同，都直接返回默认数据，`isNew=true`。
- Kit 不做迁移。结构改变、旧档无法直接套用时，把 `version` 加一，旧档整份按新档处理。
- JSON 不区分整数与小数，解码后值为整数的数字统一还原为 integer。

## 写档

- `Save(data)` 先按结构投影再写出，根节点的 `version` 由 Kit 写入。结构外的字段不会写进存档，所以业务对象可以同时挂存档字段和运行字段，直接拿去保存。
- 内容与上次写出的相同时不重复写。
- 写入失败只打印一次日志、返回 `false`，下一次保存继续尝试，不影响游戏。

## 与框架 Model 配合

推荐把 Kit 注册为 System，再由业务的 Model 持有读出的数据。框架初始化时读一次，之后业务直接修改 Model，保存时把 Model 整份交给 Kit：

```lua
arch:RegisterSystem("SaveKit",function() return SaveKit.new{...} end)
arch:RegisterModel("GameModel",function() return GameModel.new() end)
arch:GetModel("GameModel"):Load(function() --[[ 数据到位后再创建业务 ]] end)
```

Model 内部通过 `self:GetSystem("SaveKit")` 存取，不直接接触文件或云端。

## 后端

- `local`：引擎沙箱内的单个文件，读取完成后同步回调。
- 云端：尚未实现，传入未登记的后端名会直接报错，不会静默换成本地存储。
- 新后端只需实现 `read(key,done)` 和 `write(key,text)`，然后登记到 `SaveKit.lua` 的 `BACKENDS`。云端读取是异步的，所以 `Load` 统一使用回调，业务层不用改。
