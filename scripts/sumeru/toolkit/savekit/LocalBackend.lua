-- 本地文件后端：在引擎沙箱内读写单个文件，读取完成后立即回调。
local B={};B.__index=B

-- 创建本地后端，不持有状态。
function B.new() return setmetatable({},B) end

-- 读取文件文本交给 done；文件不存在或打不开时回调 nil。
function B:read(key,done)
 if not fileSystem:FileExists(key) then return done(nil) end
 local f=File(key,FILE_READ)
 if not f:IsOpen() then return done(nil) end
 local text=f:ReadString();f:Close()
 done(text)
end

-- 覆盖写出整份文本，返回是否写入成功。
function B:write(key,text)
 local f=File(key,FILE_WRITE)
 if not f:IsOpen() then return false end
 local ok=f:WriteString(text);f:Close()
 return ok==true
end

return B
