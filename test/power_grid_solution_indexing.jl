using Test
using MarinePowerDynamics
using Graphs
import DiffEqBase: AbstractTimeseriesSolution
import SciMLBase

struct DummySolution <: AbstractTimeseriesSolution
    retcode::SciMLBase.ReturnCode
end

@testset "PowerGridSolution indexing" begin
    pg = PowerGrid(SimpleGraph(1), [1], [])
    dummy = DummySolution(SciMLBase.ReturnCode.Success)
    sol = PowerGridSolution(dummy, pg)
    @test_throws StateError sol(0.0, 2, :v)
end

