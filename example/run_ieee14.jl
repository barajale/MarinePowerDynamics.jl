#!/usr/bin/env julia

using Pkg
Pkg.activate(joinpath(@__DIR__, "env"))
Pkg.instantiate()

using CSV
using DataFrames
using MarinePowerDynamics
using OrderedCollections: OrderedDict
using Plots

include(joinpath(@__DIR__, "plotting_utils.jl"))

const _SBASE = 100e6
const _PTO_RECORD = joinpath(@__DIR__, "RM3", "linear_pto_heave.json")

function build_ieee15_grid()
    buses = OrderedDict(
        "bus1"  => FourthOrderEq(T_d_dash = 7.4, D = 2, X_d = 0.8979, X_q = 0.646, Ω = 50,
                                 X_d_dash = 0.2995, T_q_dash = 0.1, X_q_dash = 0.646,
                                 P = 2.32, H = 5.148, E_f = 1),
        "bus2"  => SlackAlgebraic(U = 1),
        "bus3"  => FourthOrderEq(T_d_dash = 6.1, D = 2, X_d = 1.05, X_q = 0.98, Ω = 50,
                                 X_d_dash = 0.185, T_q_dash = 0.4, X_q_dash = 0.36,
                                 P = -0.942, H = 6.54, E_f = 1),
        "bus4"  => PQAlgebraic(P = -0.478, Q = -0.0),
        "bus5"  => PQAlgebraic(P = -0.076, Q = -0.016),
        "bus6"  => FourthOrderEq(T_d_dash = 4.75, D = 2, X_d = 1.25, X_q = 1.22, Ω = 50,
                                 X_d_dash = 0.232, T_q_dash = 1.6, X_q_dash = 0.715,
                                 P = -0.122, H = 5.06, E_f = 1),
        "bus7"  => PQAlgebraic(P = -0.0, Q = -0.0),
        "bus8"  => FourthOrderEq(T_d_dash = 4.75, D = 2, X_d = 1.25, X_q = 1.22, Ω = 50,
                                 X_d_dash = 0.232, T_q_dash = 1.6, X_q_dash = 0.715,
                                 P = 0.0, H = 5.06, E_f = 1),
        "bus9"  => PQAlgebraic(P = -0.295, Q = -0.166),
        "bus10" => PQAlgebraic(P = -0.09, Q = -0.058),
        "bus11" => PQAlgebraic(P = -0.035, Q = -0.018),
        "bus12" => PQAlgebraic(P = -0.061, Q = -0.016),
        "bus13" => PQAlgebraic(P = -0.135, Q = -0.058),
        "bus14" => PQAlgebraic(P = -0.149, Q = -0.05),
        "bus15" => LinearPTO(τ_P = 0.05,
                              τ_Q = 2.0,
                              K_P = 0.05,
                              K_Q = 0.01,
                              V_r = 1.0,
                              Q = 0.0,
                              η = 0.80,
                              scaling_factor = 1 / _SBASE,
                              json_file = _PTO_RECORD),
    )

    branches = OrderedDict(
        "branch1"  => PiModelLine(from = "bus1",  to = "bus2",  y = 4.999131600798035 - 15.263086523179553im, y_shunt_km = 0.0528 / 2, y_shunt_mk = 0.0528 / 2),
        "branch2"  => PiModelLine(from = "bus1",  to = "bus5",  y = 1.025897454970189 - 4.234983682334831im,  y_shunt_km = 0.0492 / 2, y_shunt_mk = 0.0492 / 2),
        "branch3"  => PiModelLine(from = "bus2",  to = "bus3",  y = 1.1350191923073958 - 4.781863151757718im, y_shunt_km = 0.0438 / 2, y_shunt_mk = 0.0438 / 2),
        "branch4"  => PiModelLine(from = "bus2",  to = "bus4",  y = 1.686033150614943 - 5.115838325872083im,  y_shunt_km = 0.0340 / 2, y_shunt_mk = 0.0340 / 2),
        "branch5"  => PiModelLine(from = "bus2",  to = "bus5",  y = 1.7011396670944048 - 5.193927397969713im, y_shunt_km = 0.0346 / 2, y_shunt_mk = 0.0346 / 2),
        "branch6"  => PiModelLine(from = "bus3",  to = "bus4",  y = 1.9859757099255606 - 5.0688169775939205im, y_shunt_km = 0.0128 / 2, y_shunt_mk = 0.0128 / 2),
        "branch7"  => StaticLine(from = "bus4",  to = "bus5",  Y = 6.840980661495672 - 21.578553981691588im),
        "branch8"  => Transformer(from = "bus4",  to = "bus7",  y = 0.0 - 4.781943381790359im, t_ratio = 0.978),
        "branch9"  => Transformer(from = "bus4",  to = "bus9",  y = 0.0 - 1.7979790715236075im, t_ratio = 0.969),
        "branch10" => Transformer(from = "bus5",  to = "bus6",  y = 0.0 - 3.967939052456154im, t_ratio = 0.932),
        "branch11" => StaticLine(from = "bus6",  to = "bus11", Y = 1.9550285631772604 - 4.0940743442404415im),
        "branch12" => StaticLine(from = "bus6",  to = "bus12", Y = 1.525967440450974 - 3.1759639650294003im),
        "branch13" => StaticLine(from = "bus6",  to = "bus13", Y = 3.0989274038379877 - 6.102755448193116im),
        "branch14" => StaticLine(from = "bus7",  to = "bus8",  Y = 0.0 - 5.676979846721544im),
        "branch15" => StaticLine(from = "bus7",  to = "bus9",  Y = 0.0 - 9.09008271975275im),
        "branch16" => StaticLine(from = "bus9",  to = "bus10", Y = 3.902049552447428 - 10.365394127060915im),
        "branch17" => StaticLine(from = "bus9",  to = "bus14", Y = 1.4240054870199312 - 3.0290504569306034im),
        "branch18" => StaticLine(from = "bus10", to = "bus11", Y = 1.8808847537003996 - 4.402943749460521im),
        "branch19" => StaticLine(from = "bus12", to = "bus13", Y = 2.4890245868219187 - 2.251974626172212im),
        "branch20" => StaticLine(from = "bus13", to = "bus14", Y = 1.1369941578063267 - 2.314963475105352im),
        "branch21" => StaticLine(from = "bus8",  to = "bus15", Y = 1.1369941578063267 - 2.314963475105352im),
    )

    PowerGrid(buses, branches)
end

function build_ieee14_grid()
    buses = OrderedDict(
        "bus1"  => FourthOrderEq(T_d_dash = 7.4, D = 2, X_d = 0.8979, X_q = 0.646, Ω = 50,
                                 X_d_dash = 0.2995, T_q_dash = 0.1, X_q_dash = 0.646,
                                 P = 2.32, H = 5.148, E_f = 1),
        "bus2"  => SlackAlgebraic(U = 1),
        "bus3"  => FourthOrderEq(T_d_dash = 6.1, D = 2, X_d = 1.05, X_q = 0.98, Ω = 50,
                                 X_d_dash = 0.185, T_q_dash = 0.4, X_q_dash = 0.36,
                                 P = -0.942, H = 6.54, E_f = 1),
        "bus4"  => PQAlgebraic(P = -0.478, Q = -0.0),
        "bus5"  => PQAlgebraic(P = -0.076, Q = -0.016),
        "bus6"  => FourthOrderEq(T_d_dash = 4.75, D = 2, X_d = 1.25, X_q = 1.22, Ω = 50,
                                 X_d_dash = 0.232, T_q_dash = 1.6, X_q_dash = 0.715,
                                 P = -0.122, H = 5.06, E_f = 1),
        "bus7"  => PQAlgebraic(P = -0.0, Q = -0.0),
        "bus8"  => FourthOrderEq(T_d_dash = 4.75, D = 2, X_d = 1.25, X_q = 1.22, Ω = 50,
                                 X_d_dash = 0.232, T_q_dash = 1.6, X_q_dash = 0.715,
                                 P = 0.0, H = 5.06, E_f = 1),
        "bus9"  => PQAlgebraic(P = -0.295, Q = -0.166),
        "bus10" => PQAlgebraic(P = -0.09, Q = -0.058),
        "bus11" => PQAlgebraic(P = -0.035, Q = -0.018),
        "bus12" => PQAlgebraic(P = -0.061, Q = -0.016),
        "bus13" => PQAlgebraic(P = -0.135, Q = -0.058),
        "bus14" => PQAlgebraic(P = -0.149, Q = -0.05),
    )

    branches = OrderedDict(
        "branch1"  => PiModelLine(from = "bus1",  to = "bus2",  y = 4.999131600798035 - 15.263086523179553im, y_shunt_km = 0.0528 / 2, y_shunt_mk = 0.0528 / 2),
        "branch2"  => PiModelLine(from = "bus1",  to = "bus5",  y = 1.025897454970189 - 4.234983682334831im,  y_shunt_km = 0.0492 / 2, y_shunt_mk = 0.0492 / 2),
        "branch3"  => PiModelLine(from = "bus2",  to = "bus3",  y = 1.1350191923073958 - 4.781863151757718im, y_shunt_km = 0.0438 / 2, y_shunt_mk = 0.0438 / 2),
        "branch4"  => PiModelLine(from = "bus2",  to = "bus4",  y = 1.686033150614943 - 5.115838325872083im,  y_shunt_km = 0.0340 / 2, y_shunt_mk = 0.0340 / 2),
        "branch5"  => PiModelLine(from = "bus2",  to = "bus5",  y = 1.7011396670944048 - 5.193927397969713im, y_shunt_km = 0.0346 / 2, y_shunt_mk = 0.0346 / 2),
        "branch6"  => PiModelLine(from = "bus3",  to = "bus4",  y = 1.9859757099255606 - 5.0688169775939205im, y_shunt_km = 0.0128 / 2, y_shunt_mk = 0.0128 / 2),
        "branch7"  => StaticLine(from = "bus4",  to = "bus5",  Y = 6.840980661495672 - 21.578553981691588im),
        "branch8"  => Transformer(from = "bus4",  to = "bus7",  y = 0.0 - 4.781943381790359im, t_ratio = 0.978),
        "branch9"  => Transformer(from = "bus4",  to = "bus9",  y = 0.0 - 1.7979790715236075im, t_ratio = 0.969),
        "branch10" => Transformer(from = "bus5",  to = "bus6",  y = 0.0 - 3.967939052456154im, t_ratio = 0.932),
        "branch11" => StaticLine(from = "bus6",  to = "bus11", Y = 1.9550285631772604 - 4.0940743442404415im),
        "branch12" => StaticLine(from = "bus6",  to = "bus12", Y = 1.525967440450974 - 3.1759639650294003im),
        "branch13" => StaticLine(from = "bus6",  to = "bus13", Y = 3.0989274038379877 - 6.102755448193116im),
        "branch14" => StaticLine(from = "bus7",  to = "bus8",  Y = 0.0 - 5.676979846721544im),
        "branch15" => StaticLine(from = "bus7",  to = "bus9",  Y = 0.0 - 9.09008271975275im),
        "branch16" => StaticLine(from = "bus9",  to = "bus10", Y = 3.902049552447428 - 10.365394127060915im),
        "branch17" => StaticLine(from = "bus9",  to = "bus14", Y = 1.4240054870199312 - 3.0290504569306034im),
        "branch18" => StaticLine(from = "bus10", to = "bus11", Y = 1.8808847537003996 - 4.402943749460521im),
        "branch19" => StaticLine(from = "bus12", to = "bus13", Y = 2.4890245868219187 - 2.251974626172212im),
        "branch20" => StaticLine(from = "bus13", to = "bus14", Y = 1.1369941578063267 - 2.314963475105352im),
    )

    PowerGrid(buses, branches)
end

function simulate_flat_run(pg::PowerGrid; fault_line = "branch1", fault_span = (60.1, 60.2), timespan = (0.0, 60.0))
    op = find_operationpoint(pg; solve_powerflow = true)
    perturbation = LineFailure(line_name = fault_line, tspan_fault = fault_span)
    sol = simulate(perturbation, pg, op, timespan)
    return sol, op
end

function save_plots(sol15, sol14, output_dir)
    grid_plot = plot_grid_vars(sol15)
    savefig(grid_plot, joinpath(output_dir, "ieee15_grid_overview.png"))

    bus15_p = plot_bus_var(sol15, "bus15", :p; ylabel = "P [p.u.]", label = "WEC Bus")
    savefig(bus15_p, joinpath(output_dir, "ieee15_bus15_active_power.png"))

    bus5_dashboard = plot_bus_all_vars(sol15, "bus5")
    savefig(bus5_dashboard, joinpath(output_dir, "ieee15_bus5_dashboard.png"))

    comparison = plot_bus_compare(sol15, sol14, "bus8"; label1 = "IEEE 15", label2 = "IEEE 14")
    savefig(comparison, joinpath(output_dir, "bus8_ieee15_vs_ieee14.png"))
end

function save_data(sol15, output_dir)
    csv_path = joinpath(output_dir, "ieee15_flat_run.csv")
    save_solution_dataframe(csv_path, sol15;
                            vars = (:v, :ω, :p, :q),
                            buses = ["bus1", "bus5", "bus15"])

    sample_path = joinpath(output_dir, "ieee15_bus1_v_omega.csv")
    sample_df = solution_dataframe(sol15;
                                   vars = (:v, :ω),
                                   buses = ["bus1"],
                                   time_grid = 0:0.1:60)
    CSV.write(sample_path, sample_df)
end

function main(args)
    output_dir = length(args) >= 1 ? abspath(args[1]) : joinpath(@__DIR__, "output")
    mkpath(output_dir)

    @info "Output directory" output_dir

    @info "Building IEEE 15-bus grid with Linear PTO"
    grid15 = build_ieee15_grid()
    sol15, op15 = simulate_flat_run(grid15)
    @info "Flat-run simulation completed" retcode = sol15.dqsol.retcode

    @info "Building reference IEEE 14-bus grid"
    grid14 = build_ieee14_grid()
    sol14, _ = simulate_flat_run(grid14)

    @info "Saving figures"
    save_plots(sol15, sol14, output_dir)

    @info "Saving sampled data"
    save_data(sol15, output_dir)

    @info "Done"
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
