# PoolKit：对象池

`require("sumeru.toolkit.poolkit")` 返回对象池 System，参照 QFramework PoolKit。框架不引用业务模块，项目在架构上注册一次，业务经 `GetSystem("PoolKit")` 取用。

```lua
local PoolKit=require("sumeru.toolkit.poolkit")
local arch=Sumeru.Architecture.MakeArchitecture("my-game")
arch:RegisterSystem("PoolKit",PoolKit.new())

local pools=arch:GetSystem("PoolKit")

-- 数据记录：取出、填写、用完回收；reset 清空旧字段，避免串值。
local records=pools:Object("effects",{create=function() return {} end,reset=PoolKit.Wipe,prewarm=120})
local e=records:Allocate();e.kind="hit";e.age=0
records:Recycle(e)

-- 每帧重画的固定控件：初始化时一次性创建，每帧按顺序复用，未用到的自动隐藏。
local shapes=pools:Frame("shapes",{capacity=720,
 create=function(i) local node=UI.Panel{position="absolute",visible=false};parent:AddChild(node);return node end,
 hide=function(node) node:SetVisible(false) end})
shapes:Begin()
local node=shapes:Next() -- 容量用完时返回 nil
shapes:Finish()
```

## 两种池

| 类 | 适用 | 接口 |
|---|---|---|
| `ObjectPool` | 生命周期不定的对象：特效记录、实体动画播放器、带状态的视图槽位 | `Allocate` / `Recycle` / `Prewarm` / `Count` / `Clear` |
| `FramePool` | 每帧整体重画的固定容量对象：UI 图形、弹体精灵 | `Begin` / `Next` / `Finish` / `Used` / `Capacity` / `Clear` |

`ObjectPool.new` 的选项：

| 字段 | 说明 |
|---|---|
| `create()` | 必填，构造新对象 |
| `reset(obj)` | 回收时调用，清除上一次使用的状态；记录表可直接用 `PoolKit.Wipe` |
| `prewarm` | 初始化时预先创建的数量 |
| `limit` | 对象总数上限（含使用中）。达到上限后 `Allocate` 返回 nil，计入 `misses`；固定数量的控件池用它防止运行中新建控件 |
| `cache` | 空闲栈长度上限，超出的回收对象交给 GC；不设则全部保留 |

## PoolKit（System）

- `Object(name,options)`：按名称取或建 `ObjectPool`，选项只在首次创建时生效。跨页面长期存在的数据池用它。
- `Frame(name,options)`：新建 `FramePool` 并替换同名池。帧池绑定具体控件层，宿主重建后旧控件已经失效，所以总是重建。
- `Get(name)`、`Release(name)`：查询；注销并清空（隐藏帧池槽位、丢弃空闲对象）。池里的控件随宿主树释放，PoolKit 不销毁控件。
- `Stats()`：返回按名称排序的统计行，供调试面板低频读取。对象池给出 `created / active / free / peak / reused / misses`，帧池给出 `capacity / active / peak / overflow`。

## 约定

- 回收前断开对象对业务实体的引用，或在 `reset` 里清掉；同一对象重复 `Recycle` 会被忽略并返回 false。
- 池化对象不放进存档。存档数据保持纯表，池里只放显示层对象和短时记录。
- 只把明显重复分配的对象池化：每帧、每次命中、每次生成都会新建的才值得做。一次性创建的界面、低频弹窗不必入池。
- `Stats()` 每次返回新表，不要在每帧调用。
