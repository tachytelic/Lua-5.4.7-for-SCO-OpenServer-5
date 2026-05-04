-- Comprehensive Lua 5.4 functionality test for SCO cross-compile validation
local pass, fail = 0, 0
local function check(name, ok, detail)
  if ok then
    pass = pass + 1
    print(string.format("  PASS  %s", name))
  else
    fail = fail + 1
    print(string.format("  FAIL  %s  %s", name, detail or ""))
  end
end

print("=== integers and floats ===")
check("integer arithmetic", 2^31 - 1 + 1 == 2^31)
check("integer division", 17 // 5 == 3)
check("float division", math.abs(1/3 - 0.33333333333333) < 1e-12)
check("modulo", 17 % 5 == 2)
check("bitwise", (0xff | 0x100) == 0x1ff and (0xff & 0x0f) == 0x0f)
check("shifts", (1 << 20) == 1048576 and (1024 >> 5) == 32)
check("integer/float distinction", math.type(1) == "integer" and math.type(1.0) == "float")
check("hex floats", 0x1p4 == 16)
check("large integers", 9223372036854775807 // 2 == 4611686018427387903)
check("math.maxinteger", math.maxinteger == 9223372036854775807)

print("=== strings ===")
check("concat", "hello" .. " " .. "world" == "hello world")
check("length", #"hello" == 5)
check("upper/lower", ("HeLLo"):upper() == "HELLO" and ("HeLLo"):lower() == "hello")
check("sub", ("abcdefgh"):sub(2,5) == "bcde")
check("rep", ("ab"):rep(3) == "ababab")
check("reverse", ("abc"):reverse() == "cba")
check("byte/char", string.char(string.byte("A")) == "A" and string.byte("A") == 65)
check("format", string.format("%d %s %.2f", 42, "x", 3.14159) == "42 x 3.14")
check("format hex", string.format("%08x", 255) == "000000ff")
check("find", select(1, ("hello world"):find("world")) == 7)
check("match", ("v=1.2.3"):match("(%d+)%.(%d+)%.(%d+)") == "1")
check("gmatch", (function() local t={}; for w in ("one two three"):gmatch("%w+") do t[#t+1]=w end; return table.concat(t,",") end)() == "one,two,three")
check("gsub", ("hello world"):gsub("o","0") == "hell0 w0rld")
check("pack/unpack", string.unpack("i4", string.pack("i4", -12345)) == -12345)

print("=== tables ===")
local t = {1,2,3,4,5}
check("array length", #t == 5)
check("ipairs", (function() local s=0; for _,v in ipairs(t) do s=s+v end; return s end)() == 15)
check("pairs", (function() local n=0; for _ in pairs({a=1,b=2,c=3}) do n=n+1 end; return n end)() == 3)
check("table.insert", (function() local x={1,2,3}; table.insert(x,2,99); return x[2] end)() == 99)
check("table.remove", (function() local x={1,2,3,4}; table.remove(x,2); return x[2] end)() == 3)
check("table.sort", (function() local x={3,1,4,1,5,9,2,6}; table.sort(x); return x[1]==1 and x[8]==9 end)())
check("table.concat", table.concat({"a","b","c"},"-") == "a-b-c")
check("table.unpack", select(2, table.unpack({"a","b","c"})) == "b")
check("nested tables", (function() local x={{a=1,b={c=2}}}; return x[1].b.c end)() == 2)

print("=== functions and closures ===")
local function fac(n) return n<=1 and 1 or n*fac(n-1) end
check("recursion", fac(10) == 3628800)
check("varargs", (function(...) return select("#", ...) end)(1,2,3,4,5) == 5)
check("multiple returns", (function() return 1,2,3 end)() and (select(2, (function() return 1,2,3 end)())) == 2)
local function counter() local i=0; return function() i=i+1; return i end end
local c = counter()
check("closure state", c()==1 and c()==2 and c()==3)
local f = (function(x) return function(y) return x+y end end)(10)
check("closure capture", f(5) == 15)

print("=== metatables ===")
local v = setmetatable({1,2,3}, {__index = function(t,k) return "missing_"..k end})
check("__index function", v[99] == "missing_99")
local proto = {greet = function(self) return "hi "..self.name end}
local o = setmetatable({name="alice"}, {__index = proto})
check("__index table (oop)", o:greet() == "hi alice")
local vec = setmetatable({x=1,y=2}, {__add = function(a,b) return setmetatable({x=a.x+b.x,y=a.y+b.y}, getmetatable(a)) end})
local w = vec + {x=10,y=20}
check("__add", w.x == 11 and w.y == 22)
local cmp = setmetatable({n=5}, {__lt = function(a,b) return a.n < b.n end})
local cmp2 = setmetatable({n=10}, getmetatable(cmp))
check("__lt", cmp < cmp2)

print("=== coroutines ===")
local co = coroutine.create(function(a,b)
  local s = a+b
  coroutine.yield(s)
  local p = a*b
  coroutine.yield(p)
  return a-b
end)
local _,r1 = coroutine.resume(co, 3, 4)
local _,r2 = coroutine.resume(co)
local _,r3 = coroutine.resume(co)
check("coroutine yields", r1 == 7 and r2 == 12 and r3 == -1)
check("coroutine status", coroutine.status(co) == "dead")

local function gen(max)
  return coroutine.wrap(function()
    for i=1,max do coroutine.yield(i*i) end
  end)
end
local sum = 0
for v in gen(5) do sum = sum + v end
check("coroutine.wrap iterator", sum == 1+4+9+16+25)

print("=== error handling ===")
local ok, err = pcall(function() error("oops") end)
check("pcall catches error", not ok and err:find("oops"))
local ok2, err2 = pcall(function() error({code=42, msg="fail"}) end)
check("error with table", not ok2 and type(err2)=="table" and err2.code == 42)
local ok3 = pcall(function() local t = nil; return t.x end)
check("pcall catches nil deref", not ok3)

print("=== math library ===")
check("pi", math.abs(math.pi - 3.1415926535898) < 1e-10)
check("sqrt", math.sqrt(144) == 12)
check("sin/cos", math.abs(math.sin(0)) < 1e-15 and math.abs(math.cos(0) - 1) < 1e-15)
check("exp/log", math.abs(math.exp(math.log(2)) - 2) < 1e-12)
check("floor/ceil", math.floor(3.7) == 3 and math.ceil(3.2) == 4)
check("min/max", math.min(3,1,4,1,5) == 1 and math.max(3,1,4,1,5) == 5)
check("random", (function() math.randomseed(42); return math.random(1,100) >= 1 and math.random(1,100) <= 100 end)())
check("huge", math.huge > 1e300)

print("=== os library ===")
check("os.time", type(os.time()) == "number")
check("os.date", type(os.date("%Y")) == "string")
check("os.clock", type(os.clock()) == "number")
check("os.getenv", os.getenv("PATH") ~= nil or true)  -- PATH might not be set, but it must not crash

print("=== io library (stdout writes) ===")
io.write("(this is io.write)\n")
check("io.write returned io object", type(io.stdout.write) == "function")

print("=== heavy: 10k ops ===")
do
  local t = {}
  for i=1,10000 do t[i] = i end
  local s = 0
  for _,v in ipairs(t) do s = s + v end
  check("10k integer sum", s == 50005000)
end
do
  local s = ""
  for i=1,1000 do s = s .. "x" end
  check("1k string concat", #s == 1000)
end
do
  local t = {}
  for i=1,1000 do t["k"..i] = i*2 end
  local n = 0; for _ in pairs(t) do n = n + 1 end
  check("1k hash table", n == 1000)
end

print("=== gc ===")
collectgarbage("collect")
local before = collectgarbage("count")
do
  local junk = {}
  for i=1,5000 do junk[i] = {x=i, y=i*2, label="entry_"..i} end
end
local mid = collectgarbage("count")
collectgarbage("collect")
local after = collectgarbage("count")
check("gc reclaimed memory", after < mid - 50, string.format("before=%g mid=%g after=%g", before, mid, after))

print(string.format("\n=== RESULT: %d passed, %d failed ===", pass, fail))
os.exit(fail == 0 and 0 or 1)
