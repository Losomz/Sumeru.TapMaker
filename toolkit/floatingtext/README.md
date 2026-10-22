# FloatingTextKit

`require("sumeru.toolkit.floatingtext")` 返回可独立实例化的飘字管理器。核心调度不引用游戏实体、货币、存档、场景或玩法随机数；默认渲染适配器使用 UrhoX UI。项目专用事件和样式放在 `game/` 中。

## 使用

```lua
local FloatingTextKit=require("sumeru.toolkit.floatingtext")
local floats=FloatingTextKit.new({
 parent=effectLayer,
 fontFamily="lv-ali-puhuiti-heavy",
 capacity=48,
 maxPerTarget=3,
 presets={
  damage={duration=.6,fontSize=14,color={249,230,207,255},
   mergeWindow=.1,spread=4,spreadY=2,rise=24,endScale=.9},
  income={duration=1,fontSize=17,color={255,200,37,255},prefix="+",rise=28},
 },
})

floats:Emit({preset="damage",value=28,x=180,y=160,mergeKey="enemy:7"})
floats:Emit({preset="income",value=44,x=180,y=400})
floats:Update(dt)
```

父容器需要有效尺寸。默认输入坐标与父层一致，动效和字号使用该层的逻辑像素。`project(x,y)` 可注入世界到显示层的投影；`unitScale` 统一换算字号、图标和动效位移，默认 1。项目当前世界宽 720，在 360 屏宽显示，因此配置 `unitScale=2`。投影只处理事件锚点，上浮与侧移保持等比。`visualScale` 默认 1，仅整体缩放文字、图标及阴影，不改变锚点、上浮距离和动画时长；项目当前为 `0.8`（整体缩小 20%）。

## 接口

| 方法 | 作用 |
|---|---|
| `Emit(event)` | 成功显示或合并返回 `true`；无效、无配额或优先级不足返回 `false` |
| `Update(dt)` | 唯一动画更新入口；零时间可刷新投影且不推进动画 |
| `Flush(groupKey)` | 将指定目标仍在等待汇总的数字立即显示，适用于目标死亡 |
| `Pause(bool)` | 冻结时间；恢复时不补算后台经过的时间 |
| `Clear()` | 清空显示与合并索引，保留槽位、控件和累计统计 |
| `GetStats()` | 返回容量、活动/可见/等待数、峰值、生成、合并、丢弃和替换次数 |
| `Destroy()` | 幂等释放本实例；在父容器销毁前调用 |

事件字段：`preset`、正数 `value`、锚点 `x/y`、可选 `mergeKey`、`groupKey`、`icon`、`flush`、`followKey`。Kit 复制标量，调用后可以复用事件表。`mergeKey` 只在同一预设内匹配；`groupKey` 默认使用 `mergeKey`，跨预设控制同一目标的同屏数量及死亡刷新。键使用稳定的字符串或数字。没有键的事件互不合并。

需要跟随主体时，事件传入稳定的 `followKey`，配置提供 `resolveAnchor(followKey)` 返回当前锚点 `x,y`。Kit 每次更新只查询活动槽位，不保存实体引用。主体消失时返回 `nil`，数字会在最后位置完成上浮淡出；没有 `followKey` 的收益提示保留入账位置。

预设字段：

- `pool / priority`：槽位分组与替换优先级。
- `duration / delay / mergeWindow`：显示时长、显示前的累计窗口、已显示数字允许合并的窗口，单位秒。持续伤害可配置 `delay=.2`、`mergeWindow=0`。
- `fontSize / color / prefix / suffix / icon / iconSize`：外观。图标通过 `icons={name={src="...sprite.json",frame="..."}}` 注入，和文字共用一个变换与透明度。
- `spread / spreadY`：出生时横、纵方向的随机偏移上限，使用实例私有随机序列；生成后固定，不逐帧抖动或横向漂移。
- `rise / offsetY / tilt`：上浮距离、额外垂直偏移和弹出倾斜。
- `startScale / peakScale / endScale / pop / settle / fadeAt`：弹出、回弹和随后缩小的曲线。`endScale` 默认 `0.9`，不缩到零；默认在回弹结束后逐渐淡出。时长、弹出和回弹阶段使用正数，`fadeAt` 在 0 至 1 之间。

可配置 `format(value,profile)` 返回不含前后缀的字符串；只在首次显示或合并后调用。等待累计时不排版，同一帧多次合并只在 `Update` 时绑定一次文字。默认不限制显示位置，出屏部分由宿主视口裁剪。其他宿主若明确需要屏内钳制，可以传入可选 `bounds={left,top,right,bottom}`；Last Vein 不传此配置。

## 配额与性能

不配置 `groups` 时建立 `default` 池，容量取 `capacity`，默认 48。分组时为预设指定 `pool`：

```lua
groups={
 {id="normal",capacity=36},
 {id="important",capacity=8},
 {id="income",capacity=4},
}
```

分组保留独立配额。池满后选择优先级不高于新事件的最低优先级、最旧槽位替换；没有可替换槽时丢弃新显示。达到单目标上限时同样优先保留重要反馈。丢弃只影响显示，绝不能作为业务结算成功或失败的依据。

初始化分配所有记录、姿态表、控件和空闲栈。活动表采用交换移除，分配与释放不搬移整段数组；合并按预设及目标索引查找，替换与目标计数只扫描有界活动表。等待累计的记录同样占配额，不存在无限待播放队列。

动画只有一个更新循环，不创建逐条定时器或 Player。每帧复用姿态表，只写自有节点的纯渲染属性；引擎渲染遍历直接读取这些属性，不经过每次都会标记 Yoga 布局脏的 `SetStyle`。尺寸与文字布局仍使用正式 API，仅在生成或合并时更新。外层定位、内层缩放，回弹不会放大整段世界位移。图标共用图集缓存，文字用单层硬阴影，不采用八方向描边或模糊光晕。框架内部的分配和 GPU 绘制次数仍由引擎决定，此处不承诺整个 UI 管线零分配。

## 可替换渲染器

通过 `renderer` 注入一个实现 `Create(slot)`、`Bind(slot)`、`Draw(slot,pose)`、`Hide(slot)`、`Destroy()` 的实例。`Bind` 在首次可见绘制前及可见内容变化后调用；等待累计时只会收到 `visible=false` 的 `Draw`。`pose` 是复用表，包含锚点、位移、缩放、角度、透明度和显隐；读取后不要修改或保存副本到异步任务。

当前 `UIRenderer` 采用整条池化 Label 和静态 Sprite，**没有实现专用 GPU 批量提交**。共享字体、图集或父层不等于一次 draw call，`GetStats()` 也不伪报绘制批次。后续有可验证的批量绘制接口时，只替换该适配器，不改变事件与调度接口。

## Last Vein 接入

- `game/feedback/DamageNumbers.lua`：统一结算入口记录扣血及护盾损失。固定 256 条收集记录，同目标同类别在消费前合并；普通记录最多使用前 248 个名额，保留重要反馈空间。收集器使用对局弱引用，不进入 Session 或存档。
- `game/ui/FloatingTextConfig.lua`：颜色、字体、容量、数字格式和图标。生命伤害按实际剩余 HP 限制显示值，不改已有伤害统计或战斗规则。
- `game/ui/FloatingFeedback.lua`：把结算记录与回收入账事件翻译成 Kit 输入；正式游戏和现有真实 1v1 共用。
- 普通伤害出生错位为横向 ±4、纵向 ±2 逻辑像素（360 屏宽），持续伤害横向 ±3，暴击 ±5。保留弹出，随后上浮、缩至 0.9 并淡出；合并不再追加放大脉冲。敌人数字通过复用索引跟随头顶，出屏不贴边，死亡后在最后位置结束。
- `Game:SyncEffects`：消费一次记录并推进动画，暂停传入零时间；换局清空显示，隐藏时丢弃待消费反馈。
- 矿物完全回到停靠点后实际入账，同时生成原物品图标和 `+金额`。移除了旧的 120 个回收精灵池及重复动画。
- 暴击样式可直接使用 `critical` 预设。正式伤害入口的末尾可选 `feedback={critical=true}` 只携带已判定的暴击结果；调用者仍负责计算伤害及将标记传递至弹体命中。现有玩法未新增暴击率或暴击倍率。

本次实现尚未运行预览、性能测量或自动化测试。
