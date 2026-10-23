-- 池化整条 Label 的渲染适配器；共用字体与图集，不把共享纹理宣称为合批。
local UI=require("urhox-libs/UI")
---@class SumeruFloatingTextRenderer
---@field unit number
---@field width number
---@field height number
---@field icons table<string,{src:string,frame:string}>
---@field config {fontFamily:string?,format:function?,project:function?,bounds:{left:number,right:number,top:number,bottom:number}?,visualScale:number?}
local Renderer={};Renderer.__index=Renderer
-- 创建单一显示层，样式与坐标投影由宿主传入。
---@return SumeruFloatingTextRenderer
function Renderer.new(config)
 local self=setmetatable({config=config,unit=config.unitScale or 1,icons=config.icons or {},sheets={}},Renderer)
 self.width=(config.width or 112)*self.unit;self.height=(config.height or 32)*self.unit
 self.root=UI.Panel{position="absolute",left=0,top=0,width=config.layerWidth or "100%",height=config.layerHeight or "100%",
  pointerEvents="none",overflow="visible",backgroundColor={0,0,0,0}}
 assert(config.parent,"FloatingTextKit UI renderer needs a parent"):AddChild(self.root)
 for _,icon in pairs(self.icons) do
  if not self.sheets[icon.src] then self.sheets[icon.src]=UI.SpriteSheet.Load(icon.src) end
 end
 return self
end
-- 外层只定位，内层缩放回弹，避免缩放连同整段世界位移一起放大。
function Renderer:Create(slot)
 local u=self.unit
 local root=UI.Panel{position="absolute",left=0,top=0,width=self.width,height=self.height,
  pointerEvents="none",visible=false,transformOrigin="center",backgroundColor={0,0,0,0}}
 local visual=UI.Panel{position="absolute",left=0,top=0,width=self.width,height=self.height,
  pointerEvents="none",transformOrigin="center",backgroundColor={0,0,0,0}}
 local label=UI.Label{position="absolute",left=0,top=0,width=self.width,height=self.height,
  text="",fontFamily=self.config.fontFamily or "sans",fontWeight="normal",fontSize=14*u,
  textAlign="center",verticalAlign="middle",whiteSpace="nowrap",lineHeight=1,pointerEvents="none",
  textShadow={offsetX=u,offsetY=u,blur=0,color={19,19,19,230}}}
 local icon=UI.Sprite{position="absolute",left=0,top=0,width=18*u,height=18*u,
  autoPlay=false,objectFit="contain",pointerEvents="none",visible=false}
 for path,sheet in pairs(self.sheets) do icon:AddAnimation(path,sheet) end
 visual:AddChild(icon);visual:AddChild(label);root:AddChild(visual);self.root:AddChild(root)
 slot.view={root=root,visual=visual,label=label,icon=icon}
end
-- 首次显示或合并后才格式化和测宽，图标与数字作为一个居中组合。
function Renderer:Bind(slot)
 local v=slot.view;local p=slot.profile;local u=self.unit
 local formatter=self.config.format
 local value=formatter and formatter(slot.value,p) or string.format("%.0f",slot.value)
 local text=(p.prefix or "")..value..(p.suffix or "")
 if v.text~=text or v.profile~=p or v.iconId~=slot.icon then
  local size=(p.fontSize or 14)*u
  local width=UI.MeasureTextWidth(text,UI.Theme.FontSize(size),self.config.fontFamily or "sans")
  if width<=0 then width=#text*size*.6 end
  local def=self.icons[slot.icon];local iconSize=def and (p.iconSize or 18)*u or 0
  local gap=def and 3*u or 0;width=math.min(self.width-iconSize-gap,width+2*u)
  local left=(self.width-width-iconSize-gap)/2
  v.label:SetText(text)
  v.label:SetStyle({left=left+iconSize+gap,width=width,fontSize=size,fontColor=p.color or {255,255,255,255}})
  v.icon:SetVisible(def~=nil)
  if def then
   v.icon:GotoFrameKey(def.frame)
   v.icon:SetStyle({left=left,top=(self.height-iconSize)/2,width=iconSize,height=iconSize})
  end
  v.text=text;v.profile=p;v.iconId=slot.icon
 end
end
-- 直接更新渲染属性避免标脏 Yoga；视觉倍率只缩放文字、图标和阴影，不改变锚点与位移。
function Renderer:Draw(slot,pose)
 local v=slot.view;v.root:SetVisible(pose.visible)
 if not pose.visible then return end
 local x,y=pose.x,pose.y
 if self.config.project then x,y=self.config.project(x,y) end
 x=x+pose.dx*self.unit;y=y+pose.dy*self.unit
 local bounds=self.config.bounds
 if bounds then
  local half=self.width/2;local height=self.height/2
  x=math.max(bounds.left+half,math.min(bounds.right-half,x))
  y=math.max(bounds.top+height,math.min(bounds.bottom-height,y))
 end
 local position=v.root.props;local visual=v.visual.props
 position.translateX=x-self.width/2;position.translateY=y-self.height/2
 visual.scale=pose.scale*(self.config.visualScale or 1);visual.rotate=pose.rotate;visual.opacity=pose.opacity
end
-- 回收时隐藏整个组，保留字体和图集缓存。
function Renderer:Hide(slot) slot.view.root:SetVisible(false) end
-- 释放 Kit 自己的显示层，父层仍由宿主管理。
function Renderer:Destroy()
 if self.root then self.root:Destroy();self.root=nil end
 self.config=nil;self.icons=nil;self.sheets=nil
end
return Renderer
