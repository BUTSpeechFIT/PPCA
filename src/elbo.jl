# Computation of the Evidence Lower Bound (ELBO).
#
# Lucas Ondel 2021

"""
    elbo(model, X[, detailed = false])

Compute the Evidence Lower-BOund (ELBO) of the model. If `detailed` is
set to `true` returns a tuple `elbo, loglikelihood, KL`.
"""
function elbo(model, args...; detailed = false, stats_scale=1)
    llh = sum(loglikelihood(model, args...))*stats_scale

    params = Zygote.@ignore filter(isbayesparam, getparams(model))
    KL = sum(param -> EFD.kldiv(param.posterior, param.prior, μ = param._μ),
             params)
    detailed ? (llh - KL, llh, KL) : llh - KL
end

"""
    ∇elbo(model, args...[, stats_scale = 1])

Compute the natural gradient of the elbo w.r.t. to the posteriors'
parameters.
"""
function ∇elbo(model, args...; params, stats_scale = 1)
    P = Params([param._μ for param in params])
    𝓛, back = Zygote.pullback(() -> elbo(model, args..., stats_scale = stats_scale), P)

    μgrads = back(1)

    grads = Dict()
    for param in params
        ∂𝓛_∂μ = μgrads[param._μ]

        # The next two lines are equivalent to:
        #ξ = EFD.realform(param.posterior.param)
        #J = inv(FD.jacobian(param.posterior.param.ξ_to_η, ξ))

        η = EFD.naturalform(param.posterior.param)
        J = FD.jacobian(param.posterior.param.η_to_ξ, η)

        grads[param] = J * ∂𝓛_∂μ
    end
    𝓛, grads
end

"""
    gradstep(param_grad; lrate)

Update the parameters' posterior by doing one natural gradient steps.
"""
function gradstep(param_grad; lrate::Real)
    for (param, ∇𝓛) in param_grad
        ξ = param.posterior.param.ξ
        ξ[:] = ξ + lrate*∇𝓛
        param._μ[:] = EFD.gradlognorm(param.posterior)
    end
end

