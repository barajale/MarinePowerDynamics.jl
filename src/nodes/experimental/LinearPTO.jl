using JSON

struct SeriesSampler
    time::Vector{Float64}
    values::Vector{Float64}
end

function build_sampler(time_raw, value_raw)
    t = Float64.(collect(time_raw))
    v = Float64.(collect(value_raw))
    @assert !isempty(t) "LinearPTO data needs non-empty time series"
    @assert length(t) == length(v) "LinearPTO time/value series must have matching lengths"
    if !issorted(t)
        idx = sortperm(t)
        t = t[idx]
        v = v[idx]
    end
    return SeriesSampler(t, v)
end

function (s::SeriesSampler)(t::Real)
    if !isfinite(t)
        return 0.0
    elseif t <= s.time[1]
        return s.values[1]
    elseif t >= s.time[end]
        return s.values[end]
    else
        i = searchsortedlast(s.time, t)
        i ≥ length(s.time) && return s.values[end]
        t1 = s.time[i]
        t2 = s.time[i+1]
        y1 = s.values[i]
        y2 = s.values[i+1]
        if t2 == t1
            return y2
        end
        return y1 + (t - t1) / (t2 - t1) * (y2 - y1)
    end
end

struct LinearPTOInput
    displacement::SeriesSampler
    velocity::SeriesSampler
    K::Float64
    C::Float64
end

function _load_linear_pto_json(path::AbstractString)
    payload = JSON.parsefile(path)
    @assert haskey(payload, "data") "LinearPTO JSON requires a 'data' section"
    data = payload["data"]
    for key in ("time", "relativeDisplacement", "relativeVelocity")
        @assert haskey(data, key) "LinearPTO JSON missing data.$(key)"
    end
    disp_sampler = build_sampler(data["time"], data["relativeDisplacement"])
    vel_sampler = build_sampler(data["time"], data["relativeVelocity"])

    meta = get(payload, "meta", Dict{String,Any}())
    K = _extract_coeff(meta, "Kpto", "stiffness")
    C = _extract_coeff(meta, "Cpto", "damping")

    return LinearPTOInput(disp_sampler, vel_sampler, K, C)
end

function _extract_coeff(meta, key_symbol, nested_key)
    if haskey(meta, key_symbol)
        val = meta[key_symbol]
        parsed = _try_float(val)
        return parsed === nothing ? 0.0 : parsed
    end
    if haskey(meta, "pto")
        pto = meta["pto"]
        if (pto isa Dict || pto isa NamedTuple) && haskey(pto, nested_key)
            val = pto[nested_key]
            parsed = _try_float(val)
            return parsed === nothing ? 0.0 : parsed
        end
    end
    return 0.0
end

function _try_float(val)
    if val isa Number
        return Float64(val)
    elseif val isa String
        try
            return parse(Float64, val)
        catch
            return nothing
        end
    else
        return nothing
    end
end

@doc doc"""
```Julia
LinearPTO(; τ_P, τ_Q, K_P, K_Q, V_r, Q, η, scaling_factor, json_file)
```

Grid-forming inverter model that sources its active-power reference from a
pre-computed linear PTO motion record. The PTO is treated as a spring-damper in
heave (`F = -K * x_rel - C * ẋ_rel`). Mechanical power is converted to
electrical power by multiplying with efficiency `η` and the user-supplied
`scaling_factor`, then fed into the standard droop dynamics inherited from
`VoltageSourceInverterMinimal`.

`json_file` must point to the `linear_pto_heave.json` produced by
`userDefinedFunctions.m`, which contains at least `data.time`,
`data.relativeDisplacement`, and `data.relativeVelocity`. The PTO stiffness and
damping are read from the JSON metadata; if absent they default to zero.
"""
@DynamicNode LinearPTO(
    τ_P, τ_Q, K_P, K_Q, V_r, Q, η, scaling_factor, json_file
) begin
    @assert τ_P > 0 "time constant active power measurement should be >0"
    @assert τ_Q > 0 "time constant reactive power measurement should be >0"
    @assert K_Q > 0 "reactive power droop constant should be >0"
    @assert K_P > 0 "active power droop constant should be >0"

    input = _load_linear_pto_json(json_file)

end [[ω, dω]] begin

    if !isfinite(t)
        relative_displacement = 0.0
        relative_velocity = 0.0
    else
        relative_displacement = input.displacement(t)
        relative_velocity = input.velocity(t)
    end

    F_pto = -input.K * relative_displacement - input.C * relative_velocity
    P_mech = -F_pto * relative_velocity
    Pref = η * scaling_factor * P_mech

    p = real(u * conj(i))
    q = imag(u * conj(i))
    dϕ = ω
    v = abs(u)
    dv = 1/τ_Q * (-v + V_r - K_Q * (q - Q))
    du = u * 1im * dϕ + dv * (u / v)
    dω = 1/τ_P * (-ω - K_P * (p - Pref))

end

export LinearPTO
