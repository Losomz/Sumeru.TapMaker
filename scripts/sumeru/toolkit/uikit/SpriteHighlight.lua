-- 运行时受击提亮：复用当前帧和原纹理 Alpha，不创建遮罩图片、纹理或控件。
local Sprite=require("urhox-libs/UI/Widgets/Sprite")
local Cache=require("urhox-libs/UI/Core/ImageCache")
local H={}
-- 在原精灵之上做一次加色绘制；独立保存混合状态，避免影响场景和后续 UI。
local function render(self,vg)
 Sprite.Render(self,vg)
 local amount=self.hitHighlight or 0;if amount<=0 then return end
 local sheet=self:GetSheet();if not sheet then return end
 local index=self:GetCurrentFrame();local frame=sheet:GetFrame(index);if not frame then return end
 local path,iw,ih=sheet:GetPageForFrame(index);if not path or iw<=0 or ih<=0 then return end
 local image=Cache.Get(path);if not image or image==0 then return end
 local l=self:GetAbsoluteLayout();local src=frame.sourceSize;local r=frame.frame;local offset=frame.offset
 if l.w<=0 or l.h<=0 or src.w<=0 or src.h<=0 then return end
 local sx,sy=l.w/src.w,l.h/src.h;local fit=self.props.objectFit
 if fit=="contain" then sx=math.min(sx,sy);sy=sx
 elseif fit=="cover" then sx=math.max(sx,sy);sy=sx
 elseif fit=="none" then sx=1;sy=1 end
 local px,py=self:ResolveObjectPos_()
 local bx,by=l.x+(l.w-src.w*sx)*px,l.y+(l.h-src.h*sy)*py
 local flipX,flipY=self.props.flipX,self.props.flipY
 local x=bx+(flipX and src.w-offset.x-r.w or offset.x)*sx
 local y=by+(flipY and src.h-offset.y-r.h or offset.y)*sy
 local w,h=r.w*sx,r.h*sy
 nvgSave(vg);nvgIntersectScissor(vg,l.x,l.y,l.w,l.h)
 -- RGB 加亮，目标 Alpha 保持原值；透明像素不会改变背景。
 nvgGlobalCompositeBlendFuncSeparate(vg,NVG_ONE,NVG_ONE,NVG_ZERO,NVG_ONE)
 local ox,oy=x-r.x*sx,y-r.y*sy
 if flipX or flipY then
  nvgTranslate(vg,flipX and x+w or x,flipY and y+h or y)
  nvgScale(vg,flipX and -1 or 1,flipY and -1 or 1)
  ox,oy=-r.x*sx,-r.y*sy;x,y=0,0
 end
 nvgBeginPath(vg);nvgRect(vg,x,y,w,h)
 nvgFillPaint(vg,nvgImagePattern(vg,ox,oy,iw*sx,ih*sy,0,image,math.min(1,amount)))
 nvgFill(vg);nvgRestore(vg)
end
-- 每个 Sprite 只接入一次，切帧、旋转、缩放和透明度继续交由官方组件处理。
function H.Attach(sprite)
 sprite.hitHighlight=0;sprite.Render=render;return sprite
end
-- 采样器只传入当前强度；重置到零立即停止额外绘制。
function H.Set(sprite,amount) sprite.hitHighlight=math.max(0,math.min(1,amount or 0)) end
return H
