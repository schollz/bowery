--- quantized voltage passthrough + dynamic AR envelopes + just intonation option
function init()
    -- toggle: set to true for just intonation, false for 12-TET
    local use_just = true

    -- define C major scale for both tuning systems
    local scale_12tet = {0, 2, 4, 5, 7, 9, 11}
    local scale_ji = {1 / 1, 9 / 8, 5 / 4, 4 / 3, 3 / 2, 5 / 3, 15 / 8}

    -- assign correct scale + temperament based on toggle
    if use_just then
        input[1].mode('scale', scale_ji, 'ji', 1.0)
        input[2].mode('scale', scale_ji, 'ji', 1.0)
        output[1].scale(scale_ji, 'ji', 1.0)
        output[2].scale(scale_ji, 'ji', 1.0)
    else
        input[1].mode('scale', scale_12tet, 12, 1.0)
        input[2].mode('scale', scale_12tet, 12, 1.0)
        output[1].scale(scale_12tet, 12, 1.0)
        output[2].scale(scale_12tet, 12, 1.0)
    end

    -- track time of last voltage change
    last_change = {time(), time()}

    for i = 1, 2 do
        input[i].scale = function(s)
            local time_between = time() - last_change[i]
            -- print(i, s.volts, time_between)
            local atk = math.min(time_between / 1000 * 0.4, 4)
            local rel = math.min(time_between / 1000 * 0.6, 6)
            output[i].volts = s.volts
            output[i + 2].action = ar(atk, rel, 5)
            output[i + 2]()
            last_change[i] = time()
        end
    end
end
