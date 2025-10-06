using DiffEqBase: AbstractTimeseriesSolution
using SciMLBase
using Lazy: @>>
using RecipesBase: @recipe, RecipesBase
using NetworkDynamics
using OrderedCollections: OrderedDict
using DataFrames
using CSV


"""
    struct PowerGridSolution
        dqsol::AbstractTimeseriesSolution
        powergrid::PowerGrid
    end
The data structure interfacing to the solution of the differential equations of a power grid.
Normally, it is not created by hand but return from `PowerDynSolve.solve`.
# Accessing the solution in a similar interface as [`State`](@ref).
For some grid solution `sol`, one can access the variables as
```julia
sol(t, n, s)
```
where `t` is the time (either float or array),
`n` the node number(s) (either integer, array, range (e.g. 2:3) or colon (:, for all nodes)),
and `s` is the symbol represnting the chosen value.
`s` can be either: `:v`, `:φ`, `:i`, `:iabs`, `:δ`, `:s`, `:p`, `:q`, or the symbol of the internal variable of the nodes.
The meaning of the symbols derives from the conventions of PowerDynamics.jl.
Finally, one can access the `a`-th internal variable of a node by using `sol(t, n, :int, a)`.
# Interfacing the Plots.jl library via plotting recipes, that follow similar instructions as the direct access to the solution.
For some grid solution `sol`, one plot variables of the solution asin
```julia
using Plots
plot(sol, n, s, plots_kwargs...)
```
where `n` and `s` are as in the accessing of plots, and `plots_kwargs` are the keyword arguments for Plots.jl.
"""
struct PowerGridSolution
    dqsol::AbstractTimeseriesSolution
    powergrid::PowerGrid
    function PowerGridSolution(dqsol::AbstractTimeseriesSolution, powergrid::PowerGrid)
        if !SciMLBase.successful_retcode(dqsol.retcode)
            throw(GridSolutionError("unsuccesful, return code is $(dqsol.retcode)"))
        end
        new(dqsol, powergrid)
    end
end
TimeSeries(sol::PowerGridSolution) = sol.dqsol
tspan(sol::PowerGridSolution) = (TimeSeries(sol).t[1], TimeSeries(sol).t[end])
tspan(sol::PowerGridSolution, tres) = range(TimeSeries(sol).t[1], stop=TimeSeries(sol).t[end], length=tres)

(sol::PowerGridSolution)(sym::Symbol) = sol(Val{sym})
(sol::PowerGridSolution)(::Type{Val{:initial}}) = sol(tspan(sol)[1])
(sol::PowerGridSolution)(::Type{Val{:final}}) = sol(tspan(sol)[2])


(sol::PowerGridSolution)(t::Number) = begin
    State(sol.powergrid, convert(Array, TimeSeries(sol)(t)))
end

(sol::PowerGridSolution)(t, ::Colon, sym::Symbol, args...; kwargs...) = sol(t, collect(keys(sol.powergrid.nodes)), sym, args...; kwargs...)
(sol::PowerGridSolution)(t, n, sym::Symbol, args...) = begin
    if any(n .< 1) || any(n .> length(sol.powergrid.nodes))
        throw(StateError("Index: $n is outside of range of nodes."))
    else
        sol(t, n, Val{sym}, args...)
    end
end

(sol::PowerGridSolution)(t, n::String, sym::Symbol, args...) = begin
    bus_array=collect(keys(sol.powergrid.nodes))
    ni=findfirst(x->x==n, bus_array)
    if (ni === nothing)
        throw(StateError("Key: $n is not in bus dictionary."))
    else
        sol(t, n, Val{sym}, args...)
    end
end

(sol::PowerGridSolution)(t, n::Array, sym::Symbol, args...) = begin
    bus_array=collect(keys(sol.powergrid.nodes))
    ni=[findfirst(x->x==nx, bus_array) for nx in n]
    if any(ni .=== nothing) || any(ni .< 1) || any(ni .> length(sol.powergrid.nodes))
        throw(StateError("Array: $n is not in bus dictionary."))
    else
        sol(t, n, Val{sym}, args...)
    end
end

(sol::PowerGridSolution)(t::Number, n::Number, ::Type{Val{:u}}) = begin
    u_real = TimeSeries(sol)(t, idxs= variable_index(sol.powergrid.nodes, n, :u_r))
    u_imag = TimeSeries(sol)(t, idxs= variable_index(sol.powergrid.nodes, n, :u_i))
    u_real + im * u_imag
end

(sol::PowerGridSolution)(t::Number, n::String, ::Type{Val{:u}}) = begin
    u_real = TimeSeries(sol)(t, idxs= variable_index(sol.powergrid.nodes, n, :u_r))
    u_imag = TimeSeries(sol)(t, idxs= variable_index(sol.powergrid.nodes, n, :u_i))
    u_real + im * u_imag
end
(sol::PowerGridSolution)(t, n::AbstractArray, ::Type{Val{:u}}) = begin
    u_real = @>> TimeSeries(sol)(t, idxs= variable_index(sol.powergrid.nodes, n, :u_r)) convert(Array)
    u_imag = @>> TimeSeries(sol)(t, idxs= variable_index(sol.powergrid.nodes, n, :u_i)) convert(Array)
    u_real .+ im .* u_imag
end
(sol::PowerGridSolution)(t, n::String, ::Type{Val{:u}}) = begin
    u_real = @>> TimeSeries(sol)(t, idxs= variable_index(sol.powergrid.nodes, n, :u_r)) convert(Array)
    u_imag = @>> TimeSeries(sol)(t, idxs= variable_index(sol.powergrid.nodes, n, :u_i)) convert(Array)
    u_real .+ im .* u_imag
end
(sol::PowerGridSolution)(t, n, ::Type{Val{:v}}) = sol(t, n, :u) .|> abs
(sol::PowerGridSolution)(t, n, ::Type{Val{:φ}}) = sol(t, n, :u) .|> angle

(sol::PowerGridSolution)(t, n, ::Type{Val{:i}}) = get_current(sol, t, n)
(sol::PowerGridSolution)(t::Number, n, ::Type{Val{:i}}) = get_current(sol, t, n)

(sol::PowerGridSolution)(t, n, ::Type{Val{:iabs}}) = sol(t, n, :i) .|> abs
(sol::PowerGridSolution)(t, n, ::Type{Val{:δ}}) = sol(t, n, :i) .|> angle
(sol::PowerGridSolution)(t, n, ::Type{Val{:s}}) = sol(t, n, :u) .* conj.(sol(t, n, :i))
(sol::PowerGridSolution)(t, n, ::Type{Val{:p}}) = sol(t, n, :s) .|> real
(sol::PowerGridSolution)(t, n, ::Type{Val{:q}}) = sol(t, n, :s) .|> imag
(sol::PowerGridSolution)(t, n, ::Type{Val{:int}}, i) = @>> TimeSeries(sol)(t, idxs=variable_index(sol.powergrid.nodes, n, i)) convert(Array)
(sol::PowerGridSolution)(t::Number, n::String, ::Type{Val{:int}}, i::S) where {S <: Union{Number,Symbol}} = TimeSeries(sol)(t, idxs=variable_index(sol.powergrid.nodes, n, i))
(sol::PowerGridSolution)(t::Number, n::Number, ::Type{Val{:int}}, i::S) where {S <: Union{Number,Symbol}} = TimeSeries(sol)(t, idxs=variable_index(sol.powergrid.nodes, n, i))
(sol::PowerGridSolution)(t, n, ::Type{Val{sym}}) where sym = sol(t, n, Val{:int}, sym)

variable_index(nodes, n::AbstractArray, s) = map(n -> variable_index(nodes, n, s), n)

startindex(nodes, n::AbstractArray) = map(n -> startindex(nodes, n), n)

const _network_dynamics_cache = IdDict{UInt, Any}()

function _network_dynamics_for(sol::PowerGridSolution)
    pg = sol.powergrid
    get!(_network_dynamics_cache, objectid(pg)) do
        vertices = map(construct_vertex, collect(values(pg.nodes)))
        edges = map(construct_edge, collect(values(pg.lines)))
        network_dynamics(vertices, edges, pg.graph)
    end
end

function _ordered_node_keys(pg::PowerGrid)
    pg.nodes isa OrderedDict ? collect(keys(pg.nodes)) : collect(eachindex(pg.nodes))
end

function resolve_bus(pg::PowerGrid, bus)
    key_list = _ordered_node_keys(pg)

    if pg.nodes isa OrderedDict
        idx = findfirst(isequal(bus), key_list)
        idx === nothing && (idx = findfirst(k -> string(k) == string(bus), key_list))
        if idx === nothing
            if bus isa Integer && 1 <= bus <= length(key_list)
                return key_list[bus]
            else
                throw(StateError("Bus $(bus) not found in power grid."))
            end
        end
        return key_list[idx]
    end

    if bus isa Integer
        1 <= bus <= length(key_list) || throw(StateError("Bus index $(bus) outside 1:$(length(key_list))."))
        return bus
    end

    m = match(r"(\d+)", string(bus))
    m === nothing && throw(StateError("Cannot parse bus identifier $(bus)."))
    idx = parse(Int, m.captures[1])
    1 <= idx <= length(key_list) || throw(StateError("Bus index $(idx) outside 1:$(length(key_list))."))
    idx
end

function resolve_buses(pg::PowerGrid, buses)
    if buses === nothing
        return _ordered_node_keys(pg)
    elseif buses isa AbstractVector
        return [resolve_bus(pg, b) for b in buses]
    else
        return [resolve_bus(pg, buses)]
    end
end

function _bus_indices(pg::PowerGrid, buses)
    key_list = _ordered_node_keys(pg)
    index_map = Dict{Any, Int}(key => i for (i, key) in enumerate(key_list))
    map(buses) do bus
        idx = get(index_map, bus, nothing)
        idx === nothing && throw(StateError("Bus $(bus) not found in power grid."))
        idx
    end
end

function _collect_current(nd, state, idxs::AbstractVector{Int})
    gd = nd(state, nothing, 0.0, GetGD)
    [total_current(get_dst_edges(gd, idx)) for idx in idxs]
end

function _collect_current(nd, state, idx::Int)
    gd = nd(state, nothing, 0.0, GetGD)
    total_current(get_dst_edges(gd, idx))
end

get_current(sol::PowerGridSolution, t::Number, bus) = begin
    pg = sol.powergrid
    nd = _network_dynamics_for(sol)
    resolved_bus = resolve_bus(pg, bus)
    idx = only(_bus_indices(pg, [resolved_bus]))
    state = sol.dqsol(t)
    _collect_current(nd, state, idx)
end

get_current(sol::PowerGridSolution, t::Number, buses::AbstractVector) = begin
    pg = sol.powergrid
    nd = _network_dynamics_for(sol)
    resolved = resolve_buses(pg, buses)
    idxs = _bus_indices(pg, resolved)
    state = sol.dqsol(t)
    _collect_current(nd, state, idxs)
end

get_current(sol::PowerGridSolution, t::AbstractVector, buses::AbstractVector) = begin
    pg = sol.powergrid
    nd = _network_dynamics_for(sol)
    resolved = resolve_buses(pg, buses)
    idxs = _bus_indices(pg, resolved)
    states = sol.dqsol(t)
    hcat([_collect_current(nd, state, idxs) for state in states]...)
end

get_current(sol::PowerGridSolution, t::AbstractVector, bus) = get_current(sol, t, [bus])

function _ensure_matrix(data)
    arr = convert(Array, data)
    ndims(arr) == 1 && return reshape(arr, 1, :)
    ndims(arr) == 2 && return arr
    throw(ArgumentError("Unsupported data dimensionality $(ndims(arr))."))
end

function _as_time_by_bus(data, time_len::Int, bus_len::Int)
    arr = _ensure_matrix(data)
    if size(arr, 1) == bus_len && size(arr, 2) == time_len
        return permutedims(arr, (2, 1))
    elseif size(arr, 1) == time_len && size(arr, 2) == bus_len
        return copy(arr)
    else
        throw(ArgumentError("Unexpected data dimensions $(size(arr)) for $(bus_len) buses over $(time_len) samples."))
    end
end

function _default_column_name(var::Symbol, bus, idx::Int)
    bus_str = string(bus)
    sanitized = replace(bus_str, r"[^A-Za-z0-9_]+" => "_")
    isempty(sanitized) && (sanitized = "bus$(idx)")
    Symbol(string(var), "_", sanitized)
end

"""
    extract_timeseries(sol::PowerGridSolution;
                       vars = (:v, :ω, :p, :q),
                       buses = nothing,
                       time_grid = nothing,
                       warn_on_missing = true)

Collect solution values for the selected variables and buses on a chosen time grid.
Returns a named tuple with the sampled `time` vector, resolved `buses`, an
`OrderedDict` mapping each variable to a matrix of size `(length(time), length(buses))`,
and a list of `missing` variables that were skipped because they are not defined
for the selected buses.
"""
function extract_timeseries(sol::PowerGridSolution;
                            vars = (:v, :ω, :p, :q),
                            buses = nothing,
                            time_grid = nothing,
                            warn_on_missing::Bool = true)
    var_list = vars isa Symbol ? (vars,) : collect(vars)
    pg = sol.powergrid
    selected_buses = resolve_buses(pg, buses)
    isempty(selected_buses) && throw(ArgumentError("No buses selected."))

    times = time_grid === nothing ? copy(TimeSeries(sol).t) : collect(time_grid)
    isempty(times) && throw(ArgumentError("Time grid is empty."))

    bus_count = length(selected_buses)
    values = OrderedDict{Symbol, AbstractMatrix}()
    missing = Symbol[]
    cache = Dict{Symbol, Any}()
    complex_power = Ref{Any}(nothing)
    complex_power_tried = Ref(false)

    ensure_cached!(var::Symbol) = begin
        if haskey(cache, var)
            return cache[var]
        end
        data = try
            _as_time_by_bus(sol(times, selected_buses, var), length(times), bus_count)
        catch err
            if err isa StateError && occursin("Variable", err.msg)
                cache[var] = nothing
                return nothing
            else
                rethrow()
            end
        end
        cache[var] = data
        data
    end

    handle_missing(var::Symbol) = begin
        push!(missing, var)
        warn_on_missing && @warn "Variable $(var) not defined for all selected buses. Skipping."
        nothing
    end

    function complex_power_data()
        if complex_power_tried[]
            return complex_power[]
        end
        complex_power_tried[] = true
        u_data = ensure_cached!(:u)
        i_data = ensure_cached!(:i)
        if u_data === nothing || i_data === nothing
            complex_power[] = nothing
        else
            complex_power[] = u_data .* conj.(i_data)
        end
        complex_power[]
    end

    for var in var_list
        if var === :v
            u_data = ensure_cached!(:u)
            u_data === nothing && (handle_missing(var); continue)
            values[var] = abs.(u_data)
        elseif var === :φ
            u_data = ensure_cached!(:u)
            u_data === nothing && (handle_missing(var); continue)
            values[var] = angle.(u_data)
        elseif var === :iabs
            i_data = ensure_cached!(:i)
            i_data === nothing && (handle_missing(var); continue)
            values[var] = abs.(i_data)
        elseif var === :δ
            i_data = ensure_cached!(:i)
            i_data === nothing && (handle_missing(var); continue)
            values[var] = angle.(i_data)
        elseif var === :s
            s_data = complex_power_data()
            s_data === nothing && (handle_missing(var); continue)
            values[var] = s_data
        elseif var === :p || var === :q
            s_data = complex_power_data()
            s_data === nothing && (handle_missing(var); continue)
            values[var] = var === :p ? real.(s_data) : imag.(s_data)
        else
            data = ensure_cached!(var)
            data === nothing && (handle_missing(var); continue)
            values[var] = data
        end
    end

    (; time = times, buses = selected_buses, values, missing)
end

"""
    solution_dataframe(sol::PowerGridSolution; kwargs...)

Return a wide `DataFrame` with columns for each `(variable, bus)` combination and
an optional leading `time` column.
"""
function solution_dataframe(sol::PowerGridSolution;
                            vars = (:v, :ω, :p, :q),
                            buses = nothing,
                            time_grid = nothing,
                            warn_on_missing::Bool = true,
                            include_time::Bool = true,
                            column_namer::_F = _default_column_name) where {_F}
    sample = extract_timeseries(sol;
                                vars = vars,
                                buses = buses,
                                time_grid = time_grid,
                                warn_on_missing = warn_on_missing)

    isempty(sample.values) && throw(StateError("No variables available to build DataFrame."))

    df = include_time ? DataFrame(time = sample.time) : DataFrame()

    for (var, data) in sample.values
        for (idx, bus) in enumerate(sample.buses)
            col_name = column_namer(var, bus, idx)
            df[!, col_name] = @view data[:, idx]
        end
    end

    df
end

"""
    save_solution_dataframe(destination, sol::PowerGridSolution; kwargs...)

Write the sampled solution to `destination` using `CSV.write`. The helper accepts
all keyword arguments of [`solution_dataframe`](@ref) to control the sampled
content. Returns the result of `CSV.write`.
"""
function save_solution_dataframe(destination, sol::PowerGridSolution; kwargs...)
    df = solution_dataframe(sol; kwargs...)
    CSV.write(destination, df)
end

# define the plotting recipes

"Create the standard variable labels for power grid plots."
tslabel(sym, node) = "$(sym)$(node)"
tslabel(sym, n::AbstractArray) = tslabel.(Ref(sym), n)
tslabel(sym, node, i) = "$(sym)$(node)_$(i)"
tslabel(sym, n::AbstractArray, i) = tslabel.(Ref(sym), n, Ref(i))
"Transform the array output from DifferentialEquations.jl correctly to be used in Plots.jl's recipes."
tstransform(arr::AbstractArray{T, 1}) where T = arr
tstransform(arr::AbstractArray{T, 2}) where T = arr'

const PLOT_TTIME_RESOLUTION = 10_000 # TODO:@sabine is this high resolution really needed?

@recipe function f(sol::PowerGridSolution, ::Colon, sym::Symbol, args...)
    sol, collect(keys(sol.powergrid.nodes)), sym, args ...
end
@recipe function f(sol::PowerGridSolution, n, sym::Symbol, args...; tres = PLOT_TTIME_RESOLUTION)
    if sym == :int
        label --> tslabel(sym, n, args[1])
    else
        label --> tslabel(sym, n)
    end
    xguide --> "t"
    t = tspan(sol, tres)
    t, tstransform(sol(t, n, sym, args...))
end
