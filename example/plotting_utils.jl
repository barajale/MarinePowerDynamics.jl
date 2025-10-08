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

"""
    plot_system_comparison(sol1, sol2; 
                          system_labels = ["IEEE 14", "IEEE 15"],
                          vars = [:v, :ω, :p],
                          buses = :generators,
                          time_range = nothing,
                          fault_time = nothing,
                          save_path = nothing,
                          kwargs...)

Compare two power grid solutions side-by-side with optional fault marking.
Ideal for IEEE 14 vs IEEE 15 analysis with WEC integration.
"""
function plot_system_comparison(sol1::PowerGridSolution, sol2::PowerGridSolution;
                               system_labels = ["System 1", "System 2"],
                               vars = [:v, :ω, :p],
                               buses = :generators,
                               time_range = nothing,
                               fault_time = nothing,
                               save_path = nothing,
                               kwargs...)
    
    # Determine buses for both systems
    buses1 = buses == :generators ? _get_generator_buses(sol1.powergrid) : buses
    buses2 = buses == :generators ? _get_generator_buses(sol2.powergrid) : buses
    
    # Extract data
    requested_vars = vars isa Symbol ? (vars,) : collect(vars)
    sample1 = extract_timeseries(sol1; vars = requested_vars, buses = buses1, 
                                time_grid = time_range, warn_on_missing = false)
    sample2 = extract_timeseries(sol2; vars = requested_vars, buses = buses2,
                                time_grid = time_range, warn_on_missing = false)
    
    # Create comparison plots for each variable
    plots_array = []
    
    for var in requested_vars
        if haskey(sample1.values, var) && haskey(sample2.values, var)
            # Plot system 1
            p = plot(sample1.time, sample1.values[var];
                    xlabel = "Time [s]",
                    ylabel = _var_label(var),
                    title = "$(_var_title(var)) Comparison",
                    label = reshape(["$(system_labels[1]) - $(bus)" for bus in sample1.buses], 1, :),
                    linestyle = :solid,
                    alpha = 0.8,
                    merge(_DEFAULT_PLOT_SETTINGS, kwargs)...)
            
            # Add system 2
            plot!(p, sample2.time, sample2.values[var];
                  label = reshape(["$(system_labels[2]) - $(bus)" for bus in sample2.buses], 1, :),
                  linestyle = :dash,
                  alpha = 0.8)
            
            # Mark fault period if provided
            if fault_time !== nothing
                fault_start, fault_end = fault_time
                plot!(p, [fault_start, fault_start], ylims(p), 
                      color = :red, linestyle = :dot, linewidth = 2, 
                      label = "Fault Start", alpha = 0.7)
                plot!(p, [fault_end, fault_end], ylims(p),
                      color = :orange, linestyle = :dot, linewidth = 2,
                      label = "Fault Clear", alpha = 0.7)
            end
            
            push!(plots_array, p)
        end
    end
    
    # Create final layout
    if isempty(plots_array)
        error("No matching variables found between systems")
    end
    
    layout = _layout_dims(length(plots_array))
    final_plot = plot(plots_array...;
                     layout = layout,
                     size = (1200, 400 * layout[1]),
                     plot_title = "$(system_labels[1]) vs $(system_labels[2]) Analysis",
                     left_margin = 15Plots.mm,
                     bottom_margin = 10Plots.mm,
                     legend = :outertopright)
    
    if save_path !== nothing
        savefig(final_plot, save_path)
        @info "System comparison saved to: $save_path"
    end
    
    return final_plot
end

"""
    plot_fault_response(sol; 
                       fault_time = (10.0, 10.06),
                       pre_fault = 5.0,
                       post_fault = 35.0,
                       vars = [:v, :ω],
                       buses = :generators,
                       save_path = nothing,
                       kwargs...)

Specialized plot focusing on fault response characteristics with zoomed views.
"""
function plot_fault_response(sol::PowerGridSolution;
                           fault_time = (10.0, 10.06),
                           pre_fault = 5.0,
                           post_fault = 35.0,
                           vars = [:v, :ω],
                           buses = :generators,
                           save_path = nothing,
                           kwargs...)
    
    fault_start, fault_end = fault_time
    t_start = fault_start - pre_fault
    t_end = fault_end + post_fault
    
    # Extract data for fault analysis period
    selected_buses = buses == :generators ? _get_generator_buses(sol.powergrid) : buses
    sample = extract_timeseries(sol;
                               vars = vars,
                               buses = selected_buses,
                               time_grid = t_start:0.01:t_end,
                               warn_on_missing = false)
    
    plots_array = []
    
    for var in vars
        if haskey(sample.values, var)
            bus_labels = [_clean_bus_label(sol.powergrid, bus) for bus in sample.buses]
            
            p = plot(sample.time, sample.values[var];
                    xlabel = "Time [s]",
                    ylabel = _var_label(var),
                    title = "Fault Response - $(_var_title(var))",
                    label = reshape(bus_labels, 1, :),
                    grid = true,
                    gridalpha = 0.3,
                    merge(_DEFAULT_PLOT_SETTINGS, kwargs)...)
            
            # Highlight fault period
            y_min, y_max = ylims(p)
            plot!(p, [fault_start, fault_end, fault_end, fault_start, fault_start],
                  [y_min, y_min, y_max, y_max, y_min];
                  fillalpha = 0.2, fillcolor = :red, linecolor = :red,
                  linewidth = 0, label = "Fault Period")
            
            # Vertical lines for fault events
            vline!(p, [fault_start], color = :red, linestyle = :dash, 
                   linewidth = 2, label = "Fault Start", alpha = 0.7)
            vline!(p, [fault_end], color = :orange, linestyle = :dash,
                   linewidth = 2, label = "Fault Clear", alpha = 0.7)
            
            push!(plots_array, p)
        end
    end
    
    layout = _layout_dims(length(plots_array))
    final_plot = plot(plots_array...;
                     layout = layout,
                     size = (1200, 400 * layout[1]),
                     plot_title = "Grid Fault Response Analysis",
                     left_margin = 15Plots.mm,
                     legend = :outertopright)
    
    if save_path !== nothing
        savefig(final_plot, save_path)
        @info "Fault response plot saved to: $save_path"
    end
    
    return final_plot
end

"""
    analyze_wec_impact(ieee14_sol, ieee15_sol;
                      fault_time = (10.0, 10.06),
                      wec_bus = 15,
                      analysis_vars = [:v, :ω, :p],
                      save_dir = nothing)

Comprehensive analysis of WEC impact on grid stability comparing IEEE 14 vs IEEE 15.
Generates summary statistics and key performance indicators.
"""
function analyze_wec_impact(ieee14_sol::PowerGridSolution, ieee15_sol::PowerGridSolution;
                           fault_time = (10.0, 10.06),
                           wec_bus = 15,
                           analysis_vars = [:v, :ω, :p],
                           save_dir = nothing)
    
    println("="^60)
    println("WEC Impact Analysis: IEEE 14 vs IEEE 15 Comparison")
    println("="^60)
    
    fault_start, fault_end = fault_time
    
    # Get generator buses for comparison (common to both systems)
    gen_buses_14 = _get_generator_buses(ieee14_sol.powergrid)
    gen_buses_15 = _get_generator_buses(ieee15_sol.powergrid)
    common_buses = intersect(gen_buses_14, gen_buses_15)
    
    println("Analyzing $(length(common_buses)) common generator buses")
    println("Fault period: $(fault_start)s - $(fault_end)s")
    
    # Analysis periods
    pre_fault_period = (0.0, fault_start)
    during_fault_period = fault_time
    post_fault_period = (fault_end, fault_end + 10.0)  # 10s recovery analysis
    
    analysis_results = Dict()
    
    for var in analysis_vars
        if var ∈ [:v, :ω]  # Variables where we analyze deviations
            println("\n" * "="^40)
            println("$(_var_title(var)) Analysis")
            println("="^40)
            
            # Extract data for common buses
            data_14 = extract_timeseries(ieee14_sol; vars = (var,), buses = common_buses)
            data_15 = extract_timeseries(ieee15_sol; vars = (var,), buses = common_buses)
            
            # Calculate metrics for each period
            for (period_name, (t_start, t_end)) in [("Pre-fault", pre_fault_period),
                                                   ("During fault", during_fault_period),
                                                   ("Post-fault", post_fault_period)]
                
                # Find time indices
                idx_14 = findall(t -> t_start ≤ t ≤ t_end, data_14.time)
                idx_15 = findall(t -> t_start ≤ t ≤ t_end, data_15.time)
                
                if !isempty(idx_14) && !isempty(idx_15)
                    vals_14 = data_14.values[var][idx_14, :]
                    vals_15 = data_15.values[var][idx_15, :]
                    
                    # Calculate standard deviation (measure of stability)
                    std_14 = mean(std(vals_14, dims=1))
                    std_15 = mean(std(vals_15, dims=1))
                    
                    # Calculate max deviation from initial value
                    if var == :ω
                        # For frequency, measure deviation from nominal (assume first value is close to nominal)
                        initial_14 = mean(vals_14[1, :])
                        initial_15 = mean(vals_15[1, :])
                        max_dev_14 = maximum(abs.(vals_14 .- initial_14))
                        max_dev_15 = maximum(abs.(vals_15 .- initial_15))
                    else
                        max_dev_14 = maximum(abs.(vals_14 .- vals_14[1, :]))
                        max_dev_15 = maximum(abs.(vals_15 .- vals_15[1, :]))
                    end
                    
                    println("\n$period_name Period ($(t_start)-$(t_end)s):")
                    println("  Standard Deviation:")
                    println("    IEEE 14: $(round(std_14, digits=5))")
                    println("    IEEE 15: $(round(std_15, digits=5))")
                    println("    Improvement: $(round(((std_14-std_15)/std_14)*100, digits=2))%")
                    println("  Maximum Deviation:")
                    println("    IEEE 14: $(round(max_dev_14, digits=5))")
                    println("    IEEE 15: $(round(max_dev_15, digits=5))")
                    println("    Improvement: $(round(((max_dev_14-max_dev_15)/max_dev_14)*100, digits=2))%")
                    
                    # Store results
                    key = "$(var)_$(period_name)"
                    analysis_results[key] = Dict(
                        "std_14" => std_14, "std_15" => std_15,
                        "max_dev_14" => max_dev_14, "max_dev_15" => max_dev_15
                    )
                end
            end
        end
    end
    
    # WEC-specific analysis
    println("\n" * "="^40)
    println("WEC Performance Analysis")
    println("="^40)
    
    try
        wec_data = extract_timeseries(ieee15_sol; vars = (:p,), buses = [wec_bus])
        wec_power = vec(wec_data.values[:p][:, 1])
        
        println("WEC at Bus $wec_bus:")
        println("  Average Power: $(round(mean(wec_power), digits=3)) p.u.")
        println("  Peak Power: $(round(maximum(wec_power), digits=3)) p.u.")
        println("  Min Power: $(round(minimum(wec_power), digits=3)) p.u.")
        println("  Power Std Dev: $(round(std(wec_power), digits=4)) p.u.")
        
        analysis_results["wec_performance"] = Dict(
            "avg_power" => mean(wec_power),
            "peak_power" => maximum(wec_power),
            "min_power" => minimum(wec_power),
            "power_std" => std(wec_power)
        )
    catch
        println("Could not analyze WEC performance (bus $wec_bus not found)")
    end
    
    # Save results if directory provided
    if save_dir !== nothing
        mkpath(save_dir)
        
        # Generate comparison plots
        comparison_plot = plot_system_comparison(ieee14_sol, ieee15_sol;
                                               system_labels = ["IEEE 14", "IEEE 15"],
                                               vars = analysis_vars,
                                               fault_time = fault_time,
                                               save_path = joinpath(save_dir, "system_comparison.png"))
        
        fault_plot_14 = plot_fault_response(ieee14_sol; fault_time = fault_time,
                                          save_path = joinpath(save_dir, "ieee14_fault_response.png"))
        
        fault_plot_15 = plot_fault_response(ieee15_sol; fault_time = fault_time,
                                          save_path = joinpath(save_dir, "ieee15_fault_response.png"))
        
        # Save numerical results
        # Could add CSV export of analysis_results here if needed
        
        println("\nAnalysis plots saved to: $save_dir")
    end
    
    println("\n" * "="^60)
    println("Analysis Complete")
    println("="^60)
    
    return analysis_results
end

"""
    plot_wec_contribution(ieee15_sol; 
                         wec_bus = 15,
                         vars = [:p, :q, :v],
                         time_range = nothing,
                         save_path = nothing,
                         kwargs...)

Plot WEC-specific contributions and behavior in the IEEE 15 system.
"""
function plot_wec_contribution(ieee15_sol::PowerGridSolution;
                              wec_bus = 15,
                              vars = [:p, :q, :v],
                              time_range = nothing,
                              save_path = nothing,
                              kwargs...)
    
    # Extract WEC data
    wec_sample = extract_timeseries(ieee15_sol;
                                   vars = vars,
                                   buses = [wec_bus],
                                   time_grid = time_range,
                                   warn_on_missing = false)
    
    wec_label = _clean_bus_label(ieee15_sol.powergrid, wec_bus)
    
    # Create individual plots for each variable
    plots_array = []
    
    for var in vars
        if haskey(wec_sample.values, var)
            data = vec(wec_sample.values[var][:, 1])
            
            p = plot(wec_sample.time, data;
                    xlabel = "Time [s]",
                    ylabel = _var_label(var),
                    title = "WEC $(_var_title(var)) Output",
                    label = "$wec_label (WEC)",
                    color = :green,
                    linewidth = 3,
                    grid = true,
                    gridalpha = 0.3,
                    merge(_DEFAULT_PLOT_SETTINGS, kwargs)...)
            
            # Add statistics as annotations
            if var == :p
                avg_power = mean(data)
                annotate!(p, [(wec_sample.time[end]*0.7, maximum(data)*0.9, 
                             "Avg: $(round(avg_power, digits=3)) p.u.", 10)])
            end
            
            push!(plots_array, p)
        end
    end
    
    # Layout
    layout = _layout_dims(length(plots_array))
    final_plot = plot(plots_array...;
                     layout = layout,
                     size = (1000, 300 * layout[1]),
                     plot_title = "Wave Energy Converter Performance Analysis",
                     left_margin = 12Plots.mm)
    
    if save_path !== nothing
        savefig(final_plot, save_path)
        @info "WEC analysis plot saved to: $save_path"
    end
    
    return final_plot
end

# Update exports
export plot_grid_vars, plot_bus_dashboard, plot_bus_all_vars, plot_bus_var, 
       plot_bus_compare, save_solution_data, quick_analysis,
       plot_system_comparison, plot_fault_response, analyze_wec_impact, plot_wec_contribution
