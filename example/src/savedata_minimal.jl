using CSV
using DataFrames
using JSON

"""
    save_sim_minimal(solution::PowerGridSolution, config=nothing; 
                     output_dir="./simulation_results", 
                     filename_prefix="simulation",
                     key_variables=[:v, :ω, :p])

Save full resolution simulation results for all nodes in the power grid.

# Arguments
- `solution`: PowerGridSolution object from simulate()
- `config`: Configuration dictionary used for the simulation (optional)
- `output_dir`: Directory to save files (default: "./simulation_results")
- `filename_prefix`: Prefix for output files (default: "simulation")
- `key_variables`: Variables to save (default: [:v, :ω, :p] - voltage, frequency, power)

# Output files
- `{filename_prefix}_data.csv`: Full resolution time series data for all nodes
- `{filename_prefix}_metadata.json`: Simulation metadata with node classification

# Notes
- Generators (FourthOrderEq, LinearPTO) will have :ω and :p data
- Loads (PQAlgebraic, etc.) will only have :v data typically
- Missing variables for specific node types will show warnings but not fail
"""
function save_sim_minimal(solution::PowerGridSolution, config=nothing; 
                          output_dir="./simulation_results", 
                          filename_prefix="simulation",
                          key_variables=[:v, :ω, :p])
    
    # Create output directory if it doesn't exist
    if !isdir(output_dir)
        mkpath(output_dir)
    end
    
    # Get time vector and all nodes info
    time_vector = solution.dqsol.t
    all_nodes = solution.powergrid.nodes
    all_node_names = collect(keys(all_nodes))
    
    # Separate generators from other nodes for clarity
    generator_names = []
    other_node_names = []
    
    for (name, node) in all_nodes
        # Check if this is a dynamic generator
        if typeof(node) in [FourthOrderEq, LinearPTO]
            push!(generator_names, name)
        else
            push!(other_node_names, name)
        end
    end
    
    # Create simple filename based on duration
    sim_duration = time_vector[end] - time_vector[1]
    base_filename = "$(filename_prefix)_$(round(Int, sim_duration))s"
    
    println("Saving full resolution simulation data...")
    println("Time span: $(time_vector[1]) - $(time_vector[end]) seconds")
    println("Total nodes: $(length(all_node_names))")
    println("Generators: $(length(generator_names)) - $(generator_names)")
    println("Other nodes: $(length(other_node_names)) - $(other_node_names[1:min(5, length(other_node_names))])")
    println("Variables: $(key_variables)")
    
    # Save metadata
    metadata_file = joinpath(output_dir, "$(base_filename)_metadata.json")
    metadata = Dict(
        "simulation_info" => Dict(
            "duration_sec" => sim_duration,
            "total_points" => length(time_vector),
            "dt_avg_sec" => sim_duration / (length(time_vector) - 1)
        ),
        "grid_info" => Dict(
            "all_nodes" => all_node_names,
            "generators" => generator_names,
            "other_nodes" => other_node_names,
            "variables" => string.(key_variables)
        ),
        "config" => config
    )
    
    open(metadata_file, "w") do f
        JSON.print(f, metadata, 2)
    end
    
    # Save time series data
    data_file = joinpath(output_dir, "$(base_filename)_data.csv")
    
    # Create DataFrame with time
    df = DataFrame(time = time_vector)
    
    # Add data for each variable and all nodes
    for var in key_variables
        for node_name in all_node_names
            try
                # Get full resolution data 
                full_data = solution(time_vector, node_name, var)
                
                # Handle complex numbers (like voltage)
                if eltype(full_data) <: Complex
                    df[!, "$(node_name)_$(var)_mag"] = abs.(full_data)
                    df[!, "$(node_name)_$(var)_angle"] = angle.(full_data)
                else
                    df[!, "$(node_name)_$(var)"] = full_data
                end
            catch e
                println("Warning: Could not extract :$(var) for $(node_name) - $(typeof(all_nodes[node_name]))")
            end
        end
    end
    
    CSV.write(data_file, df)
    
    println("Data saved to: $(data_file)")
    println("Metadata saved to: $(metadata_file)")
    
    return Dict(
        "data_file" => data_file,
        "metadata_file" => metadata_file,
        "base_filename" => base_filename
    )
end

"""
    save_generator_data(solution::PowerGridSolution, config=nothing; 
                        output_dir="./simulation_results", 
                        filename_prefix="generators",
                        key_variables=[:v, :ω, :p])

Save simulation results for generators only (like plotexample.jl does).
This matches the approach used in plotexample.jl for generator-specific analysis.

# Arguments
- `solution`: PowerGridSolution object from simulate()
- `config`: Configuration dictionary used for the simulation (optional)
- `output_dir`: Directory to save files (default: "./simulation_results")
- `filename_prefix`: Prefix for output files (default: "generators")
- `key_variables`: Variables to save (default: [:v, :ω, :p])

# Returns
Dictionary with file paths and generator information
"""
function save_generator_data(solution::PowerGridSolution, config=nothing; 
                           output_dir="./simulation_results", 
                           filename_prefix="generators",
                           key_variables=[:v, :ω, :p])
    
    # Create output directory if it doesn't exist
    if !isdir(output_dir)
        mkpath(output_dir)
    end
    
    # Get time vector
    time_vector = solution.dqsol.t
    all_nodes = solution.powergrid.nodes
    
    # Find generators only (like plotexample.jl does)
    generator_names = []
    for (name, node) in all_nodes
        if typeof(node) in [FourthOrderEq, LinearPTO]
            push!(generator_names, name)
        end
    end
    
    if isempty(generator_names)
        error("No generators found in the power grid!")
    end
    
    # Create filename based on duration
    sim_duration = time_vector[end] - time_vector[1]
    base_filename = "$(filename_prefix)_$(round(Int, sim_duration))s"
    
    println("Saving generator-only data...")
    println("Time span: $(time_vector[1]) - $(time_vector[end]) seconds")
    println("Generators: $(length(generator_names)) - $(generator_names)")
    println("Variables: $(key_variables)")
    
    # Save metadata
    metadata_file = joinpath(output_dir, "$(base_filename)_metadata.json")
    metadata = Dict(
        "simulation_info" => Dict(
            "duration_sec" => sim_duration,
            "total_points" => length(time_vector),
            "dt_avg_sec" => sim_duration / (length(time_vector) - 1)
        ),
        "grid_info" => Dict(
            "generators_only" => generator_names,
            "variables" => string.(key_variables),
            "approach" => "generator_focused_like_plotexample",
            "data_note" => "p = electrical power output, P_mech = mechanical power setpoint"
        ),
        "config" => config
    )
    
    open(metadata_file, "w") do f
        JSON.print(f, metadata, 2)
    end
    
    # Save time series data
    data_file = joinpath(output_dir, "$(base_filename)_data.csv")
    
    # Create DataFrame with time
    df = DataFrame(time = time_vector)
    
    # Add data for each variable and generator only
    for var in key_variables
        for gen_name in generator_names
            try
                # Get full resolution data 
                full_data = solution(time_vector, gen_name, var)
                
                # Handle complex numbers (like voltage)
                if eltype(full_data) <: Complex
                    df[!, "$(gen_name)_$(var)_mag"] = abs.(full_data)
                    df[!, "$(gen_name)_$(var)_angle"] = angle.(full_data)
                else
                    df[!, "$(gen_name)_$(var)"] = full_data
                end
            catch e
                println("Warning: Could not extract :$(var) for generator $(gen_name) - $(e)")
            end
        end
    end
    
    # Try to get mechanical power setpoint for FourthOrderEq generators  
    for gen_name in generator_names
        gen_node = all_nodes[gen_name]
        if typeof(gen_node) == FourthOrderEq
            try
                # For FourthOrderEq, the mechanical power P is a parameter, not a state variable
                # During step changes, this gets modified internally
                # Let's try to extract the internal mechanical power if available
                P_mech = fill(gen_node.P, length(time_vector))  # This is the initial setpoint
                df[!, "$(gen_name)_P_mech"] = P_mech
                println("Note: $(gen_name)_P_mech shows initial setpoint. For step changes, check fault parameters.")
            catch e
                println("Warning: Could not extract mechanical power setpoint for $(gen_name): $(e)")
            end
        end
    end
    
    CSV.write(data_file, df)
    
    println("Generator data saved to: $(data_file)")
    println("Metadata saved to: $(metadata_file)")
    println("Note: :p = electrical power output ($(minimum(df[!, "bus8_p"])) to $(maximum(df[!, "bus8_p"])) pu)")
    println("      P_mech = mechanical power setpoint (constant unless modified by step change)")
    
    return Dict(
        "data_file" => data_file,
        "metadata_file" => metadata_file,
        "base_filename" => base_filename,
        "generators" => generator_names
    )
end

"""
    load_sim_data(filename; data_dir="./simulation_results")

Load simulation data for plotting.

# Arguments
- `filename`: Base filename (without _data.csv extension)
- `data_dir`: Directory containing the data files

# Returns
- DataFrame with all simulation data
- Metadata dictionary
"""
function load_sim_data(filename; data_dir="./simulation_results")
    data_file = joinpath(data_dir, "$(filename)_data.csv")
    metadata_file = joinpath(data_dir, "$(filename)_metadata.json")
    
    # Load data
    df = CSV.read(data_file, DataFrame)
    
    # Load metadata
    metadata = nothing
    if isfile(metadata_file)
        metadata = JSON.parsefile(metadata_file)
    end
    
    return df, metadata
end

"""
    plot_frequency_comparison(data1, data2, label1="Case 1", label2="Case 2")

Create frequency deviation plot similar to the conference figure.
"""
function plot_frequency_comparison(data1, data2, label1="Case 1", label2="Case 2")
    # Get frequency columns (looking for ω variables)
    freq_cols1 = filter(x -> contains(string(x), "_ω"), names(data1))
    freq_cols2 = filter(x -> contains(string(x), "_ω"), names(data2))
    
    # Create simple plot data for manual plotting or use with Plots.jl
    println("Frequency deviation data ready for plotting")
    println("Available frequency columns in dataset 1: ", freq_cols1[1:min(3, length(freq_cols1))])
    println("Available frequency columns in dataset 2: ", freq_cols2[1:min(3, length(freq_cols2))])
    
    # Return the data for manual plotting
    plot_data = Dict()
    
    # Extract frequency data for key buses
    key_buses = ["bus1", "bus3", "bus6"]  # Adjust based on your system
    
    for bus in key_buses
        col1 = "$(bus)_ω"
        col2 = "$(bus)_ω"
        
        if col1 in freq_cols1 && col2 in freq_cols2
            # Convert from pu to Hz (assuming 60 Hz base)
            freq1_hz = (data1[!, col1] .- data1[1, col1]) .* 60
            freq2_hz = (data2[!, col2] .- data2[1, col2]) .* 60
            
            plot_data["$(bus)_$(label1)"] = (data1.time, freq1_hz)
            plot_data["$(bus)_$(label2)"] = (data2.time, freq2_hz)
        end
    end
    
    return plot_data
end
