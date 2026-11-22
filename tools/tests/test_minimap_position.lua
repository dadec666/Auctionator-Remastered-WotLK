dofile("AuctionatorRemastered/Remastered/Core/Bootstrap.lua")
dofile("AuctionatorRemastered/Remastered/Integration/LegacyBridge.lua")
local f=assert(io.open('AuctionatorRemastered/Remastered/UI/Launcher.lua'));local s=f:read('*a');f:close()
local shapesStart = assert(s:find("local minimapShapes%s*="))
local posStart = assert(s:find("local function positionIcon", shapesStart, true))
assert(loadstring(s:sub(shapesStart, posStart - 1)))()
local checks=0
local function check(v,msg) checks=checks+1;assert(v,msg) end
for _,size in ipairs({{140,140},{220,160},{80,180}}) do
 local width,height=unpack(size)
 for degrees=0,355,5 do
  local x,y=Atr_BrowserMinimapOffset(math.rad(degrees),width,height,'SQUARE')
  local edge=math.max(math.abs(x)/(width/2-7),math.abs(y)/(height/2-7))
  check(math.abs(edge-1)<1e-9,'square/rectangular icon follows the inset edge at '..degrees)
  x,y=Atr_BrowserMinimapOffset(math.rad(degrees),width,height,'ROUND')
  check(math.abs((x/(width/2+10))^2+(y/(height/2+10))^2-1)<1e-9,'round icon stays on its ellipse')
 end
end
local x,y=Atr_BrowserMinimapOffset(math.rad(-45),140,140,'CORNER-TOPLEFT')
check(math.abs(x*x+y*y-80*80)<1e-7,'shape-designated round quadrant retains outside radius')
x,y=Atr_BrowserMinimapOffset(math.rad(45),140,140,'CORNER-TOPLEFT')
check(math.abs(x-63)<1e-9 and math.abs(y-63)<1e-9,'square quadrant uses inset instead of outside radius')
x,y=Atr_BrowserMinimapOffset(0,nil,0,'UNKNOWN')
check(x==80 and y==0,'unavailable size/shape falls back safely')
print('PASS: '..checks..' minimap edge, shape and size checks')
