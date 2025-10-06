using Plots
using OrderedCollections: OrderedDict
using MarinePowerDynamics: PowerGridSolution, extract_timeseries, resolve_bus, resolve_buses
using CSV, DataFrames

const _VAR_LABELS = Dict(
    :v => "V [p.u.]",
    :ω => "ω [rad/s]", 
    :p => "P [p.u.]",
    :q => "Q [p.u.]",
    :φ => "φ [rad]",
    :i => "I [p.u.]",
)

const _VAR_TITLES = Dict(
    :v => "Voltage",
    :ω => "Frequency",
    :p => "Active Power", 
    :q => "Reactive Power",
    :φ => "Voltage Angle",
    :i => "Current",
)

const _DEFAULT_VARS = (:v, :ω, :p, :q)
const _DEFAULT_PLOT_SETTINGS = Dict(
    :lw => 2.5,
    :size => (1000, 600),
    :left_margin => 12Plots.mm,
    :bottom_margin => 8Plots.mm,
    :dpi => 150
)

# Helper functions
_layout_dims(n) = n == 1 ? (1, 1) : n <= 2 ? (1, 2) : n <= 4 ? (2, 2) : (ceil(Int, n / 2), 2)
_var_label(var::Symbol) = get(_VAR_LABELS, var, string(var))
_var_title(var::Symbol) = get(_VAR_TITLES, var, string(var))

function _clean_bus_label(pg, bus)
    """Generate clean, consistent bus labels for legends"""
    bus_str = string(bus)
    # Extract just the number if it's a standard bus name
    m = match(r"(?:bus)?(\d+)$"i, bus_str)
    return m !== nothing ? "Bus $(m.captures[1])" : bus_str
end

function _get_generator_buses(pg)
    """Get list of generator/dynamic buses for focused plotting"""
    if pg.nodes isa OrderedDict
        return [k for (k, v) in pg.nodes if isa(v, Union{FourthOrderEq, LinearPTO})]
    else
        return [i for (i, v) in enumerate(pg.nodes) if isa(v, Union{FourthOrderEq, LinearPTO})]
    end
end

"""
    plot_grid_vars(sol::PowerGridSolution; 
                   vars = _DEFAULT_VARS,
                   buses = :generators,  # :all, :generators, or specific list
                   time_grid = nothing,
                   legend = :outertopright,
                   title = "Grid Variables Analysis",
                   save_path = nothing,
                   kwargs...)

Fast, clean plotting of grid variables with proper legends and performance optimization.
"""
function plot_grid_vars(sol::PowerGridSolution; 
                       vars = _DEFAULT_VARS, 
                       buses = :generators,
                       time_grid = nothing, 
                       legend = :outertopright,
                       title = "Grid Variables Analysis",
                       save_path = nothing,
                       kwargs...)
    
    # Determine which buses to plot
    if buses == :generators
        selected_buses = _get_generator_buses(sol.powergrid)
    elseif buses == :all || buses === nothing
        selected_buses = nothing  # extract_timeseries will handle all buses
    else
        selected_buses = buses
    end
    
    # Fast data extraction
    requested_vars = vars isa Symbol ? (vars,) : collect(vars)
    sample = extract_timeseries(sol;
                               vars = requested_vars,
                               buses = selected_buses,
                               time_grid = time_grid,
                               warn_on_missing = false)
    
    # Check available variables
    available_vars = [var for var in requested_vars if haskey(sample.values, var)]
    isempty(available_vars) && error("No variables available for plotting")
    
    # Generate clean labels for legend
    bus_labels = [_clean_bus_label(sol.powergrid, bus) for bus in sample.buses]
    
    # Create panels efficiently
    panels = map(available_vars) do var
        data_matrix = sample.values[var]
        p = plot(sample.time, data_matrix;
                xlabel = "Time [s]",
                ylabel = _var_label(var),
                title = _var_title(var),
                label = reshape(bus_labels, 1, :),  # Proper reshape for legend
                legend = legend,
                grid = true,
                gridalpha = 0.3,
                merge(_DEFAULT_PLOT_SETTINGS, kwargs)...)
        p
    end
    
    # Layout and final plot
    layout = _layout_dims(length(panels))
    final_plot = plot(panels...; 
                     layout = layout,
                     size = (1000, 300 * layout[1]),
                     plot_title = title,
                     left_margin = 12Plots.mm,
                     bottom_margin = 8Plots.mm)
    
    # Save if requested
    if save_path !== nothing
        savefig(final_plot, save_path)
        @info "Plot saved to: $save_path"
    end
    
    return final_plot
end

"""
    plot_bus_dashboard(sol::PowerGridSolution, bus;
                      vars = _DEFAULT_VARS,
                      time_grid = nothing, 
                      save_path = nothing,
                      kwargs...)

Create a comprehensive dashboard for a single bus with all requested variables.
"""
function plot_bus_dashboard(sol::PowerGridSolution, bus; 
                           vars = _DEFAULT_VARS, 
                           time_grid = nothing,
                           save_path = nothing,
                           kwargs...)
    
    resolved_bus = resolve_bus(sol.powergrid, bus)
    bus_label = _clean_bus_label(sol.powergrid, resolved_bus)
    
    # Extract data efficiently
    requested_vars = vars isa Symbol ? (vars,) : collect(vars)
    sample = extract_timeseries(sol;
                               vars = requested_vars,
                               buses = [resolved_bus],
                               time_grid = time_grid,
                               warn_on_missing = false)
    
    available_vars = [var for var in requested_vars if haskey(sample.values, var)]
    isempty(available_vars) && error("No variables available for bus $bus_label")
    
    # Create panels
    panels = map(available_vars) do var
        data = vec(sample.values[var][:, 1])  # Extract single bus data
        plot(sample.time, data;
             xlabel = "Time [s]",
             ylabel = _var_label(var),
             title = "$(bus_label) - $(_var_title(var))",
             label = bus_label,
             grid = true,
             gridalpha = 0.3,
             legend = :topright,
             merge(_DEFAULT_PLOT_SETTINGS, kwargs)...)
    end
    
    # Layout
    layout = _layout_dims(length(panels))
    final_plot = plot(panels...;
                     layout = layout,
                     size = (1000, 300 * layout[1]),
                     plot_title = "$bus_label Analysis Dashboard",
                     left_margin = 12Plots.mm)
    
    # Save if requested
    if save_path !== nothing
        savefig(final_plot, save_path)
        @info "Dashboard saved to: $save_path"
    end
    
    return final_plot
end

# Alias for backward compatibility
plot_bus_all_vars = plot_bus_dashboard

"""
    plot_bus_var(sol::PowerGridSolution, bus, var;
                 time_grid = nothing,
                 ylabel = nothing,
                 label = nothing,
                 save_path = nothing,
                 kwargs...)

Plot a single variable for a single bus with clean styling.
"""
function plot_bus_var(sol::PowerGridSolution, bus, var; 
                     time_grid = nothing, 
                     ylabel = nothing, 
                     label = nothing,
                     save_path = nothing,
                     kwargs...)
    
    resolved_bus = resolve_bus(sol.powergrid, bus)
    bus_label = something(label, _clean_bus_label(sol.powergrid, resolved_bus))
    y_label = something(ylabel, _var_label(var))
    
    # Extract data
    sample = extract_timeseries(sol;
                               vars = (var,),
                               buses = [resolved_bus],
                               time_grid = time_grid,
                               warn_on_missing = false)
    
    data = get(sample.values, var, nothing)
    data === nothing && error("Variable $var not available for $bus_label")
    
    # Create plot
    p = plot(sample.time, vec(data[:, 1]);
             xlabel = "Time [s]",
             ylabel = y_label,
             title = "$bus_label - $(_var_title(var))",
             label = bus_label,
             grid = true,
             gridalpha = 0.3,
             legend = :topright,
             merge(_DEFAULT_PLOT_SETTINGS, kwargs)...)
    
    # Save if requested
    if save_path !== nothing
        savefig(p, save_path)
        @info "Plot saved to: $save_path"
    end
    
    return p
end

"""
    plot_bus_compare(sol1, sol2, bus, var;
                    labels = ["Case 1", "Case 2"],
                    save_path = nothing,
                    kwargs...)

Compare a single variable between two solutions for the same bus.
"""
function plot_bus_compare(sol1::PowerGridSolution, sol2::PowerGridSolution, bus, var;
                         labels = ["Case 1", "Case 2"],
                         time_grid = nothing,
                         save_path = nothing,
                         kwargs...)
    
    resolved_bus1 = resolve_bus(sol1.powergrid, bus)
    resolved_bus2 = resolve_bus(sol2.powergrid, bus)
    bus_label = _clean_bus_label(sol1.powergrid, resolved_bus1)
    
    # Extract data from both solutions
    sample1 = extract_timeseries(sol1; vars = (var,), buses = [resolved_bus1], 
                                time_grid = time_grid, warn_on_missing = false)
    sample2 = extract_timeseries(sol2; vars = (var,), buses = [resolved_bus2], 
                                time_grid = time_grid, warn_on_missing = false)
    
    data1 = get(sample1.values, var, nothing)
    data2 = get(sample2.values, var, nothing)
    
    (data1 === nothing || data2 === nothing) && 
        error("Variable $var not available in one or both solutions")
    
    # Create comparison plot
    p = plot(sample1.time, vec(data1[:, 1]);
             xlabel = "Time [s]",
             ylabel = _var_label(var),
             title = "$bus_label - $(_var_title(var)) Comparison",
             label = labels[1],
             grid = true,
             gridalpha = 0.3,
             legend = :topright,
             merge(_DEFAULT_PLOT_SETTINGS, kwargs)...)
    
    plot!(p, sample2.time, vec(data2[:, 1]);
          label = labels[2],
          linestyle = :dash)
    
    # Save if requested
    if save_path !== nothing
        savefig(p, save_path)
        @info "Comparison plot saved to: $save_path"
    end
    
    return p
end

"""
    save_solution_data(sol::PowerGridSolution, filepath;
                      vars = _DEFAULT_VARS,
                      buses = :generators,
                      time_grid = nothing,
                      format = :csv)

Fast data export with proper formatting and metadata.
"""
function save_solution_data(sol::PowerGridSolution, filepath; 
                           vars = _DEFAULT_VARS,
                           buses = :generators,
                           time_grid = nothing,
                           format = :csv)
    
    # Determine buses
    if buses == :generators
        selected_buses = _get_generator_buses(sol.powergrid)
    elseif buses == :all
        selected_buses = nothing
    else
        selected_buses = buses
    end
    
    # Extract data efficiently
    requested_vars = vars isa Symbol ? (vars,) : collect(vars)
    sample = extract_timeseries(sol;
                               vars = requested_vars,
                               buses = selected_buses,
                               time_grid = time_grid,
                               warn_on_missing = false)
    
    # Create DataFrame
    df = DataFrame(time = sample.time)
    
    # Add data columns with clear names
    for (var, data_matrix) in sample.values
        for (i, bus) in enumerate(sample.buses)
            col_name = "$(bus)_$(var)"
            df[!, col_name] = data_matrix[:, i]
        end
    end
    
    # Save based on format  
    if format == :csv
        CSV.write(filepath, df)
    elseif format == :json
        # Could add JSON export here if needed
        error("JSON format not yet implemented")
    else
        error("Unsupported format: $format")
    end
    
    @info "Data exported to: $filepath ($(nrow(df)) rows, $(ncol(df)) columns)"
    return df
end

"""
    quick_analysis(sol::PowerGridSolution, bus; 
                  save_dir = nothing)

Generate a quick analysis report with plots and data for a specific bus.
"""
function quick_analysis(sol::PowerGridSolution, bus; save_dir = nothing)
    resolved_bus = resolve_bus(sol.powergrid, bus) 
    bus_label = _clean_bus_label(sol.powergrid, resolved_bus)
    
    println("="^50)
    println("Quick Analysis for $bus_label")
    println("="^50)
    
    # Create dashboard plot
    dashboard_plot = plot_bus_dashboard(sol, bus)
    
    # Extract and summarize data
    sample = extract_timeseries(sol;
                               vars = _DEFAULT_VARS,
                               buses = [resolved_bus],
                               warn_on_missing = false)
    
    # Print summary statistics
    for (var, data_matrix) in sample.values
        data_vec = vec(data_matrix[:, 1])
        println("\n$(_var_title(var)) ($(_var_label(var))):")
        println("  Min: $(round(minimum(data_vec), digits=4))")
        println("  Max: $(round(maximum(data_vec), digits=4))")
        println("  Mean: $(round(sum(data_vec)/length(data_vec), digits=4))")
        println("  Final: $(round(data_vec[end], digits=4))")
    end
    
    # Save if directory provided
    if save_dir !== nothing
        mkpath(save_dir)
        
        # Save plot
        plot_path = joinpath(save_dir, "$(bus)_dashboard.png")
        savefig(dashboard_plot, plot_path)
        
        # Save data  
        data_path = joinpath(save_dir, "$(bus)_data.csv")
        save_solution_data(sol, data_path; buses = [resolved_bus])
        
        println("\nFiles saved to: $save_dir")
    end
    
    return dashboard_plot
end

# Export all functions
export plot_grid_vars, plot_bus_dashboard, plot_bus_all_vars, plot_bus_var, 
       plot_bus_compare, save_solution_data, quick_analysis
