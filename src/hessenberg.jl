# This file is a part of Julia. License is MIT: https://julialang.org/license

######################################################################################
# Upper-Hessenberg matrices H+μI, analogous to the UpperTriangular type

"""
    UpperHessenberg(A::AbstractMatrix)

Construct an `UpperHessenberg` view of the matrix `A`.
Entries of `A` below the first subdiagonal are ignored.

!!! compat "Julia 1.3"
    This type was added in Julia 1.3.

Efficient algorithms are implemented for `H \\ b`, `det(H)`, and similar.

See also the [`hessenberg`](@ref) function to factor any matrix into a similar
upper-Hessenberg matrix.

If `F::Hessenberg` is the factorization object, the unitary matrix can be accessed
with `F.Q` and the Hessenberg matrix with `F.H`. When `Q` is extracted, the resulting
type is the `HessenbergQ` object, and may be converted to a regular matrix with
[`convert(Array, _)`](@ref) (or `Array(_)` for short).

Iterating the decomposition produces the factors `F.Q` and `F.H`.

# Examples
```jldoctest
julia> A = [1 2 3 4; 5 6 7 8; 9 10 11 12; 13 14 15 16]
4×4 Matrix{Int64}:
  1   2   3   4
  5   6   7   8
  9  10  11  12
 13  14  15  16

julia> UpperHessenberg(A)
4×4 UpperHessenberg{Int64, Matrix{Int64}}:
 1   2   3   4
 5   6   7   8
 ⋅  10  11  12
 ⋅   ⋅  15  16
```
"""
struct UpperHessenberg{T,S<:AbstractMatrix{T}} <: AbstractMatrix{T}
    data::S

    function UpperHessenberg{T,S}(data) where {T,S<:AbstractMatrix{T}}
        require_one_based_indexing(data)
        new{T,S}(data)
    end
end
UpperHessenberg(H::UpperHessenberg) = H
UpperHessenberg{T}(A::AbstractMatrix) where {T} = UpperHessenberg(convert(AbstractMatrix{T}, A))
UpperHessenberg{T}(H::UpperHessenberg) where {T} = UpperHessenberg{T}(H.data)
UpperHessenberg(A::AbstractMatrix) = UpperHessenberg{eltype(A),typeof(A)}(A)
Matrix(H::UpperHessenberg{T}) where {T} = Matrix{T}(H)
Array(H::UpperHessenberg) = Matrix(H)
size(H::UpperHessenberg) = size(H.data)
axes(H::UpperHessenberg) = axes(H.data)
parent(H::UpperHessenberg) = H.data

# similar behaves like UpperTriangular
similar(H::UpperHessenberg, ::Type{T}) where {T} = UpperHessenberg(similar(H.data, T))
similar(H::UpperHessenberg, ::Type{T}, dims::Dims{N}) where {T,N} = similar(H.data, T, dims)

AbstractMatrix{T}(H::UpperHessenberg) where {T} = UpperHessenberg{T}(H)
AbstractMatrix{T}(H::UpperHessenberg{T}) where {T} = copy(H)

Base.dataids(A::UpperHessenberg) = Base.dataids(parent(A))
Base.unaliascopy(A::UpperHessenberg) = UpperHessenberg(Base.unaliascopy(parent(A)))

copy(H::UpperHessenberg) = UpperHessenberg(copy(H.data))
real(H::UpperHessenberg{<:Complex}) = UpperHessenberg(triu!(real(H.data),-1))
imag(H::UpperHessenberg) = UpperHessenberg(triu!(imag(H.data),-1))

Base.@constprop :aggressive function istriu(A::UpperHessenberg, k::Integer=0)
    k <= -1 && return true
    return _istriu(A, k)
end
# additional indirection to dispatch to optimized method for banded parents (defined in special.jl)
@inline function _istriu(A::UpperHessenberg, k)
    P = parent(A)
    m = size(A, 1)
    for j in firstindex(P,2):min(m + k - 1, lastindex(P,2))
        Prows = @view P[max(begin, j - k + 1):min(j+1,end), j]
        _iszero(Prows) || return false
    end
    return true
end

function Matrix{T}(H::UpperHessenberg) where T
    m,n = size(H)
    return triu!(copyto!(Matrix{T}(undef, m, n), H.data), -1)
end

Base.isassigned(H::UpperHessenberg, i::Int, j::Int) =
    i <= j+1 ? isassigned(H.data, i, j) : true

Base.@propagate_inbounds getindex(H::UpperHessenberg{T}, i::Int, j::Int) where {T} =
    i <= j+1 ? convert(T, H.data[i,j]) : zero(T)

Base._reverse(A::UpperHessenberg, dims) = reverse!(Matrix(A); dims)

Base.@propagate_inbounds function setindex!(A::UpperHessenberg, x, i::Integer, j::Integer)
    if i > j+1
        iszero(x) || throw(ArgumentError(LazyString("cannot set index in the lower triangular part ",
            lazy"($i, $j) of an UpperHessenberg matrix to a nonzero value ($x)")))
    else
        A.data[i,j] = x
    end
    return A
end

function Base.replace_in_print_matrix(A::UpperHessenberg, i::Integer, j::Integer, s::AbstractString)
    return i <= j+1 ? s : Base.replace_with_centered_mark(s)
end

Base.copy(A::Adjoint{<:Any,<:UpperHessenberg}) = tril!(adjoint!(similar(A.parent.data), A.parent.data), 1)
Base.copy(A::Transpose{<:Any,<:UpperHessenberg}) = tril!(transpose!(similar(A.parent.data), A.parent.data), 1)

-(A::UpperHessenberg) = UpperHessenberg(-A.data)
rmul!(H::UpperHessenberg, x::Number) = (rmul!(H.data, x); H)
lmul!(x::Number, H::UpperHessenberg) = (lmul!(x, H.data); H)

fillstored!(H::UpperHessenberg, x) = (fillband!(H.data, x, -1, size(H,2)-1); H)

function fillband!(H::UpperHessenberg, x, l, u)
    if l > u
        return H
    end
    if l < -1 && !iszero(x)
        throw_fillband_error(l, u, x)
    end
    fillband!(H.data, x, l, u)
    return H
end

+(A::UpperHessenberg, B::UpperHessenberg) = UpperHessenberg(A.data+B.data)
-(A::UpperHessenberg, B::UpperHessenberg) = UpperHessenberg(A.data-B.data)

for T = (:UniformScaling, :Diagonal, :Bidiagonal, :Tridiagonal, :SymTridiagonal,
         :UpperTriangular, :UnitUpperTriangular)
    for op = (:+, :-)
        @eval begin
            $op(H::UpperHessenberg, x::$T) = UpperHessenberg($op(H.data, x))
            $op(x::$T, H::UpperHessenberg) = UpperHessenberg($op(x, H.data))
        end
    end
end

for T = (:Number, :UniformScaling)
    @eval begin
        *(H::UpperHessenberg, x::$T) = UpperHessenberg(H.data * x)
        *(x::$T, H::UpperHessenberg) = UpperHessenberg(x * H.data)
        /(H::UpperHessenberg, x::$T) = UpperHessenberg(H.data / x)
        \(x::$T, H::UpperHessenberg) = UpperHessenberg(x \ H.data)
    end
end

mul(H::UpperHessenberg, D::Diagonal) = UpperHessenberg(H.data * D)
mul(D::Diagonal, H::UpperHessenberg) = UpperHessenberg(D * H.data)
function mul(H::UpperHessenberg, U::UpperOrUnitUpperTriangular)
    HH = mul!(matprod_dest(H, U, promote_op(matprod, eltype(H), eltype(U))), H, U)
    UpperHessenberg(HH)
end
function mul(U::UpperOrUnitUpperTriangular, H::UpperHessenberg)
    HH = mul!(matprod_dest(U, H, promote_op(matprod, eltype(U), eltype(H))), U, H)
    UpperHessenberg(HH)
end

/(H::UpperHessenberg, D::Diagonal) = UpperHessenberg(H.data / D)
function /(H::UpperHessenberg, U::UpperTriangular)
    HH = _rdiv!(matprod_dest(H, U, promote_op(/, eltype(H), eltype(U))), H, U)
    UpperHessenberg(HH)
end
\(D::Diagonal, H::UpperHessenberg) = UpperHessenberg(D \ H.data)
function /(H::UpperHessenberg, U::UnitUpperTriangular)
    HH = _rdiv!(matprod_dest(H, U, promote_op(/, eltype(H), eltype(U))), H, U)
    UpperHessenberg(HH)
end

function \(U::UpperTriangular, H::UpperHessenberg)
    HH = ldiv!(matprod_dest(U, H, promote_op(\, eltype(U), eltype(H))), U, H)
    UpperHessenberg(HH)
end
function \(U::UnitUpperTriangular, H::UpperHessenberg)
    HH = ldiv!(matprod_dest(U, H, promote_op(\, eltype(U), eltype(H))), U, H)
    UpperHessenberg(HH)
end

AdjUpperHessenberg{T,S<:UpperHessenberg{T}} = Adjoint{T, S}
TransUpperHessenberg{T,S<:UpperHessenberg{T}} = Transpose{T, S}
AdjOrTransUpperHessenberg{T,S<:UpperHessenberg{T}} = AdjOrTrans{T, S}

function (\)(H::Union{UpperHessenberg,AdjOrTransUpperHessenberg}, B::AbstractVecOrMat)
    TFB = typeof(oneunit(eltype(H)) \ oneunit(eltype(B)))
    return ldiv!(H, copy_similar(B, TFB))
end

(/)(B::AbstractMatrix, H::UpperHessenberg) = _rdiv(B, H)
(/)(B::AbstractMatrix, H::AdjUpperHessenberg) = _rdiv(B, H)
(/)(B::AbstractMatrix, H::TransUpperHessenberg) = _rdiv(B, H)
function _rdiv(B, H)
    TFB = typeof(oneunit(eltype(B)) / oneunit(eltype(H)))
    return rdiv!(copy_similar(B, TFB), H)
end

ldiv!(H::AdjOrTransUpperHessenberg, B::AbstractVecOrMat) =
    (rdiv!(wrapperop(H)(B), parent(H)); B)
rdiv!(B::AbstractVecOrMat, H::AdjOrTransUpperHessenberg) =
    (ldiv!(parent(H), wrapperop(H)(B)); B)

# fix method ambiguities for right division, from adjtrans.jl:
/(u::AdjointAbsVec, A::UpperHessenberg) = adjoint(adjoint(A) \ u.parent)
/(u::TransposeAbsVec, A::UpperHessenberg) = transpose(transpose(A) \ u.parent)
/(u::AdjointAbsVec, A::AdjUpperHessenberg) = adjoint(adjoint(A) \ u.parent)
/(u::TransposeAbsVec, A::TransUpperHessenberg) = transpose(transpose(A) \ u.parent)
/(u::AdjointAbsVec, A::TransUpperHessenberg) = adjoint(conj(A.parent) \ u.parent) # technically should be adjoint(copy(adjoint(copy(A))) \ u.parent)
/(u::TransposeAbsVec, A::AdjUpperHessenberg) = transpose(conj(A.parent) \ u.parent)

# Solving (H+µI)x = b: we can do this in O(m²) time and O(m) memory
# (in-place in x) by the RQ algorithm from:
#
#    G. Henry, "The shifted Hessenberg system solve computation," Tech. Rep. 94–163,
#    Center for Appl. Math., Cornell University (1994).
#
# as reviewed in
#
#    C. Beattie et al., "A note on shifted Hessenberg systems and frequency
#    response computation," ACM Trans. Math. Soft. 38, pp. 12:6–12:16 (2011)
#
# (Note, however, that there is apparently a typo in Algorithm 1 of the
#  Beattie paper: the Givens rotation uses u(k), not H(k,k) - σ.)
#
# Essentially, it works by doing a Givens RQ factorization of H+µI from
# right to left, and doing backsubstitution *simultaneously*.

# solve (H+μI)X = B, storing result in B
function ldiv!(F::UpperHessenberg, B::AbstractVecOrMat; shift::Number=false)
    checksquare(F)
    m = size(F,1)
    m != size(B,1) && throw(DimensionMismatch(lazy"wrong right-hand-side # rows != $m"))
    require_one_based_indexing(B)
    n = size(B,2)
    H = F.data
    μ = shift
    u = Vector{typeof(zero(eltype(H))+μ)}(undef, m) # for last rotated col of H-μI
    copyto!(u, 1, H, m*(m-1)+1, m) # u .= H[:,m]
    u[m] += μ
    X = B # not a copy, just rename to match paper
    cs = Vector{Tuple{real(eltype(u)),eltype(u)}}(undef, length(u)) # store Givens rotations
    @inbounds for k = m:-1:2
        c, s, ρ = givensAlgorithm(u[k], H[k,k-1])
        cs[k] = (c, s)
        for i = 1:n
            X[k,i] /= ρ
            t₁ = s * X[k,i]; t₂ = c * X[k,i]
            @simd for j = 1:k-2
                X[j,i] -= u[j]*t₂ + H[j,k-1]*t₁
            end
            X[k-1,i] -= u[k-1]*t₂ + (H[k-1,k-1] + μ) * t₁
        end
        @simd for j = 1:k-2
            u[j] = H[j,k-1]*c - u[j]*s'
        end
        u[k-1] = (H[k-1,k-1] + μ) * c - u[k-1]*s'
    end
    for i = 1:n
        τ₁ = X[1,i] / u[1]
        @inbounds for j = 2:m
            τ₂ = X[j,i]
            c, s = cs[j]
            X[j-1,i] = c*τ₁ + s*τ₂
            τ₁ = c*τ₂ - s'τ₁
        end
        X[m,i] = τ₁
    end
    return X
end

# solve X(H+μI) = B, storing result in B
#
# Note: this can be derived from the Henry (1994) algorithm
# by transformation to F(Hᵀ+µI)F FXᵀ = FBᵀ, where
# F is the permutation matrix that reverses the order
# of rows/cols.  Essentially, we take the ldiv! algorithm,
# swap indices of H and X to transpose, and reverse the
# order of the H indices (or the order of the loops).
function rdiv!(B::AbstractMatrix, F::UpperHessenberg; shift::Number=false)
    checksquare(F)
    m = size(F,1)
    m != size(B,2) && throw(DimensionMismatch(lazy"wrong right-hand-side # cols != $m"))
    require_one_based_indexing(B)
    n = size(B,1)
    H = F.data
    μ = shift
    u = Vector{typeof(zero(eltype(H))+μ)}(undef, m) # for last rotated row of H-μI
    u .= @view H[1,:]
    u[1] += μ
    X = B # not a copy, just rename to match paper
    cs = Vector{Tuple{real(eltype(u)),eltype(u)}}(undef, length(u)) # store Givens rotations
    @inbounds for k = 1:m-1
        c, s, ρ = givensAlgorithm(u[k], H[k+1,k])
        cs[k] = (c, s)
        for i = 1:n
            X[i,k] /= ρ
            t₁ = s * X[i,k]; t₂ = c * X[i,k]
            @simd for j = k+2:m
                X[i,j] -= u[j]*t₂ + H[k+1,j]*t₁
            end
            X[i,k+1] -= u[k+1]*t₂ + (H[k+1,k+1] + μ) * t₁
        end
        @simd for j = k+2:m
            u[j] = H[k+1,j]*c - u[j]*s'
        end
        u[k+1] = (H[k+1,k+1] + μ) * c - u[k+1]*s'
    end
    for i = 1:n
        τ₁ = X[i,m] / u[m]
        @inbounds for j = m-1:-1:1
            τ₂ = X[i,j]
            c, s = cs[j]
            X[i,j+1] = c*τ₁ + s*τ₂
            τ₁ = c*τ₂ - s'τ₁
        end
        X[i,1] = τ₁
    end
    return X
end

# Hessenberg-matrix determinant formula for H+μI based on:
#
#    N. D. Cahill, J. R. D’Errico, D. A. Narayan, and J. Y. Narayan, "Fibonacci determinants,"
#    College Math. J. 33, pp. 221-225 (2003).
#
# as reviewed in Theorem 2.1 of:
#
#    K. Kaygisiz and A. Sahin, "Determinant and permanent of Hessenberg matrix and generalized Lucas polynomials,"
#    arXiv:1111.4067 (2011).
#
# Cost is O(m²) with O(m) storage.
function det(F::UpperHessenberg; shift::Number=false)
    checksquare(F)
    H = F.data
    m = size(H,1)
    μ = shift
    m == 0 && return one(zero(eltype(H)) + μ)
    determinant = H[1,1] + μ
    prevdeterminant = one(determinant)
    m == 1 && return determinant
    prods = Vector{typeof(determinant)}(undef, m-1) # temporary storage for partial products
    @inbounds for n = 2:m
        prods[n-1] = prevdeterminant
        prevdeterminant = determinant
        determinant *= H[n,n] + μ
        h = H[n,n-1]
        @simd for r = n-1:-2:2
            determinant -= H[r,n] * (prods[r] *= h) - H[r-1,n] * (prods[r-1] *= h)
        end
        if iseven(n)
            determinant -= H[1,n] * (prods[1] *= h)
        end
    end
    return determinant
end

# O(m²) log-determinant based on first doing Givens RQ to put H+μI into upper-triangular form and then
# taking the product of the diagonal entries.   The trick is that we only need O(m) temporary storage,
# because we don't need to store the whole Givens-rotated matrix, only the most recent column.
# We do RQ (column rotations) rather than QR (row rotations) for more consecutive memory access.
# (We could also use it for det instead of the Cahill algorithm above.  Cahill is slightly faster
#  for very small matrices where you are likely to use det, and also uses only ± and * so it can
#  be applied to Hessenberg matrices over other number fields.)
function logabsdet(F::UpperHessenberg; shift::Number=false)
    checksquare(F)
    H = F.data
    m = size(H,1)
    μ = shift
    P = one(zero(eltype(H)) + μ)
    logdeterminant = zero(real(P))
    m == 0 && return (logdeterminant, P)
    g = Vector{typeof(P)}(undef, m) # below, g is the k-th col of Givens-rotated H+μI matrix
    copyto!(g, 1, H, m*(m-1)+1, m) # g .= H[:,m]
    g[m] += μ
    @inbounds for k = m:-1:2
        c, s, ρ = givensAlgorithm(g[k], H[k,k-1])
        logdeterminant += log(abs(ρ))
        P *= sign(ρ)
        g[k-1] = c*(H[k-1,k-1] + μ) - s'*g[k-1]
        @simd for j = 1:k-2
            g[j] = c*H[j,k-1] - s'*g[j]
        end
    end
    logdeterminant += log(abs(g[1]))
    P *= sign(g[1])
    return (logdeterminant, P)
end

function dot(x::AbstractVector, H::UpperHessenberg, y::AbstractVector)
    require_one_based_indexing(x, y)
    m = size(H, 1)
    (length(x) == m == length(y)) || throw(DimensionMismatch())
    if iszero(m)
        return dot(zero(eltype(x)), zero(eltype(H)), zero(eltype(y)))
    end
    x₁ = x[1]
    r = dot(x₁, H[1,1], y[1])
    r += dot(x[2], H[2,1], y[1])
    @inbounds for j in 2:m-1
        yj = y[j]
        if !iszero(yj)
            temp = adjoint(H[1,j]) * x₁
            @simd for i in 2:j+1
                temp += adjoint(H[i,j]) * x[i]
            end
            r += dot(temp, yj)
        end
    end
    ym = y[m]
    if !iszero(ym)
        temp = adjoint(H[1,m]) * x₁
        @simd for i in 2:m
            temp += adjoint(H[i,m]) * x[i]
        end
        r += dot(temp, ym)
    end
    return r
end

######################################################################################
# Hessenberg factorizations Q(H+μI)Q' of A+μI:

"""
    Hessenberg <: Factorization

A `Hessenberg` object represents the Hessenberg factorization `QHQ'` of a square
matrix, or a shift `Q(H+μI)Q'` thereof, which is produced by the [`hessenberg`](@ref) function.
"""
struct Hessenberg{T,SH<:AbstractMatrix,S<:AbstractMatrix,W<:AbstractVector,V<:Number} <: Factorization{T}
    H::SH # UpperHessenberg or SymTridiagonal
    uplo::Char
    factors::S # reflector data in uplo triangle, may share data with H
    τ::W # more Q (reflector) data
    μ::V # diagonal shift for copy-free (F+μI) \ b solves and similar
end
Hessenberg(factors::AbstractMatrix, τ::AbstractVector, H::AbstractMatrix=UpperHessenberg(factors), uplo::AbstractChar='L'; μ::Number=false) =
    Hessenberg{typeof(zero(eltype(factors))+μ),typeof(H),typeof(factors),typeof(τ),typeof(μ)}(H, uplo, factors, τ, μ)
Hessenberg(F::Hessenberg) = F
Hessenberg(F::Hessenberg, μ::Number) = Hessenberg(F.factors, F.τ, F.H, F.uplo; μ=μ)

copy(F::Hessenberg{<:Any,<:UpperHessenberg}) = Hessenberg(copy(F.factors), copy(F.τ); μ=F.μ)
copy(F::Hessenberg{<:Any,<:SymTridiagonal}) = Hessenberg(copy(F.factors), copy(F.τ), copy(F.H), F.uplo; μ=F.μ)
size(F::Hessenberg, d::Integer) = size(F.H, d)
size(F::Hessenberg) = size(F.H)

transpose(F::Hessenberg{<:Real}) = F'
transpose(::Hessenberg) =
    throw(ArgumentError("transpose of Hessenberg decomposition is not supported, consider using adjoint"))

# iteration for destructuring into components
Base.iterate(S::Hessenberg) = (S.Q, Val(:H))
Base.iterate(S::Hessenberg, ::Val{:H}) = (S.H, Val(:μ))
Base.iterate(S::Hessenberg, ::Val{:μ}) = (S.μ, Val(:done))
Base.iterate(S::Hessenberg, ::Val{:done}) = nothing

hessenberg!(A::StridedMatrix{<:BlasFloat}) = Hessenberg(LAPACK.gehrd!(A)...)

function hessenberg!(A::Union{Symmetric{<:BlasReal,<:StridedMatrix},Hermitian{<:BlasFloat,<:StridedMatrix}})
    factors, τ, d, e = LAPACK.hetrd!(A.uplo, A.data)
    return Hessenberg(factors, τ, SymTridiagonal(d, e), A.uplo)
end

"""
    hessenberg!(A) -> Hessenberg

`hessenberg!` is the same as [`hessenberg`](@ref), but saves space by overwriting
the input `A`, instead of creating a copy.
"""
hessenberg!(A::AbstractMatrix)

"""
    hessenberg(A) -> Hessenberg

Compute the Hessenberg decomposition of `A` and return a `Hessenberg` object. If `F` is the
factorization object, the unitary matrix can be accessed with `F.Q` (of type `LinearAlgebra.HessenbergQ`)
and the Hessenberg matrix with `F.H` (of type [`UpperHessenberg`](@ref)), either of
which may be converted to a regular matrix with `Matrix(F.H)` or `Matrix(F.Q)`.

If `A` is [`Hermitian`](@ref) or real-[`Symmetric`](@ref), then the Hessenberg
decomposition produces a real-symmetric tridiagonal matrix and `F.H` is of type
[`SymTridiagonal`](@ref).

Note that the shifted factorization `A+μI = Q (H+μI) Q'` can be
constructed efficiently by `F + μ*I` using the [`UniformScaling`](@ref)
object [`I`](@ref), which creates a new `Hessenberg` object with shared storage
and a modified shift.   The shift of a given `F` is obtained by `F.μ`.
This is useful because multiple shifted solves `(F + μ*I) \\ b`
(for different `μ` and/or `b`) can be performed efficiently once `F` is created.

Iterating the decomposition produces the factors `F.Q, F.H, F.μ`.

# Examples
```julia-repl
julia> A = [4. 9. 7.; 4. 4. 1.; 4. 3. 2.]
3×3 Matrix{Float64}:
 4.0  9.0  7.0
 4.0  4.0  1.0
 4.0  3.0  2.0

julia> F = hessenberg(A)
Hessenberg{Float64, UpperHessenberg{Float64, Matrix{Float64}}, Matrix{Float64}, Vector{Float64}, Bool}
Q factor: 3×3 LinearAlgebra.HessenbergQ{Float64, Matrix{Float64}, Vector{Float64}, false}
H factor:
3×3 UpperHessenberg{Float64, Matrix{Float64}}:
  4.0      -11.3137       -1.41421
 -5.65685    5.0           2.0
   ⋅        -8.88178e-16   1.0

julia> F.Q * F.H * F.Q'
3×3 Matrix{Float64}:
 4.0  9.0  7.0
 4.0  4.0  1.0
 4.0  3.0  2.0

julia> q, h = F; # destructuring via iteration

julia> q == F.Q && h == F.H
true
```
"""
hessenberg(A::AbstractMatrix{T}) where T =
    hessenberg!(eigencopy_oftype(A, eigtype(T)))

function show(io::IO, mime::MIME"text/plain", F::Hessenberg)
    summary(io, F)
    if !iszero(F.μ)
        print("\nwith shift μI for μ = ", F.μ)
    end
    print(io, "\nQ factor: ")
    show(io, mime, F.Q)
    println(io, "\nH factor:")
    show(io, mime, F.H)
end

function getproperty(F::Hessenberg, d::Symbol)
    d === :Q && return HessenbergQ(F)
    return getfield(F, d)
end

Base.propertynames(F::Hessenberg, private::Bool=false) =
    (:Q, :H, :μ, (private ? (:τ, :factors, :uplo) : ())...)

AbstractArray(F::Hessenberg) = AbstractMatrix(F)
Matrix(F::Hessenberg) = Array(AbstractArray(F))
Array(F::Hessenberg) = Matrix(F)
function AbstractMatrix(F::Hessenberg)
    Q = F.Q
    A = rmul!(lmul!(Q, Matrix{eltype(Q)}(F.H)), Q')
    μ = F.μ
    if iszero(μ)
        return A
    elseif typeof(zero(eltype(A))+μ) <: eltype(A) # can shift A in-place
        for i = 1:size(A,1)
            @inbounds A[i,i] += μ
        end
        return A
    else
        return A + μ*I # allocate another matrix, e.g. if A is real and μ is complex
    end
end

# multiply x by the entries of M in the upper-k triangle, which contains
# the entries of the upper-Hessenberg matrix H for k=-1
function rmul_triu!(M::AbstractMatrix, x, k::Integer=0)
    require_one_based_indexing(M)
    m, n = size(M)
    for j = 1:n, i = 1:min(j-k,m)
        @inbounds M[i,j] *= x
    end
    return M
end
function lmul_triu!(x, M::AbstractMatrix, k::Integer=0)
    require_one_based_indexing(M)
    m, n = size(M)
    for j = 1:n, i = 1:min(j-k,m)
        @inbounds M[i,j] = x * M[i,j]
    end
    return M
end

# when H is UpperHessenberg, it shares data with F.factors
# multiply Hessenberg by scalar (but don't modify lower triangle of F.H.data)
rmul!(F::Hessenberg{<:Any,<:UpperHessenberg{T}}, x::T) where {T<:Number} = Hessenberg(rmul_triu!(F.factors, x, -1), F.τ; μ=F.μ*x)
lmul!(x::T, F::Hessenberg{<:Any,<:UpperHessenberg{T}}) where {T<:Number} = Hessenberg(lmul_triu!(x, F.factors, -1), F.τ; μ=x*F.μ)

rmul!(F::Hessenberg{<:Any,<:SymTridiagonal{T}}, x::T) where {T<:Number} = Hessenberg(F.factors, F.τ, SymTridiagonal(F.H.dv*x, F.H.ev*x), F.uplo; μ=F.μ*x)
lmul!(x::T, F::Hessenberg{<:Any,<:SymTridiagonal{T}}) where {T<:Number} = Hessenberg(F.factors, F.τ, SymTridiagonal(x*F.H.dv, x*F.H.ev), F.uplo; μ=x*F.μ)

# Promote F * x or x * F.  In general, we don't know how to do promotions
# that would change the element type of F.H, however.
function (*)(F::Hessenberg{<:Any,<:AbstractMatrix{T}}, x::S) where {T,S<:Number}
    TS = typeof(zero(T) * x)
    if TS === T
        return rmul!(copy(F), convert(T, x))
    else
        throw(MethodError(*, (F, x)))
    end
end
function (*)(x::S, F::Hessenberg{<:Any,<:AbstractMatrix{T}}) where {T,S<:Number}
    TS = typeof(zero(T) * x)
    if TS === T
        return lmul!(convert(T, x), copy(F))
    else
        throw(MethodError(*, (x, F)))
    end
end
-(F::Hessenberg) = F * -one(eltype(F.H))

# shift Hessenberg by λI
+(F::Hessenberg, J::UniformScaling) = Hessenberg(F, F.μ + J.λ)
+(J::UniformScaling, F::Hessenberg) = Hessenberg(F, J.λ + F.μ)
-(F::Hessenberg, J::UniformScaling) = Hessenberg(F, F.μ - J.λ)
-(J::UniformScaling, F::Hessenberg) = Hessenberg(-F, J.λ - F.μ)

function ldiv!(F::Hessenberg, B::AbstractVecOrMat)
    Q = F.Q
    if iszero(F.μ)
        return lmul!(Q, ldiv!(F.H, lmul!(Q', B)))
    else
        return lmul!(Q, ldiv!(F.H, lmul!(Q', B); shift=F.μ))
    end
end

function rdiv!(B::AbstractMatrix, F::Hessenberg)
    Q = F.Q
    return rmul!(rdiv!(rmul!(B, Q), F.H; shift=F.μ), Q')
end

# handle case of real H and complex μ — we need to work around the
# fact that we can't multiple a real F.Q by a complex matrix directly in LAPACK
function ldiv!(F::Hessenberg{<:Complex,<:Any,<:AbstractMatrix{<:Real}}, B::AbstractVecOrMat{<:Complex})
    Q = F.Q
    Br = lmul!(Q', real(B))
    Bi = lmul!(Q', imag(B))
    ldiv!(F.H, B .= Complex.(Br,Bi); shift=F.μ)
    Br .= real.(B); Bi .= imag.(B)
    Br = lmul!(Q, Br)
    Bi = lmul!(Q, Bi)
    return B .= Complex.(Br,Bi)
end
function rdiv!(B::AbstractVecOrMat{<:Complex}, F::Hessenberg{<:Complex,<:Any,<:AbstractMatrix{<:Real}})
    Q = F.Q
    Br = rmul!(real(B), Q)
    Bi = rmul!(imag(B), Q)
    rdiv!(B .= Complex.(Br,Bi), F.H; shift=F.μ)
    Br .= real.(B); Bi .= imag.(B)
    Br = rmul!(Br, Q')
    Bi = rmul!(Bi, Q')
    return B .= Complex.(Br,Bi)
end

ldiv!(F::AdjointFactorization{<:Any,<:Hessenberg}, B::AbstractVecOrMat) = rdiv!(B', F')'

det(F::Hessenberg) = det(F.H; shift=F.μ)
logabsdet(F::Hessenberg) = logabsdet(F.H; shift=F.μ)
function logdet(F::Hessenberg)
    d,s = logabsdet(F)
    return d + log(s)
end
