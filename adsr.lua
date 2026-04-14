function init()
  for i = 1,4 do
    local a = math.random() * 1 + 1
    local d = math.random() * 1 + 1
    local s_lvl = math.random() * 2 + 5
    local r = math.random() * 5 + 5

    print(i, a, d, s_lvl, r)

    output[i].action = adsr(a, d, s_lvl, r)
  end

  input[1].change = function(s)
    for i = 1,4 do
      output[i](s)
    end
  end

  input[1].mode = 'change'

  input[2]{
    mode = 'stream',
    stream = function(v) print(v) end
  }
end
