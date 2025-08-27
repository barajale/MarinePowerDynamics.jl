using Plots
using DataFrames
using CSV

"""
    plot_bus_data(solution, bus_number, variable, sim_config; wave_df=nothing, plot_wave=false, save_to_file=false, events=false, run="default", output_dir="./plots")

Plot data for a specific bus and variable from a power system simulation.

# Arguments
- `solution`: The solution object from the power system simulation
- `bus_number`: The bus number to plot (integer)
- `variable`: The variable to plot (string: "v", "p", "q", "ω", "φ")
- `sim_config`: Dictionary containing simulation configuration including timing information
- `wave_df`: DataFrame containing wave data (optional)
- `plot_wave`: Boolean to control whether to plot wave data
- `save_to_file`: Boolean to control whether to save the plot to file
- `events`: Boolean to control whether to show event markers
- `run`: String identifier for the run
- `output_dir`: Directory to save plots if save_to_file is true
"""
function plot_bus_data(solution, bus_number, variable, sim_config; 
                      wave_df=nothing, plot_wave=false, save_to_file=false, 
                      events=false, run="default", output_dir="./plots")
    
    # Extract time vector from solution
    time_vector = solution.dqsol.t
    
    # Map variable strings to symbols and labels
    var_map = Dict(
        "v" => (:v, "Voltage Magnitude [p.u.]"),
        "p" => (:p, "Active Power [p.u.]"),
        "q" => (:q, "Reactive Power [p.u.]"),
        "ω" => (:ω, "Frequency [rad/s]"),
        "φ" => (:φ, "Voltage Angle [rad]")
    )
    
    if !haskey(var_map, variable)
        error("Unknown variable: $variable. Valid options are: $(keys(var_map))")
    end
    
    var_symbol, ylabel = var_map[variable]
    
    # Extract data for the specified bus and variable
    bus_name = "bus$bus_number"
    data = [solution(t, bus_name, var_symbol) for t in time_vector]
    
    # Create the main plot
    p = plot(time_vector, data, 
             label="Bus $bus_number",
             lw=2,
             xlabel="Time [s]",
             ylabel=ylabel,
             title="$ylabel - Bus $bus_number",
             legend=:topright)
    
    # Add event markers if requested
    if events && haskey(sim_config, "t1") && haskey(sim_config, "t2")
        t1 = sim_config["t1"]
        t2 = sim_config["t2"]
        
        # Add vertical lines for events
        vline!([t1], label="Event Start", linestyle=:dash, color=:red, alpha=0.7)
        vline!([t2], label="Event End", linestyle=:dash, color=:green, alpha=0.7)
    end
    
    # Add wave data subplot if requested and available
    if plot_wave && wave_df !== nothing
        # Create a subplot for wave height
        wave_times = wave_df.Time
        wave_heights = wave_df.Wave_Height
        
        p_wave = plot(wave_times, wave_heights,
                     lw=2,
                     xlabel="Time [s]",
                     ylabel="Wave Height [m]",
                     title="Wave Height",
                     color=:blue,
                     label="Wave Height")
        
        # Combine plots
        p = plot(p, p_wave, layout=(2,1), size=(800, 600))
    end
    
    # Save to file if requested
    if save_to_file
        mkpath(output_dir)
        filename = joinpath(output_dir, "$(run)_bus$(bus_number)_$(variable).png")
        savefig(p, filename)
        println("Plot saved to: $filename")
    end
    
    return p
end

export plot_bus_data
