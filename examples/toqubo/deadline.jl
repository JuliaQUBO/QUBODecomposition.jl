# SPDX-License-Identifier: MPL-2.0
module DeadlineExample
using JuMP, ToQUBO, QUBODecomposition, QUBODrivers, QUBOTools
import MathOptInterface as MOI

# The caller owns an absolute deadline. Compile without an internal optimizer,
# then dispatch the compiled model with only the remaining time. Source analysis
# is explicit for this small fixture; project every bit before evaluating it.
function run(; seconds=60.0,max_updates=5,budget=2,
    child=()->QUBODrivers.ExactSampler.Optimizer(),
    clock=()->time_ns()/1e9,checkpoint=_ -> nothing)
    deadline=clock()+seconds
    compiler=ToQUBO.Optimizer()
    model=Model(()->compiler)
    @variable(model,x[1:2],Bin)
    @objective(model,Max,5+3*x[1]+3*x[2])
    c=@constraint(model,x[1]+x[2]<=1)
    set_attribute(model,ToQUBO.Attributes.MaxPenaltyUpdates(),0)
    composite=QUBODecomposition.Optimizer(;child_optimizer=child,max_variables=budget,
        max_child_calls=100,max_candidate_evaluations=1+100*2^budget)
    composite.clock=clock
    dispatched_limits=Float64[]
    history=Any[]
    reason=:updates
    for k in 0:max_updates
        clock()>=deadline && (reason=:deadline;break)
        set_attribute(c,ToQUBO.Attributes.ConstraintEncodingPenaltyHint(),-0.1*10.0^k)
        MOI.Utilities.reset_optimizer(model)
        optimize!(model) # compilation time is charged before dispatch
        checkpoint(:compiled)
        clock()>=deadline && (reason=:deadline;break)
        target=MOI.get(compiler,ToQUBO.Attributes.TargetModel())
        map=MOI.copy_to(composite,target)
        checkpoint(:copied)
        remaining=deadline-clock()
        remaining<=0 && (reason=:deadline;break)
        MOI.set(composite,MOI.TimeLimitSec(),remaining)
        push!(dispatched_limits,remaining)
        MOI.optimize!(composite)
        checkpoint(:solved)
        MOI.get(composite,MOI.ResultCount())==0 && (reason=:empty;break)
        bits=Dict(v=>MOI.get(composite,MOI.VariablePrimal(),map[v])
            for v in MOI.get(target,MOI.ListOfVariableIndices()))
        decoded=ToQUBO.project_original_state(compiler,bits)
        a,b=decoded[index(x[1])],decoded[index(x[2])]
        residual=a+b-1
        source_value=5+3*a+3*b
        push!(history,(;bits=copy(bits),decoded=[a,b],residual,source_value,
            penalized_value=MOI.get(composite,MOI.ObjectiveValue()),
            status=MOI.get(composite,MOI.TerminationStatus())))
        checkpoint(:checked) # feasibility work is charged before the next round
        clock()>=deadline && (reason=:deadline;break)
        if residual<=1e-6
            reason=:feasible;break
        end
    end
    # A synchronous opaque child may overrun. Checks prevent subsequent dispatch;
    # they cannot preempt that child. CompilationTime is only the last compile.
    return (;reason,history,dispatched_limits,deadline,
        last_compilation_sec=MOI.get(compiler,ToQUBO.Attributes.CompilationTime()),
        composite_effective_sec=QUBODrivers.effective_time(composite))
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    println(DeadlineExample.run())
end
