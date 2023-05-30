module ComponentArraysGPUArraysExt

using ComponentArrays, LinearAlgebra
isdefined(Base, :get_extension) ? (using GPUArrays) : (using ..GPUArrays)

const AbstractGPUArrayOrAdj = Union{<:GPUArrays.AbstractGPUArray{T, N}, Adjoint{T, <:GPUArrays.AbstractGPUArray{T, N}}, Transpose{T, <:GPUArrays.AbstractGPUArray{T, N}}} where {T, N}
const GPUComponentArray = ComponentArray{T,N,<:AbstractGPUArrayOrAdj{T, N},Ax} where {T,N,Ax}
const GPUComponentVector{T,Ax} = ComponentArray{T,1,<:AbstractGPUArrayOrAdj{T, 1},Ax}
const GPUComponentMatrix{T,Ax} = ComponentArray{T,2,<:AbstractGPUArrayOrAdj{T, 2},Ax}
const GPUComponentVecorMat{T,Ax} = Union{GPUComponentVector{T,Ax},GPUComponentMatrix{T,Ax}}

GPUArrays.backend(x::ComponentArray) = GPUArrays.backend(getdata(x))

function GPUArrays.Adapt.adapt_structure(to, x::ComponentArray)
    data = GPUArrays.Adapt.adapt_structure(to, getdata(x))
    return ComponentArray(data, getaxes(x))
end

GPUArrays.Adapt.adapt_storage(::Type{ComponentArray{T,N,A,Ax}}, xs::AT) where {T,N,A,Ax,AT<:AbstractArray} =
    GPUArrays.Adapt.adapt_storage(A, xs)

function Base.fill!(A::GPUComponentArray{T}, x) where {T}
    length(A) == 0 && return A
    GPUArrays.gpu_call(A, convert(T, x)) do ctx, a, val
        idx = GPUArrays.@linearidx(a)
        @inbounds a[idx] = val
        return
    end
    A
end

LinearAlgebra.dot(x::GPUComponentArray, y::GPUComponentArray) = dot(getdata(x), getdata(y))
LinearAlgebra.norm(ca::GPUComponentArray, p::Real) = norm(getdata(ca), p)
function LinearAlgebra.rmul!(ca::GPUComponentArray, b::Number)
    GPUArrays.generic_rmul!(getdata(ca), b)
    return ca
end

function Base.map(f, x::GPUComponentArray, args...)
    data = map(f, getdata(x), getdata.(args)...)
    return ComponentArray(data, getaxes(x))
end
function Base.map(f, x::GPUComponentArray, args::Vararg{Union{Base.AbstractBroadcasted, AbstractArray}})
    data = map(f, getdata(x), map(getdata, args)...)
    return ComponentArray(data, getaxes(x))
end

# We need all of these to avoid method ambiguities
function Base.mapreduce(f, op, x::GPUComponentArray; kwargs...)
    return mapreduce(f, op, getdata(x); kwargs...)
end
function Base.mapreduce(f, op, x::GPUComponentArray, args...; kwargs...)
    return mapreduce(f, op, getdata(x), map(getdata, args)...; kwargs...)
end
function Base.mapreduce(f, op, x::GPUComponentArray, args::Vararg{Union{Base.AbstractBroadcasted, AbstractArray}}; kwargs...)
    return mapreduce(f, op, getdata(x), map(getdata, args)...; kwargs...)
end

# These are all stolen from GPUArrays.j;
Base.any(A::GPUComponentArray{Bool}) = mapreduce(identity, |, getdata(A))
Base.all(A::GPUComponentArray{Bool}) = mapreduce(identity, &, getdata(A))

Base.any(f::Function, A::GPUComponentArray) = mapreduce(f, |, getdata(A))
Base.all(f::Function, A::GPUComponentArray) = mapreduce(f, &, getdata(A))

Base.count(pred::Function, A::GPUComponentArray; dims=:, init=0) =
    mapreduce(pred, Base.add_sum, getdata(A); init=init, dims=dims)

# avoid calling into `initarray!`
for (fname, op) in [(:sum, :(Base.add_sum)), (:prod, :(Base.mul_prod)),
                    (:maximum, :(Base.max)), (:minimum, :(Base.min)),
                    (:all, :&),              (:any, :|)]
    fname! = Symbol(fname, '!')
    @eval begin
        Base.$(fname!)(f::Function, r::GPUComponentArray, A::GPUComponentArray{T}) where T =
            GPUArrays.mapreducedim!(f, $(op), getdata(r), getdata(A); init=neutral_element($(op), T))
    end
end

function ComponentArray(nt::NamedTuple{names,<:Tuple{Vararg{Union{GPUArrays.AbstractGPUArray,GPUComponentArray}}}}) where {names}
    T = recursive_eltype(nt)
    gpuarray = getdata(first(nt))
    G = Base.typename(typeof(gpuarray)).wrapper  # SciMLBase.parameterless_type(gpuarray)
    return GPUArrays.adapt(G, ComponentArray(NamedTuple{names}(map(GPUArrays.adapt(Array{T}), nt))))
end

function LinearAlgebra.mul!(C::GPUComponentVecorMat,
    A::GPUComponentVecorMat,
    B::GPUComponentVecorMat, a::Number, b::Number)
    return GPUArrays.generic_matmatmul!(C, getdata(A), getdata(B), a, b)
end

function LinearAlgebra.mul!(C::GPUComponentVecorMat,
    A::AbstractGPUArrayOrAdj,
    B::GPUComponentVecorMat, a::Number, b::Number)
    return GPUArrays.generic_matmatmul!(C, A, getdata(B), a, b)
end

function LinearAlgebra.mul!(C::GPUComponentVecorMat,
    A::GPUComponentVecorMat,
    B::AbstractGPUArrayOrAdj, a::Number, b::Number)
    return GPUArrays.generic_matmatmul!(C, getdata(A), B, a, b)
end

function LinearAlgebra.mul!(C::GPUComponentVecorMat,
    A::AbstractGPUArrayOrAdj,
    B::AbstractGPUArrayOrAdj, a::Number, b::Number)
    return GPUArrays.generic_matmatmul!(C, A, B, a, b)
end

end
