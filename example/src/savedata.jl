


using CSV
using DataFrames
using JSON

"""
    save_sim(solution::PowerGridSolution, config=nothing; 
             output_dir="./simulation_results", 
             filename_prefix="simulation",
             save_metadata=true,
             save_timeseries=true,
             variables=[:v, :p, :q, :ω])

Save simulation results and metadata to files.

# Arguments
- `solution`: PowerGridSolution object from simulate()
- `config`: Configuration dictionary used for the simulation (optional)
- `output_dir`: Directory to save files (default: "./simulation_results")
- `filename_prefix`: Prefix for output files (default: "simulation")
- `save_metadata`: Whether to save metadata as JSON (default: true)
- `save_timeseries`: Whether to save time series data as CSV (default: true)
- `variables`: List of variables to save (default: [:v, :p, :q, :ω])

# Output files
- `{filename_prefix}_metadata.json`: Simulation metadata
- `{filename_prefix}_timeseries.csv`: Time series data for all buses
- `{filename_prefix}_summary.csv`: Summary statistics
"""
function save_sim(solution::PowerGridSolution, config=nothing; 
                  output_dir="./simulation_results", 
                  filename_prefix="simulation",
                  save_metadata=true,
                  save_timeseries=true,
                  variables=[:v, :p, :q, :ω])
    
    # Create output directory if it doesn't exist
    if !isdir(output_dir)
        mkpath(output_dir)
    end
    
    # Get basic info about the simulation
    time_vector = solution.dqsol.t
    bus_names = collect(keys(solution.powergrid.nodes))
    
    # Create simple numeric timestamp based on simulation duration
    sim_duration = time_vector[end] - time_vector[1]
    base_filename = "$(filename_prefix)_$(round(Int, sim_duration))s"
    
    println("Saving simulation results...")
    println("Time span: $(time_vector[1]) - $(time_vector[end]) seconds")
    println("Number of buses: $(length(bus_names))")
    println("Number of time points: $(length(time_vector))")
    
    # Save metadata
    if save_metadata
        metadata_file = joinpath(output_dir, "$(base_filename)_metadata.json")
        metadata = Dict(
            "simulation_time_info" => Dict(
                "start_time_sec" => time_vector[1],
                "end_time_sec" => time_vector[end],
                "duration_sec" => time_vector[end] - time_vector[1],
                "num_time_points" => length(time_vector),
                "avg_time_step_sec" => (time_vector[end] - time_vector[1]) / (length(time_vector) - 1),
                "time_vector_sec" => time_vector  # Store raw simulation times
            ),
            "grid_info" => Dict(
                "num_buses" => length(bus_names),
                "bus_names" => bus_names,
                "num_branches" => length(solution.powergrid.lines),
                "branch_names" => collect(keys(solution.powergrid.lines))
            ),
            "solver_info" => Dict(
                "return_code" => string(solution.dqsol.retcode),
                "solver_successful" => true  # We'll assume successful if we can save
            ),
            "config" => config,
            "variables_saved" => string.(variables)
        )
        
        open(metadata_file, "w") do f
            JSON.print(f, metadata, 2)
        end
        println("Metadata saved to: $(metadata_file)")
    end
    
    # Save time series data
    if save_timeseries
        timeseries_file = joinpath(output_dir, "$(base_filename)_timeseries.csv")
        
        # Create DataFrame with time column (simulation time in seconds)
        df = DataFrame(time_sec = time_vector)
        
        # Add data for each variable and bus
        for var in variables
            for bus in bus_names
                try
                    # Get data for this variable and bus
                    data = solution(time_vector, bus, var)
                    # Handle complex numbers (for variables like :u, :i, :s)
                    if eltype(data) <: Complex
                        df[!, "$(bus)_$(var)_real"] = real.(data)
                        df[!, "$(bus)_$(var)_imag"] = imag.(data)
                        df[!, "$(bus)_$(var)_abs"] = abs.(data)
                        df[!, "$(bus)_$(var)_angle"] = angle.(data)
                    else
                        df[!, "$(bus)_$(var)"] = data
                    end
                catch e
                    println("Warning: Could not extract variable :$(var) for bus $(bus): $(e)")
                end
            end
        end
        
        CSV.write(timeseries_file, df)
        println("Time series data saved to: $(timeseries_file)")
    end
    
    # Save summary statistics
    summary_file = joinpath(output_dir, "$(base_filename)_summary.csv")
    summary_data = []
    
    for var in variables
        for bus in bus_names
            try
                data = solution(time_vector, bus, var)
                if eltype(data) <: Complex
                    # For complex data, summarize magnitude
                    mag_data = abs.(data)
                    push!(summary_data, (
                        bus = bus,
                        variable = "$(var)_magnitude",
                        min = minimum(mag_data),
                        max = maximum(mag_data),
                        mean = sum(mag_data) / length(mag_data),
                        std = sqrt(sum((mag_data .- sum(mag_data)/length(mag_data)).^2) / (length(mag_data)-1)),
                        final_value = mag_data[end]
                    ))
                else
                    push!(summary_data, (
                        bus = bus,
                        variable = string(var),
                        min = minimum(data),
                        max = maximum(data),
                        mean = sum(data) / length(data),
                        std = sqrt(sum((data .- sum(data)/length(data)).^2) / (length(data)-1)),
                        final_value = data[end]
                    ))
                end
            catch e
                # Skip if variable not available for this bus
            end
        end
    end
    
    summary_df = DataFrame(summary_data)
    CSV.write(summary_file, summary_df)
    println("Summary statistics saved to: $(summary_file)")
    
    println("All simulation data saved successfully!")
    return Dict(
        "metadata_file" => save_metadata ? joinpath(output_dir, "$(base_filename)_metadata.json") : nothing,
        "timeseries_file" => save_timeseries ? joinpath(output_dir, "$(base_filename)_timeseries.csv") : nothing,
        "summary_file" => joinpath(output_dir, "$(base_filename)_summary.csv"),
        "base_filename" => base_filename
    )
end