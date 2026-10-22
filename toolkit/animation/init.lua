-- 动画 toolkit 公开入口，不依赖引擎、UI 或任何敌人定义。
return {
 Animation=require("sumeru.toolkit.animation.Animation"),
 SequenceAnimation=require("sumeru.toolkit.animation.SequenceAnimation"),
 HitFeedbackAnimation=require("sumeru.toolkit.animation.HitFeedbackAnimation"),
 Player=require("sumeru.toolkit.animation.Player"),
}
