-- sumeru framework 门面：require("sumeru.framework") 返回核心设施集合。
local Architecture=require("sumeru.framework.Architecture")
local Container=require("sumeru.framework.Container")
local TypeEvent=require("sumeru.framework.TypeEvent")
local Bindable=require("sumeru.framework.Bindable")

return {
 Architecture=Architecture,
 Container=Container,
 TypeEvent=TypeEvent,
 Bindable=Bindable,
}
