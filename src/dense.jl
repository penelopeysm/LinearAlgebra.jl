# This file is a part of Julia. License is MIT: https://julialang.org/license

# Linear algebra functions for dense matrices in column major format

## BLAS cutoff threshold constants

#TODO const DOT_CUTOFF = 128
const ASUM_CUTOFF = 32
const NRM2_CUTOFF = 32

# Generic cross-over constant based on benchmarking on a single thread with an i7 CPU @ 2.5GHz
# L1 cache: 32K, L2 cache: 256K, L3 cache: 6144K
# This constant should ideally be determined by the actual CPU cache size
const ISONE_CUTOFF = 2^21 # 2M

function isone(A::AbstractMatrix)
    require_one_based_indexing(A)  # multiplication not defined yet among offset matrices
    m, n = size(A)
    m != n && return false # only square matrices can satisfy x == one(x)
    if sizeof(A) < ISONE_CUTOFF
        _isone_triacheck(A)
    else
        _isone_cachefriendly(A)
    end
end

@inline function _isone_triacheck(A::AbstractMatrix)
    @inbounds for i in axes(A,2), j in axes(A,1)
        if i == j
            isone(A[i,i]) || return false
        else
            iszero(A[i,j]) && iszero(A[j,i]) || return false
        end
    end
    return true
end

# Inner loop over rows to be friendly to the CPU cache
@inline function _isone_cachefriendly(A::AbstractMatrix)
    @inbounds for i in axes(A,2), j in axes(A,1)
        if i == j
            isone(A[i,i]) || return false
        else
            iszero(A[j,i]) || return false
        end
    end
    return true
end


"""
    isposdef!(A) -> Bool

Test whether a matrix is positive definite (and Hermitian) by trying to perform a
Cholesky factorization of `A`, overwriting `A` in the process.
See also [`isposdef`](@ref).

# Examples
```jldoctest
julia> A = [1. 2.; 2. 50.];

julia> isposdef!(A)
true

julia> A
2×2 Matrix{Float64}:
 1.0  2.0
 2.0  6.78233
```
"""
isposdef!(A::AbstractMatrix) =
    ishermitian(A) && isposdef(cholesky!(Hermitian(A); check = false))

"""
    isposdef(A) -> Bool

Test whether a matrix is positive definite (and Hermitian) by trying to perform a
Cholesky factorization of `A`.

See also [`isposdef!`](@ref), [`cholesky`](@ref).

# Examples
```jldoctest
julia> A = [1 2; 2 50]
2×2 Matrix{Int64}:
 1   2
 2  50

julia> isposdef(A)
true
```
"""
isposdef(A::AbstractMatrix) =
    ishermitian(A) && isposdef(cholesky(Hermitian(A); check = false))
isposdef(x::Number) = imag(x)==0 && real(x) > 0

function norm(x::StridedVector{T}, rx::Union{UnitRange{TI},AbstractRange{TI}}) where {T<:BlasFloat,TI<:Integer}
    if minimum(rx) < 1 || maximum(rx) > length(x)
        throw(BoundsError(x, rx))
    end
    GC.@preserve x BLAS.nrm2(length(rx), pointer(x)+(first(rx)-1)*sizeof(T), step(rx))
end

norm1(x::Union{Array{T},StridedVector{T}}) where {T<:BlasReal} =
    length(x) < ASUM_CUTOFF ? generic_norm1(x) : BLAS.asum(x)

norm2(x::Union{Array{T},StridedVector{T}}) where {T<:BlasFloat} =
    length(x) < NRM2_CUTOFF ? generic_norm2(x) : BLAS.nrm2(x)

# Conservative assessment of types that have zero(T) defined for themselves
"""
    haszero(T::Type)

Return whether a type `T` has a unique zero element defined using `zero(T)`.
If a type `M` specializes `zero(M)`, it may also choose to set `haszero(M)` to `true`.
By default, `haszero` is assumed to be `false`, in which case the zero elements
are deduced from values rather than the type.

!!! note
    `haszero` is a conservative check that is used to dispatch to
    optimized paths. Extending it is optional, but encouraged.
"""
haszero(::Type) = false
haszero(::Type{T}) where {T<:Number} = isconcretetype(T)
haszero(::Type{Union{Missing,T}}) where {T<:Number} = haszero(T)
@propagate_inbounds _zero(M::AbstractArray{T}, inds...) where {T} = haszero(T) ? zero(T) : zero(M[inds...])

"""
    triu!(M, k::Integer)

Return the upper triangle of `M` starting from the `k`th superdiagonal,
overwriting `M` in the process.

# Examples
```jldoctest
julia> M = [1 2 3 4 5; 1 2 3 4 5; 1 2 3 4 5; 1 2 3 4 5; 1 2 3 4 5]
5×5 Matrix{Int64}:
 1  2  3  4  5
 1  2  3  4  5
 1  2  3  4  5
 1  2  3  4  5
 1  2  3  4  5

julia> triu!(M, 1)
5×5 Matrix{Int64}:
 0  2  3  4  5
 0  0  3  4  5
 0  0  0  4  5
 0  0  0  0  5
 0  0  0  0  0
```
"""
function triu!(M::AbstractMatrix, k::Integer)
    require_one_based_indexing(M)
    m, n = size(M)
    for j in 1:min(n, m + k)
        for i in max(1, j - k + 1):m
            @inbounds M[i,j] = _zero(M, i,j)
        end
    end
    M
end

triu(M::Matrix, k::Integer) = triu!(copy(M), k)

"""
    tril!(M, k::Integer)

Return the lower triangle of `M` starting from the `k`th superdiagonal, overwriting `M` in
the process.

# Examples
```jldoctest
julia> M = [1 2 3 4 5; 1 2 3 4 5; 1 2 3 4 5; 1 2 3 4 5; 1 2 3 4 5]
5×5 Matrix{Int64}:
 1  2  3  4  5
 1  2  3  4  5
 1  2  3  4  5
 1  2  3  4  5
 1  2  3  4  5

julia> tril!(M, 2)
5×5 Matrix{Int64}:
 1  2  3  0  0
 1  2  3  4  0
 1  2  3  4  5
 1  2  3  4  5
 1  2  3  4  5
```
"""
function tril!(M::AbstractMatrix, k::Integer)
    require_one_based_indexing(M)
    m, n = size(M)
    for j in max(1, k + 1):n
        for i in 1:min(j - k - 1, m)
            @inbounds M[i,j] = _zero(M, i,j)
        end
    end
    M
end

tril(M::Matrix, k::Integer) = tril!(copy(M), k)

"""
    fillband!(A::AbstractMatrix, x, l, u)

Fill the band between diagonals `l` and `u` with the value `x`.

# Examples
```jldoctest
julia> A = zeros(4,4)
4×4 Matrix{Float64}:
 0.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0

julia> LinearAlgebra.fillband!(A, 2, 0, 1)
4×4 Matrix{Float64}:
 2.0  2.0  0.0  0.0
 0.0  2.0  2.0  0.0
 0.0  0.0  2.0  2.0
 0.0  0.0  0.0  2.0
```
"""
function fillband!(A::AbstractMatrix{T}, x, l, u) where T
    require_one_based_indexing(A)
    m, n = size(A)
    xT = convert(T, x)
    for j in axes(A,2)
        for i in max(1,j-u):min(m,j-l)
            @inbounds A[i, j] = xT
        end
    end
    return A
end

diagind(m::Integer, n::Integer, k::Integer=0) = diagind(IndexLinear(), m, n, k)
diagind(::IndexLinear, m::Integer, n::Integer, k::Integer=0) =
    k <= 0 ? range(1-k, step=m+1, length=min(m+k, n)) : range(k*m+1, step=m+1, length=min(m, n-k))

function diagind(::IndexCartesian, m::Integer, n::Integer, k::Integer=0)
    Cstart = CartesianIndex(1 + max(0,-k), 1 + max(0,k))
    Cstep = CartesianIndex(1, 1)
    length = max(0, k <= 0 ? min(m+k, n) : min(m, n-k))
    StepRangeLen(Cstart, Cstep, length)
end

"""
    diagind(M::AbstractMatrix, k::Integer = 0, indstyle::IndexStyle = IndexLinear())
    diagind(M::AbstractMatrix, indstyle::IndexStyle = IndexLinear())

An `AbstractRange` giving the indices of the `k`th diagonal of the matrix `M`.
Optionally, an index style may be specified which determines the type of the range returned.
If `indstyle isa IndexLinear` (default), this returns an `AbstractRange{Integer}`.
On the other hand, if `indstyle isa IndexCartesian`, this returns an `AbstractRange{CartesianIndex{2}}`.

If `k` is not provided, it is assumed to be `0` (corresponding to the main diagonal).

See also: [`diag`](@ref), [`diagm`](@ref), [`Diagonal`](@ref).

# Examples
```jldoctest
julia> A = [1 2 3; 4 5 6; 7 8 9]
3×3 Matrix{Int64}:
 1  2  3
 4  5  6
 7  8  9

julia> diagind(A, -1)
2:4:6

julia> diagind(A, IndexCartesian())
StepRangeLen(CartesianIndex(1, 1), CartesianIndex(1, 1), 3)
```

!!! compat "Julia 1.11"
     Specifying an `IndexStyle` requires at least Julia 1.11.
"""
function diagind(A::AbstractMatrix, k::Integer=0, indexstyle::IndexStyle = IndexLinear())
    require_one_based_indexing(A)
    diagind(indexstyle, size(A,1), size(A,2), k)
end

diagind(A::AbstractMatrix, indexstyle::IndexStyle) = diagind(A, 0, indexstyle)

"""
    diag(M, k::Integer=0)

The `k`th diagonal of a matrix, as a vector.

See also [`diagm`](@ref), [`diagind`](@ref), [`Diagonal`](@ref), [`isdiag`](@ref).

# Examples
```jldoctest
julia> A = [1 2 3; 4 5 6; 7 8 9]
3×3 Matrix{Int64}:
 1  2  3
 4  5  6
 7  8  9

julia> diag(A,1)
2-element Vector{Int64}:
 2
 6
```
"""
diag(A::AbstractMatrix, k::Integer=0) = A[diagind(A, k, IndexStyle(A))]

"""
    diagview(M, k::Integer=0)

Return a view into the `k`th diagonal of the matrix `M`.

See also [`diag`](@ref), [`diagind`](@ref).

!!! compat "Julia 1.12"
    This function requires Julia 1.12 or later.

# Examples
```jldoctest
julia> A = [1 2 3; 4 5 6; 7 8 9]
3×3 Matrix{Int64}:
 1  2  3
 4  5  6
 7  8  9

julia> diagview(A)
3-element view(::Vector{Int64}, 1:4:9) with eltype Int64:
 1
 5
 9

julia> diagview(A, 1)
2-element view(::Vector{Int64}, 4:4:8) with eltype Int64:
 2
 6
```
"""
diagview(A::AbstractMatrix, k::Integer=0) = @view A[diagind(A, k, IndexStyle(A))]

"""
    diagm(kv::Pair{<:Integer,<:AbstractVector}...)
    diagm(m::Integer, n::Integer, kv::Pair{<:Integer,<:AbstractVector}...)

Construct a matrix from `Pair`s of diagonals and vectors.
Vector `kv.second` will be placed on the `kv.first` diagonal.
By default the matrix is square and its size is inferred
from `kv`, but a non-square size `m`×`n` (padded with zeros as needed)
can be specified by passing `m,n` as the first arguments.
For repeated diagonal indices `kv.first` the values in the corresponding
vectors `kv.second` will be added.

`diagm` constructs a full matrix; if you want storage-efficient
versions with fast arithmetic, see [`Diagonal`](@ref), [`Bidiagonal`](@ref)
[`Tridiagonal`](@ref) and [`SymTridiagonal`](@ref).

# Examples
```jldoctest
julia> diagm(1 => [1,2,3])
4×4 Matrix{Int64}:
 0  1  0  0
 0  0  2  0
 0  0  0  3
 0  0  0  0

julia> diagm(1 => [1,2,3], -1 => [4,5])
4×4 Matrix{Int64}:
 0  1  0  0
 4  0  2  0
 0  5  0  3
 0  0  0  0

julia> diagm(1 => [1,2,3], 1 => [1,2,3])
4×4 Matrix{Int64}:
 0  2  0  0
 0  0  4  0
 0  0  0  6
 0  0  0  0
```
"""
diagm(kv::Pair{<:Integer,<:AbstractVector}...) = _diagm(nothing, kv...)
diagm(m::Integer, n::Integer, kv::Pair{<:Integer,<:AbstractVector}...) = _diagm((Int(m),Int(n)), kv...)
function _diagm(size, kv::Pair{<:Integer,<:AbstractVector}...)
    A = diagm_container(size, kv...)
    for p in kv
        inds = diagind(A, p.first)
        for (i, val) in enumerate(p.second)
            A[inds[i]] += val
        end
    end
    return A
end
function diagm_size(size::Nothing, kv::Pair{<:Integer,<:AbstractVector}...)
    mnmax = mapreduce(x -> length(x.second) + abs(Int(x.first)), max, kv; init=0)
    return mnmax, mnmax
end
function diagm_size(size::Tuple{Int,Int}, kv::Pair{<:Integer,<:AbstractVector}...)
    mmax = mapreduce(x -> length(x.second) - min(0,Int(x.first)), max, kv; init=0)
    nmax = mapreduce(x -> length(x.second) + max(0,Int(x.first)), max, kv; init=0)
    m, n = size
    (m ≥ mmax && n ≥ nmax) || throw(DimensionMismatch(lazy"invalid size=$size"))
    return m, n
end
function diagm_container(size, kv::Pair{<:Integer,<:AbstractVector}...)
    T = promote_type(map(x -> eltype(x.second), kv)...)
    # For some type `T`, `zero(T)` is not a `T` and `zeros(T, ...)` fails.
    U = promote_type(T, typeof(zero(T)))
    return zeros(U, diagm_size(size, kv...)...)
end
diagm_container(size, kv::Pair{<:Integer,<:BitVector}...) =
    falses(diagm_size(size, kv...)...)

"""
    diagm(v::AbstractVector)
    diagm(m::Integer, n::Integer, v::AbstractVector)

Construct a matrix with elements of the vector as diagonal elements.
By default, the matrix is square and its size is given by
`length(v)`, but a non-square size `m`×`n` can be specified
by passing `m,n` as the first arguments.
The diagonal will be zero-padded if necessary.

# Examples
```jldoctest
julia> diagm([1,2,3])
3×3 Matrix{Int64}:
 1  0  0
 0  2  0
 0  0  3

julia> diagm(4, 5, [1,2,3])
4×5 Matrix{Int64}:
 1  0  0  0  0
 0  2  0  0  0
 0  0  3  0  0
 0  0  0  0  0
```
"""
diagm(v::AbstractVector) = diagm(0 => v)
diagm(m::Integer, n::Integer, v::AbstractVector) = diagm(m, n, 0 => v)

function tr(A::StridedMatrix{T}) where T
    checksquare(A)
    isempty(A) && return zero(T)
    reduce(+, (A[i] for i in diagind(A, IndexStyle(A))))
end

_kronsize(A::AbstractMatrix, B::AbstractMatrix) = map(*, size(A), size(B))
_kronsize(A::AbstractMatrix, B::AbstractVector) = (size(A, 1)*length(B), size(A, 2))
_kronsize(A::AbstractVector, B::AbstractMatrix) = (length(A)*size(B, 1), size(B, 2))

"""
    kron!(C, A, B)

Computes the Kronecker product of `A` and `B` and stores the result in `C`,
overwriting the existing content of `C`. This is the in-place version of [`kron`](@ref).

!!! compat "Julia 1.6"
    This function requires Julia 1.6 or later.
"""
function kron!(C::AbstractVecOrMat, A::AbstractVecOrMat, B::AbstractVecOrMat)
    size(C) == _kronsize(A, B) || throw(DimensionMismatch("kron!"))
    _kron!(C, A, B)
end
function kron!(c::AbstractVector, a::AbstractVector, b::AbstractVector)
    length(c) == length(a) * length(b) || throw(DimensionMismatch("kron!"))
    m = firstindex(c)
    @inbounds for i in eachindex(a)
        ai = a[i]
        for k in eachindex(b)
            c[m] = ai*b[k]
            m += 1
        end
    end
    return c
end
kron!(c::AbstractVecOrMat, a::AbstractVecOrMat, b::Number) = mul!(c, a, b)
kron!(c::AbstractVecOrMat, a::Number, b::AbstractVecOrMat) = mul!(c, a, b)

function _kron!(C, A::AbstractMatrix, B::AbstractMatrix)
    m = firstindex(C)
    @inbounds for j in axes(A,2), l in axes(B,2), i in axes(A,1)
        Aij = A[i,j]
        for k in axes(B,1)
            C[m] = Aij*B[k,l]
            m += 1
        end
    end
    return C
end
function _kron!(C, A::AbstractMatrix, b::AbstractVector)
    m = firstindex(C)
    @inbounds for j in axes(A,2), i in axes(A,1)
        Aij = A[i,j]
        for k in eachindex(b)
            C[m] = Aij*b[k]
            m += 1
        end
    end
    return C
end
function _kron!(C, a::AbstractVector, B::AbstractMatrix)
    m = firstindex(C)
    @inbounds for l in axes(B,2), i in eachindex(a)
        ai = a[i]
        for k in axes(B,1)
            C[m] = ai*B[k,l]
            m += 1
        end
    end
    return C
end

"""
    kron(A, B)

Computes the Kronecker product of two vectors, matrices or numbers.

For real vectors `v` and `w`, the Kronecker product is related to the outer product by
`kron(v,w) == vec(w * transpose(v))` or
`w * transpose(v) == reshape(kron(v,w), (length(w), length(v)))`.
Note how the ordering of `v` and `w` differs on the left and right
of these expressions (due to column-major storage).
For complex vectors, the outer product `w * v'` also differs by conjugation of `v`.

# Examples
```jldoctest
julia> A = [1 2; 3 4]
2×2 Matrix{Int64}:
 1  2
 3  4

julia> B = [im 1; 1 -im]
2×2 Matrix{Complex{Int64}}:
 0+1im  1+0im
 1+0im  0-1im

julia> kron(A, B)
4×4 Matrix{Complex{Int64}}:
 0+1im  1+0im  0+2im  2+0im
 1+0im  0-1im  2+0im  0-2im
 0+3im  3+0im  0+4im  4+0im
 3+0im  0-3im  4+0im  0-4im

julia> v = [1, 2]; w = [3, 4, 5];

julia> w*transpose(v)
3×2 Matrix{Int64}:
 3   6
 4   8
 5  10

julia> reshape(kron(v,w), (length(w), length(v)))
3×2 Matrix{Int64}:
 3   6
 4   8
 5  10
```
"""
function kron(A::AbstractVecOrMat{T}, B::AbstractVecOrMat{S}) where {T,S}
    C = Matrix{promote_op(*,T,S)}(undef, _kronsize(A, B))
    return kron!(C, A, B)
end
function kron(a::AbstractVector{T}, b::AbstractVector{S}) where {T,S}
    c = Vector{promote_op(*,T,S)}(undef, length(a)*length(b))
    return kron!(c, a, b)
end
kron(a::Number, b::Union{Number, AbstractVecOrMat}) = a * b
kron(a::AbstractVecOrMat, b::Number) = a * b
kron(a::AdjointAbsVec, b::AdjointAbsVec) = adjoint(kron(adjoint(a), adjoint(b)))
kron(a::AdjOrTransAbsVec, b::AdjOrTransAbsVec) = transpose(kron(transpose(a), transpose(b)))

# Matrix power
(^)(A::AbstractMatrix, p::Integer) = p < 0 ? power_by_squaring(inv(A), -p) : power_by_squaring(A, p)
function (^)(A::AbstractMatrix{T}, p::Integer) where T<:Integer
    # make sure that e.g. [1 1;1 0]^big(3)
    # gets promotes in a similar way as 2^big(3)
    TT = promote_op(^, T, typeof(p))
    return power_by_squaring(convert(AbstractMatrix{TT}, A), p)
end
function integerpow(A::AbstractMatrix{T}, p) where T
    TT = promote_op(^, T, typeof(p))
    return (TT == T ? A : convert(AbstractMatrix{TT}, A))^Integer(p)
end
function schurpow(A::AbstractMatrix, p)
    if istriu(A)
        # Integer part
        retmat = A ^ floor(Integer, p)
        # Real part
        if p - floor(p) == 0.5
            # special case: A^0.5 === sqrt(A)
            retmat = retmat * sqrt(A)
        else
            retmat = retmat * powm!(UpperTriangular(float.(A)), real(p - floor(p)))
        end
    else
        S,Q,d = Schur{Complex}(schur(A))
        # Integer part
        R = S ^ floor(Integer, p)
        # Real part
        if p - floor(p) == 0.5
            # special case: A^0.5 === sqrt(A)
            R = R * sqrt(S)
        else
            R = R * powm!(UpperTriangular(float.(S)), real(p - floor(p)))
        end
        retmat = Q * R * Q'
    end

    # if A has nonpositive real eigenvalues, retmat is a nonprincipal matrix power.
    if eltype(A) <: Real && isreal(retmat)
        return real(retmat)
    else
        return retmat
    end
end
function (^)(A::AbstractMatrix{T}, p::Real) where T
    checksquare(A)
    # Quicker return if A is diagonal
    if isdiag(A)
        if T <: Real && any(<(0), diagview(A))
            return applydiagonal(x -> complex(x)^p, A)
        else
            return applydiagonal(x -> x^p, A)
        end
    end

    # For integer powers, use power_by_squaring
    isinteger(p) && return integerpow(A, p)

    # If possible, use diagonalization
    if ishermitian(A)
        return _safe_parent(Hermitian(A)^p)
    end

    # Otherwise, use Schur decomposition
    return schurpow(A, p)
end

function _safe_parent(fA)
    parentfA = parent(fA)
    if isa(fA, Hermitian) || isa(fA, Symmetric{<:Real})
        return copytri_maybe_inplace(parentfA, 'U', true)
    elseif isa(fA, Symmetric)
        return copytri_maybe_inplace(parentfA, 'U')
    else
        return fA
    end
end
"""
    ^(A::AbstractMatrix, p::Number)

Matrix power, equivalent to ``\\exp(p\\log(A))``

# Examples
```jldoctest
julia> [1 2; 0 3]^3
2×2 Matrix{Int64}:
 1  26
 0  27
```
"""
(^)(A::AbstractMatrix, p::Number) = exp(p*log(A))

# Matrix exponential

"""
    exp(A::AbstractMatrix)

Compute the matrix exponential of `A`, defined by

```math
e^A = \\sum_{n=0}^{\\infty} \\frac{A^n}{n!}.
```

For symmetric or Hermitian `A`, an eigendecomposition ([`eigen`](@ref)) is
used, otherwise the scaling and squaring algorithm (see [^H05]) is chosen.

[^H05]: Nicholas J. Higham, "The squaring and scaling method for the matrix exponential revisited", SIAM Journal on Matrix Analysis and Applications, 26(4), 2005, 1179-1193. [doi:10.1137/090768539](https://doi.org/10.1137/090768539)

# Examples
```jldoctest
julia> A = Matrix(1.0I, 2, 2)
2×2 Matrix{Float64}:
 1.0  0.0
 0.0  1.0

julia> exp(A)
2×2 Matrix{Float64}:
 2.71828  0.0
 0.0      2.71828
```
"""
exp(A::AbstractMatrix) = exp!(copy_similar(A, eigtype(eltype(A))))
exp(A::AdjointAbsMat) = adjoint(exp(parent(A)))
exp(A::TransposeAbsMat) = transpose(exp(parent(A)))

"""
    cis(A::AbstractMatrix)

More efficient method for `exp(im*A)` of square matrix `A`
(especially if `A` is `Hermitian` or real-`Symmetric`).

See also [`cispi`](@ref), [`sincos`](@ref), [`exp`](@ref).

!!! compat "Julia 1.7"
    Support for using `cis` with matrices was added in Julia 1.7.

# Examples
```jldoctest
julia> cis([π 0; 0 π]) ≈ -I
true
```
"""
cis(A::AbstractMatrix) = exp(im * A)  # fallback
cis(A::AbstractMatrix{<:Base.HWNumber}) = exp_maybe_inplace(float.(im .* A))

exp_maybe_inplace(A::StridedMatrix{<:Union{ComplexF32, ComplexF64}}) = exp!(A)
exp_maybe_inplace(A) = exp(A)

function copytri_maybe_inplace(A::StridedMatrix, uplo, conjugate::Bool=false, diag::Bool=false)
    copytri!(A, uplo, conjugate, diag)
end
function copytri_maybe_inplace(A, uplo, conjugate::Bool=false, diag::Bool=false)
    k = Int(diag)
    if uplo == 'U'
        B = triu(A, 1-k)
        triu(A, k) + (conjugate ? copy(adjoint(B)) : copy(transpose(B)))
    elseif uplo == 'L'
        B = tril(A, k-1)
        tril(A, -k) + (conjugate ? copy(adjoint(B)) : copy(transpose(B)))
    else
        throw(ArgumentError(lazy"uplo argument must be 'U' (upper) or 'L' (lower), got $uplo"))
    end
end

"""
    ^(b::Number, A::AbstractMatrix)

Matrix exponential, equivalent to ``\\exp(\\log(b)A)``.

!!! compat "Julia 1.1"
    Support for raising `Irrational` numbers (like `ℯ`)
    to a matrix was added in Julia 1.1.

# Examples
```jldoctest
julia> 2^[1 2; 0 3]
2×2 Matrix{Float64}:
 2.0  6.0
 0.0  8.0

julia> ℯ^[1 2; 0 3]
2×2 Matrix{Float64}:
 2.71828  17.3673
 0.0      20.0855
```
"""
Base.:^(b::Number, A::AbstractMatrix) = exp_maybe_inplace(log(b)*A)
# method for ℯ to explicitly elide the log(b) multiplication
Base.:^(::Irrational{:ℯ}, A::AbstractMatrix) = exp(A)

## Destructive matrix exponential using algorithm from Higham, 2008,
## "Functions of Matrices: Theory and Computation", SIAM
function exp!(A::StridedMatrix{T}) where T<:BlasFloat
    n = checksquare(A)
    if isdiag(A)
        for i in diagind(A, IndexStyle(A))
            A[i] = exp(A[i])
        end
        return A
    elseif ishermitian(A)
        return copytri!(parent(exp(Hermitian(A))), 'U', true)
    end
    ilo, ihi, scale = LAPACK.gebal!('B', A)    # modifies A
    nA   = opnorm(A, 1)
    ## For sufficiently small nA, use lower order Padé-Approximations
    if (nA <= 2.1)
        if nA > 0.95
            C = T[17643225600.,8821612800.,2075673600.,302702400.,
                     30270240.,   2162160.,    110880.,     3960.,
                           90.,         1.]
        elseif nA > 0.25
            C = T[17297280.,8648640.,1995840.,277200.,
                     25200.,   1512.,     56.,     1.]
        elseif nA > 0.015
            C = T[30240.,15120.,3360.,
                    420.,   30.,   1.]
        else
            C = T[120.,60.,12.,1.]
        end
        A2 = A * A
        # Compute U and V: Even/odd terms in Padé numerator & denom
        # Expansion of k=1 in for loop
        P = A2
        U = similar(P)
        V = similar(P)
        for ind in CartesianIndices(P)
            U[ind] = C[4]*P[ind] + C[2]*I[ind]
            V[ind] = C[3]*P[ind] + C[1]*I[ind]
        end
        for k in 2:(div(length(C), 2) - 1)
            P *= A2
            for ind in eachindex(P, U, V)
                U[ind] += C[2k + 2] * P[ind]
                V[ind] += C[2k + 1] * P[ind]
            end
        end

        # U = A * U, but we overwrite P to avoid an allocation
        mul!(P, A, U)
        # P may be seen as an alias for U in the following code

        # Padé approximant:  (V-U)\(V+U)
        VminU, VplusU = V, U # Reuse already allocated arrays
        for ind in eachindex(V, U)
            vi, ui = V[ind], P[ind]
            VminU[ind] = vi - ui
            VplusU[ind] = vi + ui
        end
        X = LAPACK.gesv!(VminU, VplusU)[1]
    else
        s  = log2(nA/5.4)               # power of 2 later reversed by squaring
        if s > 0
            si = ceil(Int,s)
            twopowsi = convert(T,2^si)
            for ind in eachindex(A)
                A[ind] /= twopowsi
            end
        end
        CC = T[64764752532480000.,32382376266240000.,7771770303897600.,
                1187353796428800.,  129060195264000.,  10559470521600.,
                    670442572800.,      33522128640.,      1323241920.,
                        40840800.,           960960.,           16380.,
                             182.,                1.]
        A2 = A * A
        A4 = A2 * A2
        A6 = A2 * A4
        tmp1, tmp2 = similar(A6), similar(A6)

        # Allocation economical version of:
        # U  = A * (A6 * (CC[14].*A6 .+ CC[12].*A4 .+ CC[10].*A2) .+
        #           CC[8].*A6 .+ CC[6].*A4 .+ CC[4]*A2+CC[2]*I)
        for ind in eachindex(tmp1)
            tmp1[ind] = CC[14]*A6[ind] + CC[12]*A4[ind] + CC[10]*A2[ind]
            tmp2[ind] = CC[8]*A6[ind] + CC[6]*A4[ind] + CC[4]*A2[ind]
        end
        mul!(tmp2, true,CC[2]*I, true, true) # tmp2 .+= CC[2]*I
        U = mul!(tmp2, A6, tmp1, true, true)
        U, tmp1 = mul!(tmp1, A, U), A # U = A * U0

        # Allocation economical version of:
        # V  = A6 * (CC[13].*A6 .+ CC[11].*A4 .+ CC[9].*A2) .+
        #           CC[7].*A6 .+ CC[5].*A4 .+ CC[3]*A2 .+ CC[1]*I
        for ind in eachindex(tmp1)
            tmp1[ind] = CC[13]*A6[ind] + CC[11]*A4[ind] + CC[9]*A2[ind]
            tmp2[ind] = CC[7]*A6[ind] + CC[5]*A4[ind] + CC[3]*A2[ind]
        end
        mul!(tmp2, true, CC[1]*I, true, true) # tmp2 .+= CC[1]*I
        V = mul!(tmp2, A6, tmp1, true, true)

        for ind in eachindex(tmp1)
            tmp1[ind] = V[ind] + U[ind]
            tmp2[ind] = V[ind] - U[ind] # tmp2 already contained V but this seems more readable
        end
        X = LAPACK.gesv!(tmp2, tmp1)[1] # X now contains r_13 in Higham 2008

        if s > 0
            # Repeated squaring to compute X = r_13^(2^si)
            for t=1:si
                mul!(tmp2, X, X)
                X, tmp2 = tmp2, X
            end
        end
    end

    # Undo the balancing
    for j = ilo:ihi
        scj = scale[j]
        for i = 1:n
            X[j,i] *= scj
        end
        for i = 1:n
            X[i,j] /= scj
        end
    end

    if ilo > 1       # apply lower permutations in reverse order
        for j in (ilo-1):-1:1
            rcswap!(j, Int(scale[j]), X)
        end
    end
    if ihi < n       # apply upper permutations in forward order
        for j in (ihi+1):n
            rcswap!(j, Int(scale[j]), X)
        end
    end
    X
end

## Swap rows i and j and columns i and j in X
function rcswap!(i::Integer, j::Integer, X::AbstractMatrix{<:Number})
    for k = axes(X,1)
        X[k,i], X[k,j] = X[k,j], X[k,i]
    end
    for k = axes(X,2)
        X[i,k], X[j,k] = X[j,k], X[i,k]
    end
end

"""
    log(A::AbstractMatrix)

If `A` has no negative real eigenvalue, compute the principal matrix logarithm of `A`, i.e.
the unique matrix ``X`` such that ``e^X = A`` and ``-\\pi < Im(\\lambda) < \\pi`` for all
the eigenvalues ``\\lambda`` of ``X``. If `A` has nonpositive eigenvalues, a nonprincipal
matrix function is returned whenever possible.

If `A` is symmetric or Hermitian, its eigendecomposition ([`eigen`](@ref)) is
used, if `A` is triangular an improved version of the inverse scaling and squaring method is
employed (see [^AH12] and [^AHR13]). If `A` is real with no negative eigenvalues, then
the real Schur form is computed. Otherwise, the complex Schur form is computed. Then
the upper (quasi-)triangular algorithm in [^AHR13] is used on the upper (quasi-)triangular
factor.

[^AH12]: Awad H. Al-Mohy and Nicholas J. Higham, "Improved inverse  scaling and squaring algorithms for the matrix logarithm", SIAM Journal on Scientific Computing, 34(4), 2012, C153-C169. [doi:10.1137/110852553](https://doi.org/10.1137/110852553)

[^AHR13]: Awad H. Al-Mohy, Nicholas J. Higham and Samuel D. Relton, "Computing the Fréchet derivative of the matrix logarithm and estimating the condition number", SIAM Journal on Scientific Computing, 35(4), 2013, C394-C410. [doi:10.1137/120885991](https://doi.org/10.1137/120885991)

# Examples
```jldoctest
julia> A = Matrix(2.7182818*I, 2, 2)
2×2 Matrix{Float64}:
 2.71828  0.0
 0.0      2.71828

julia> log(A)
2×2 Matrix{Float64}:
 1.0  0.0
 0.0  1.0
```
"""
function log(A::AbstractMatrix)
    # If possible, use diagonalization
    if isdiag(A) && eltype(A) <: Union{Real,Complex}
        if eltype(A) <: Real && any(<(0), diagview(A))
            return applydiagonal(log ∘ complex, A)
        else
            return applydiagonal(log, A)
        end
    elseif ishermitian(A)
        return _safe_parent(log(Hermitian(A)))
    elseif istriu(A)
        return triu!(parent(log(UpperTriangular(A))))
    elseif isreal(A)
        SchurF = schur(real(A))
        if istriu(SchurF.T)
            logA = SchurF.Z * log(UpperTriangular(SchurF.T)) * SchurF.Z'
        else
            # real log exists whenever all eigenvalues are positive
            is_log_real = !any(x -> isreal(x) && real(x) ≤ 0, SchurF.values)
            if is_log_real
                logA = SchurF.Z * log_quasitriu(SchurF.T) * SchurF.Z'
            else
                SchurS = Schur{Complex}(SchurF)
                logA = SchurS.Z * log(UpperTriangular(SchurS.T)) * SchurS.Z'
            end
        end
        return eltype(A) <: Complex ? complex(logA) : logA
    else
        SchurF = schur(A)
        return SchurF.vectors * log(UpperTriangular(SchurF.T)) * SchurF.vectors'
    end
end

log(A::AdjointAbsMat) = adjoint(log(parent(A)))
log(A::TransposeAbsMat) = transpose(log(parent(A)))

"""
    sqrt(A::AbstractMatrix)

If `A` has no negative real eigenvalues, compute the principal matrix square root of `A`,
that is the unique matrix ``X`` with eigenvalues having positive real part such that
``X^2 = A``. Otherwise, a nonprincipal square root is returned.

If `A` is real-symmetric or Hermitian, its eigendecomposition ([`eigen`](@ref)) is
used to compute the square root.   For such matrices, eigenvalues λ that
appear to be slightly negative due to roundoff errors are treated as if they were zero.
More precisely, matrices with all eigenvalues `≥ -rtol*(max |λ|)` are treated as semidefinite
(yielding a Hermitian square root), with negative eigenvalues taken to be zero.
`rtol` is a keyword argument to `sqrt` (in the Hermitian/real-symmetric case only) that
defaults to machine precision scaled by `size(A,1)`.

Otherwise, the square root is determined by means of the
Björck-Hammarling method [^BH83], which computes the complex Schur form ([`schur`](@ref))
and then the complex square root of the triangular factor.
If a real square root exists, then an extension of this method [^H87] that computes the real
Schur form and then the real square root of the quasi-triangular factor is instead used.

[^BH83]:

    Åke Björck and Sven Hammarling, "A Schur method for the square root of a matrix",
    Linear Algebra and its Applications, 52-53, 1983, 127-140.
    [doi:10.1016/0024-3795(83)80010-X](https://doi.org/10.1016/0024-3795(83)80010-X)

[^H87]:

    Nicholas J. Higham, "Computing real square roots of a real matrix",
    Linear Algebra and its Applications, 88-89, 1987, 405-430.
    [doi:10.1016/0024-3795(87)90118-2](https://doi.org/10.1016/0024-3795(87)90118-2)

# Examples
```jldoctest
julia> A = [4 0; 0 4]
2×2 Matrix{Int64}:
 4  0
 0  4

julia> sqrt(A)
2×2 Matrix{Float64}:
 2.0  0.0
 0.0  2.0
```
"""
sqrt(::AbstractMatrix)

function sqrt(A::AbstractMatrix{T}) where {T<:Union{Real,Complex}}
    if checksquare(A) == 0
        return copy(float(A))
    elseif isdiag(A)
        if T <: Real && any(<(0), diagview(A))
            return applydiagonal(sqrt ∘ complex, A)
        else
            return applydiagonal(sqrt, A)
        end
    elseif ishermitian(A)
        return _safe_parent(sqrt(Hermitian(A)))
    elseif istriu(A)
        return triu!(parent(sqrt(UpperTriangular(A))))
    elseif isreal(A)
        SchurF = schur(real(A))
        if istriu(SchurF.T)
            sqrtA = SchurF.Z * sqrt(UpperTriangular(SchurF.T)) * SchurF.Z'
        else
            # real sqrt exists whenever no eigenvalues are negative
            is_sqrt_real = !any(x -> isreal(x) && real(x) < 0, SchurF.values)
            # sqrt_quasitriu uses LAPACK functions for non-triu inputs
            if typeof(sqrt(zero(T))) <: BlasFloat && is_sqrt_real
                sqrtA = SchurF.Z * sqrt_quasitriu(SchurF.T) * SchurF.Z'
            else
                SchurS = Schur{Complex}(SchurF)
                sqrtA = SchurS.Z * sqrt(UpperTriangular(SchurS.T)) * SchurS.Z'
            end
        end
        return eltype(A) <: Complex ? complex(sqrtA) : sqrtA
    else
        SchurF = schur(A)
        return SchurF.vectors * sqrt(UpperTriangular(SchurF.T)) * SchurF.vectors'
    end
end

sqrt(A::AdjointAbsMat) = adjoint(sqrt(parent(A)))
sqrt(A::TransposeAbsMat) = transpose(sqrt(parent(A)))

"""
    cbrt(A::AbstractMatrix{<:Real})

Computes the real-valued cube root of a real-valued matrix `A`. If `T = cbrt(A)`, then
we have `T*T*T ≈ A`, see example given below.

If `A` is real-symmetric or Hermitian, its eigendecomposition ([`eigen`](@ref)) is used to
find the cube root. Otherwise, a specialized version of the p-th root algorithm [^S03] is
utilized, which exploits the real-valued Schur decomposition ([`schur`](@ref))
to compute the cube root.

[^S03]:

    Matthew I. Smith, "A Schur Algorithm for Computing Matrix pth Roots",
    SIAM Journal on Matrix Analysis and Applications, vol. 24, 2003, pp. 971–989.
    [doi:10.1137/S0895479801392697](https://doi.org/10.1137/s0895479801392697)

# Examples
```jldoctest
julia> A = [0.927524 -0.15857; -1.3677 -1.01172]
2×2 Matrix{Float64}:
  0.927524  -0.15857
 -1.3677    -1.01172

julia> T = cbrt(A)
2×2 Matrix{Float64}:
  0.910077  -0.151019
 -1.30257   -0.936818

julia> T*T*T ≈ A
true
```
"""
function cbrt(A::AbstractMatrix{<:Real})
    if checksquare(A) == 0
        return copy(float(A))
    elseif isdiag(A)
        return applydiagonal(cbrt, A)
    elseif issymmetric(A)
        return copytri_maybe_inplace(parent(cbrt(Symmetric(A))), 'U')
    else
        S = schur(A)
        return S.Z * _cbrt_quasi_triu!(S.T) * S.Z'
    end
end

# Cube roots of adjoint and transpose matrices
cbrt(A::AdjointAbsMat) = adjoint(cbrt(parent(A)))
cbrt(A::TransposeAbsMat) = transpose(cbrt(parent(A)))

function applydiagonal(f, A)
    dinv = f(Diagonal(A))
    copyto!(similar(A, eltype(dinv)), dinv)
end

function inv(A::StridedMatrix{T}) where T
    checksquare(A)
    if isdiag(A)
        Ai = applydiagonal(inv, A)
    elseif istriu(A)
        Ai = triu!(parent(inv(UpperTriangular(A))))
    elseif istril(A)
        Ai = tril!(parent(inv(LowerTriangular(A))))
    else
        Ai = inv!(lu(A))
        Ai = convert(typeof(parent(Ai)), Ai)
    end
    return Ai
end

# helper function to perform a broadcast in-place if the destination is strided
# otherwise, this performs an out-of-place broadcast
@inline _broadcast!!(f, dest::StridedArray, args...) = broadcast!(f, dest, args...)
@inline _broadcast!!(f, dest, args...) = broadcast(f, args...)

"""
    cos(A::AbstractMatrix)

Compute the matrix cosine of a square matrix `A`.

If `A` is real-symmetric or Hermitian, its eigendecomposition ([`eigen`](@ref)) is used to
compute the cosine. Otherwise, the cosine is determined by calling [`exp`](@ref).

# Examples
```jldoctest
julia> cos(fill(1.0, (2,2)))
2×2 Matrix{Float64}:
  0.291927  -0.708073
 -0.708073   0.291927
```
"""
function cos(A::AbstractMatrix{<:Real})
    if isdiag(A)
        return applydiagonal(cos, A)
    elseif issymmetric(A)
        P = parent(cos(Symmetric(A)))
        return copytri_maybe_inplace(P, 'U')
    end
    M = im .* float.(A)
    return real(exp_maybe_inplace(M))
end
function cos(A::AbstractMatrix{<:Complex})
    if isdiag(A)
        return applydiagonal(cos, A)
    elseif ishermitian(A)
        P = parent(cos(Hermitian(A)))
        return copytri_maybe_inplace(P, 'U', true)
    end
    M = im .* float.(A)
    N = -M
    X = exp_maybe_inplace(M)
    Y = exp_maybe_inplace(N)
    # Compute (X + Y)/2 and return the result.
    # Compute the result in-place if X is strided
    _broadcast!!((x,y) -> (x + y)/2, X, X, Y)
end

"""
    sin(A::AbstractMatrix)

Compute the matrix sine of a square matrix `A`.

If `A` is real-symmetric or Hermitian, its eigendecomposition ([`eigen`](@ref)) is used to
compute the sine. Otherwise, the sine is determined by calling [`exp`](@ref).

# Examples
```jldoctest
julia> sin(fill(1.0, (2,2)))
2×2 Matrix{Float64}:
 0.454649  0.454649
 0.454649  0.454649
```
"""
function sin(A::AbstractMatrix{<:Real})
    if isdiag(A)
        return applydiagonal(sin, A)
    elseif issymmetric(A)
        P = parent(sin(Symmetric(A)))
        return copytri_maybe_inplace(P, 'U')
    end
    M = im .* float.(A)
    return imag(exp_maybe_inplace(M))
end
function sin(A::AbstractMatrix{<:Complex})
    if isdiag(A)
        return applydiagonal(sin, A)
    elseif ishermitian(A)
        P = parent(sin(Hermitian(A)))
        return copytri_maybe_inplace(P, 'U', true)
    end
    M = im .* float.(A)
    Mneg = -M
    X = exp_maybe_inplace(M)
    Y = exp_maybe_inplace(Mneg)
    # Compute (X - Y)/2im and return the result.
    # Compute the result in-place if X is strided
    _broadcast!!((x,y) -> (x - y)/2im, X, X, Y)
end

"""
    sincos(A::AbstractMatrix)

Compute the matrix sine and cosine of a square matrix `A`.

# Examples
```jldoctest
julia> S, C = sincos(fill(1.0, (2,2)));

julia> S
2×2 Matrix{Float64}:
 0.454649  0.454649
 0.454649  0.454649

julia> C
2×2 Matrix{Float64}:
  0.291927  -0.708073
 -0.708073   0.291927
```
"""
function sincos(A::AbstractMatrix{<:Real})
    if issymmetric(A)
        symsinA, symcosA = sincos(Symmetric(A))
        Psin = parent(symsinA)
        Pcos = parent(symcosA)
        sinA = copytri_maybe_inplace(Psin, 'U')
        cosA = copytri_maybe_inplace(Pcos, 'U')
        return sinA, cosA
    end
    M =  im .* float.(A)
    c, s = reim(exp_maybe_inplace(M))
    return s, c
end
function sincos(A::AbstractMatrix{<:Complex})
    if ishermitian(A)
        hermsinA, hermcosA = sincos(Hermitian(A))
        Psin = parent(hermsinA)
        Pcos = parent(hermcosA)
        sinA = copytri_maybe_inplace(Psin, 'U', true)
        cosA = copytri_maybe_inplace(Pcos, 'U', true)
        return sinA, cosA
    end
    M = im .* float.(A)
    Mneg = -M
    X = exp_maybe_inplace(M)
    Y = exp_maybe_inplace(Mneg)
    _sincos(X, Y)
end
function _sincos(X::StridedMatrix, Y::StridedMatrix)
    @inbounds for i in eachindex(X, Y)
        x, y = X[i]/2, Y[i]/2
        X[i] = Complex(imag(x)-imag(y), real(y)-real(x))
        Y[i] = x+y
    end
    return X, Y
end
function _sincos(X, Y)
    T = eltype(X)
    S = T(0.5)*im .* (Y .- X)
    C = T(0.5) .* (X .+ Y)
    S, C
end

"""
    tan(A::AbstractMatrix)

Compute the matrix tangent of a square matrix `A`.

If `A` is real-symmetric or Hermitian, its eigendecomposition ([`eigen`](@ref)) is used to
compute the tangent. Otherwise, the tangent is determined by calling [`exp`](@ref).

# Examples
```jldoctest
julia> tan(fill(1.0, (2,2)))
2×2 Matrix{Float64}:
 -1.09252  -1.09252
 -1.09252  -1.09252
```
"""
function tan(A::AbstractMatrix)
    if isdiag(A)
        return applydiagonal(tan, A)
    elseif ishermitian(A)
        P = parent(tan(Hermitian(A)))
        return copytri_maybe_inplace(P, 'U', true)
    end
    S, C = sincos(A)
    S /= C
    return S
end

"""
    cosh(A::AbstractMatrix)

Compute the matrix hyperbolic cosine of a square matrix `A`.
"""
function cosh(A::AbstractMatrix)
    if isdiag(A)
        return applydiagonal(cosh, A)
    elseif ishermitian(A)
        P = parent(cosh(Hermitian(A)))
        return copytri_maybe_inplace(P, 'U', true)
    end
    X = exp(A)
    negA = @. float(-A)
    Y = exp_maybe_inplace(negA)
    _broadcast!!((x,y) -> (x + y)/2, X, X, Y)
end

"""
    sinh(A::AbstractMatrix)

Compute the matrix hyperbolic sine of a square matrix `A`.
"""
function sinh(A::AbstractMatrix)
    if isdiag(A)
        return applydiagonal(sinh, A)
    elseif ishermitian(A)
        P = parent(sinh(Hermitian(A)))
        return copytri_maybe_inplace(P, 'U', true)
    end
    X = exp(A)
    negA = @. float(-A)
    Y = exp_maybe_inplace(negA)
    _broadcast!!((x,y) -> (x - y)/2, X, X, Y)
end

"""
    tanh(A::AbstractMatrix)

Compute the matrix hyperbolic tangent of a square matrix `A`.
"""
function tanh(A::AbstractMatrix)
    if isdiag(A)
        return applydiagonal(tanh, A)
    elseif ishermitian(A)
        P = parent(tanh(Hermitian(A)))
        return copytri_maybe_inplace(P, 'U', true)
    end
    X = exp(A)
    negA = @. float(-A)
    Y = exp_maybe_inplace(negA)
    X′, Y′ = _subadd!!(X, Y)
    return X′ / Y′
end
function _subadd!!(X::StridedMatrix, Y::StridedMatrix)
    @inbounds for i in eachindex(X, Y)
        x, y = X[i], Y[i]
        X[i] = x - y
        Y[i] = x + y
    end
    return X, Y
end
_subadd!!(X, Y) = X - Y, X + Y

"""
    acos(A::AbstractMatrix)

Compute the inverse matrix cosine of a square matrix `A`.

If `A` is real-symmetric or Hermitian, its eigendecomposition ([`eigen`](@ref)) is used to
compute the inverse cosine. Otherwise, the inverse cosine is determined by using
[`log`](@ref) and [`sqrt`](@ref).  For the theory and logarithmic formulas used to compute
this function, see [^AH16_1].

[^AH16_1]: Mary Aprahamian and Nicholas J. Higham, "Matrix Inverse Trigonometric and Inverse Hyperbolic Functions: Theory and Algorithms", MIMS EPrint: 2016.4. [https://doi.org/10.1137/16M1057577](https://doi.org/10.1137/16M1057577)

# Examples
```julia-repl
julia> acos(cos([0.5 0.1; -0.2 0.3]))
2×2 Matrix{ComplexF64}:
  0.5-8.32667e-17im  0.1+0.0im
 -0.2+2.63678e-16im  0.3-3.46945e-16im
```
"""
function acos(A::AbstractMatrix)
    if isdiag(A)
        return applydiagonal(acos, A)
    elseif ishermitian(A)
        return _safe_parent(acos(Hermitian(A)))
    end
    SchurF = Schur{Complex}(schur(A))
    U = UpperTriangular(SchurF.T)
    R = triu!(parent(-im * log(U + im * sqrt(I - U^2))))
    return SchurF.Z * R * SchurF.Z'
end

"""
    asin(A::AbstractMatrix)

Compute the inverse matrix sine of a square matrix `A`.

If `A` is real-symmetric or Hermitian, its eigendecomposition ([`eigen`](@ref)) is used to
compute the inverse sine. Otherwise, the inverse sine is determined by using [`log`](@ref)
and [`sqrt`](@ref).  For the theory and logarithmic formulas used to compute this function,
see [^AH16_2].

[^AH16_2]: Mary Aprahamian and Nicholas J. Higham, "Matrix Inverse Trigonometric and Inverse Hyperbolic Functions: Theory and Algorithms", MIMS EPrint: 2016.4. [https://doi.org/10.1137/16M1057577](https://doi.org/10.1137/16M1057577)

# Examples
```julia-repl
julia> asin(sin([0.5 0.1; -0.2 0.3]))
2×2 Matrix{ComplexF64}:
  0.5-4.16334e-17im  0.1-5.55112e-17im
 -0.2+9.71445e-17im  0.3-1.249e-16im
```
"""
function asin(A::AbstractMatrix)
    if isdiag(A)
        return applydiagonal(asin, A)
    elseif ishermitian(A)
        asinHermA = asin(Hermitian(A))
        P = parent(asinHermA)
        return isa(asinHermA, Hermitian) ? copytri_maybe_inplace(P, 'U', true) : P
    end
    SchurF = Schur{Complex}(schur(A))
    U = UpperTriangular(SchurF.T)
    R = triu!(parent(-im * log(im * U + sqrt(I - U^2))))
    return SchurF.Z * R * SchurF.Z'
end

"""
    atan(A::AbstractMatrix)

Compute the inverse matrix tangent of a square matrix `A`.

If `A` is real-symmetric or Hermitian, its eigendecomposition ([`eigen`](@ref)) is used to
compute the inverse tangent. Otherwise, the inverse tangent is determined by using
[`log`](@ref).  For the theory and logarithmic formulas used to compute this function, see
[^AH16_3].

[^AH16_3]: Mary Aprahamian and Nicholas J. Higham, "Matrix Inverse Trigonometric and Inverse Hyperbolic Functions: Theory and Algorithms", MIMS EPrint: 2016.4. [https://doi.org/10.1137/16M1057577](https://doi.org/10.1137/16M1057577)

# Examples
```julia-repl
julia> atan(tan([0.5 0.1; -0.2 0.3]))
2×2 Matrix{ComplexF64}:
  0.5  0.1
 -0.2  0.3
```
"""
function atan(A::AbstractMatrix)
    if isdiag(A)
        return applydiagonal(atan, A)
    elseif ishermitian(A)
        P = parent(atan(Hermitian(A)))
        return copytri_maybe_inplace(P, 'U', true)
    end
    SchurF = Schur{Complex}(schur(A))
    U = im * UpperTriangular(SchurF.T)
    R = triu!(parent(log((I + U) / (I - U)) / 2im))
    retmat = SchurF.Z * R * SchurF.Z'
    if eltype(A) <: Real
        return real(retmat)
    else
        return retmat
    end
end

"""
    acosh(A::AbstractMatrix)

Compute the inverse hyperbolic matrix cosine of a square matrix `A`.  For the theory and
logarithmic formulas used to compute this function, see [^AH16_4].

[^AH16_4]: Mary Aprahamian and Nicholas J. Higham, "Matrix Inverse Trigonometric and Inverse Hyperbolic Functions: Theory and Algorithms", MIMS EPrint: 2016.4. [https://doi.org/10.1137/16M1057577](https://doi.org/10.1137/16M1057577)
"""
function acosh(A::AbstractMatrix)
    if isdiag(A)
        return applydiagonal(acosh, A)
    elseif ishermitian(A)
        return _safe_parent(acosh(Hermitian(A)))
    end
    SchurF = Schur{Complex}(schur(A))
    U = UpperTriangular(SchurF.T)
    R = triu!(parent(log(U + sqrt(U - I) * sqrt(U + I))))
    return SchurF.Z * R * SchurF.Z'
end

"""
    asinh(A::AbstractMatrix)

Compute the inverse hyperbolic matrix sine of a square matrix `A`.  For the theory and
logarithmic formulas used to compute this function, see [^AH16_5].

[^AH16_5]: Mary Aprahamian and Nicholas J. Higham, "Matrix Inverse Trigonometric and Inverse Hyperbolic Functions: Theory and Algorithms", MIMS EPrint: 2016.4. [https://doi.org/10.1137/16M1057577](https://doi.org/10.1137/16M1057577)
"""
function asinh(A::AbstractMatrix)
    if isdiag(A)
        return applydiagonal(asinh, A)
    elseif ishermitian(A)
        P = parent(asinh(Hermitian(A)))
        return copytri_maybe_inplace(P, 'U', true)
    end
    SchurF = Schur{Complex}(schur(A))
    U = UpperTriangular(SchurF.T)
    R = triu!(parent(log(U + sqrt(I + U^2))))
    retmat = SchurF.Z * R * SchurF.Z'
    if eltype(A) <: Real
        return real(retmat)
    else
        return retmat
    end
end

"""
    atanh(A::AbstractMatrix)

Compute the inverse hyperbolic matrix tangent of a square matrix `A`.  For the theory and
logarithmic formulas used to compute this function, see [^AH16_6].

[^AH16_6]: Mary Aprahamian and Nicholas J. Higham, "Matrix Inverse Trigonometric and Inverse Hyperbolic Functions: Theory and Algorithms", MIMS EPrint: 2016.4. [https://doi.org/10.1137/16M1057577](https://doi.org/10.1137/16M1057577)
"""
function atanh(A::AbstractMatrix)
    if isdiag(A)
        return applydiagonal(atanh, A)
    elseif ishermitian(A)
        return _safe_parent(atanh(Hermitian(A)))
    end
    SchurF = Schur{Complex}(schur(A))
    U = UpperTriangular(SchurF.T)
    R = triu!(parent(log((I + U) / (I - U)) / 2))
    return SchurF.Z * R * SchurF.Z'
end

for (finv, f, finvh, fh, fn) in ((:sec, :cos, :sech, :cosh, "secant"),
                                 (:csc, :sin, :csch, :sinh, "cosecant"),
                                 (:cot, :tan, :coth, :tanh, "cotangent"))
    name = string(finv)
    hname = string(finvh)
    @eval begin
        @doc """
            $($name)(A::AbstractMatrix)

        Compute the matrix $($fn) of a square matrix `A`.
        """ ($finv)(A::AbstractMatrix{T}) where {T} = inv(($f)(A))
        @doc """
            $($hname)(A::AbstractMatrix)

        Compute the matrix hyperbolic $($fn) of square matrix `A`.
        """ ($finvh)(A::AbstractMatrix{T}) where {T} = inv(($fh)(A))
    end
end

for (tfa, tfainv, hfa, hfainv, fn) in ((:asec, :acos, :asech, :acosh, "secant"),
                                       (:acsc, :asin, :acsch, :asinh, "cosecant"),
                                       (:acot, :atan, :acoth, :atanh, "cotangent"))
    tname = string(tfa)
    hname = string(hfa)
    @eval begin
        @doc """
            $($tname)(A::AbstractMatrix)
        Compute the inverse matrix $($fn) of `A`. """ ($tfa)(A::AbstractMatrix{T}) where {T} = ($tfainv)(inv(A))
        @doc """
            $($hname)(A::AbstractMatrix)
        Compute the inverse matrix hyperbolic $($fn) of `A`. """ ($hfa)(A::AbstractMatrix{T}) where {T} = ($hfainv)(inv(A))
    end
end

"""
    factorize(A)

Compute a convenient factorization of `A`, based upon the type of the input matrix.
If `A` is passed as a generic matrix, `factorize` checks to see if it is
symmetric/triangular/etc. To this end, `factorize` may check every element of `A` to
verify/rule out each property. It will short-circuit as soon as it can rule out
symmetry/triangular structure. The return value can be reused for efficient solving
of multiple systems. For example: `A=factorize(A); x=A\\b; y=A\\C`.

| Properties of `A`          | type of factorization                          |
|:---------------------------|:-----------------------------------------------|
| Dense Symmetric/Hermitian  | Bunch-Kaufman (see [`bunchkaufman`](@ref)) |
| Sparse Symmetric/Hermitian | LDLt (see [`ldlt`](@ref))      |
| Triangular                 | Triangular                                     |
| Diagonal                   | Diagonal                                       |
| Bidiagonal                 | Bidiagonal                                     |
| Tridiagonal                | LU (see [`lu`](@ref))            |
| Symmetric real tridiagonal | LDLt (see [`ldlt`](@ref))      |
| General square             | LU (see [`lu`](@ref))            |
| General non-square         | QR (see [`qr`](@ref))            |

# Examples
```jldoctest
julia> A = Array(Bidiagonal(fill(1.0, (5, 5)), :U))
5×5 Matrix{Float64}:
 1.0  1.0  0.0  0.0  0.0
 0.0  1.0  1.0  0.0  0.0
 0.0  0.0  1.0  1.0  0.0
 0.0  0.0  0.0  1.0  1.0
 0.0  0.0  0.0  0.0  1.0

julia> factorize(A) # factorize will check to see that A is already factorized
5×5 Bidiagonal{Float64, Vector{Float64}}:
 1.0  1.0   ⋅    ⋅    ⋅
  ⋅   1.0  1.0   ⋅    ⋅
  ⋅    ⋅   1.0  1.0   ⋅
  ⋅    ⋅    ⋅   1.0  1.0
  ⋅    ⋅    ⋅    ⋅   1.0
```

This returns a `5×5 Bidiagonal{Float64}`, which can now be passed to other linear algebra
functions (e.g. eigensolvers) which will use specialized methods for `Bidiagonal` types.
"""
function factorize(A::AbstractMatrix{T}) where T
    m, n = size(A)
    if m == n
        if m == 1 return A[1] end
        utri, utri1, ltri, ltri1, sym, herm = getstructure(A)
        if ltri1
            if ltri
                if utri
                    return Diagonal(A)
                end
                if utri1
                    return Bidiagonal(diag(A), diag(A, -1), :L)
                end
                return LowerTriangular(A)
            end
            if utri
                return Bidiagonal(diag(A), diag(A, 1), :U)
            end
            if utri1
                # TODO: enable once a specialized, non-dense bunchkaufman method exists
                # if (herm & (T <: Complex)) | sym
                    # return bunchkaufman(SymTridiagonal(diag(A), diag(A, -1)))
                # end
                return lu(Tridiagonal(diag(A, -1), diag(A), diag(A, 1)))
            end
        end
        if utri
            return UpperTriangular(A)
        end
        if herm
            return factorize(Hermitian(A))
        end
        if sym
            return factorize(Symmetric(A))
        end
        return lu(A)
    end
    qr(A, ColumnNorm())
end
factorize(A::Adjoint)   =   adjoint(factorize(parent(A)))
factorize(A::Transpose) = transpose(factorize(parent(A)))
factorize(a::Number)    = a # same as how factorize behaves on Diagonal types

function getstructure(A::StridedMatrix)
    require_one_based_indexing(A)
    m, n = size(A)
    if m == 1 return A[1] end
    utri    = true
    utri1   = true
    herm    = true
    sym     = true
    for j = 1:n, i = j:m
        if (j < n) && (i > j) && utri1 # indices are off-diagonal
            if A[i,j] != 0
                utri1 = i == j + 1
                utri = false
            end
        end
        if sym
            sym &= A[i,j] == transpose(A[j,i])
        end
        if herm
            herm &= A[i,j] == adjoint(A[j,i])
        end
        if !(utri1|herm|sym) break end
    end
    ltri = true
    ltri1 = true
    for j = 3:n, i = 1:j-2
        ltri1 &= A[i,j] == 0
        if !ltri1 break end
    end
    if ltri1
        for i = 1:n-1
            if A[i,i+1] != 0
                ltri = false
                break
            end
        end
    else
        ltri = false
    end
    return (utri, utri1, ltri, ltri1, sym, herm)
end
_check_sym_herm(A) = (issymmetric(A), ishermitian(A))
_check_sym_herm(A::AbstractMatrix{<:Real}) = (sym = issymmetric(A); (sym,sym))
function getstructure(A::AbstractMatrix)
    utri1 = istriu(A,-1)
    # utri = istriu(A), but since we've already checked istriu(A,-1),
    # we only need to check that the subdiagonal band is zero
    utri = utri1 && iszero(diag(A,-1))
    sym, herm = _check_sym_herm(A)
    if sym || herm
        # in either case, the lower and upper triangular halves have identical band structures
        # in this case, istril(A,1) == istriu(A,-1) and istril(A) == istriu(A)
        ltri1 = utri1
        ltri = utri
    else
        ltri1 = istril(A,1)
        # ltri = istril(A), but since we've already checked istril(A,1),
        # we only need to check the superdiagonal band is zero
        ltri = ltri1 && iszero(diag(A,1))
    end
    return (utri, utri1, ltri, ltri1, sym, herm)
end

## Moore-Penrose pseudoinverse

"""
    pinv(M; atol::Real=0, rtol::Real=atol>0 ? 0 : n*ϵ)
    pinv(M, rtol::Real) = pinv(M; rtol=rtol) # to be deprecated in Julia 2.0

Computes the Moore-Penrose pseudoinverse.

For matrices `M` with floating point elements, it is convenient to compute
the pseudoinverse by inverting only singular values greater than
`max(atol, rtol*σ₁)` where `σ₁` is the largest singular value of `M`.

The optimal choice of absolute (`atol`) and relative tolerance (`rtol`) varies
both with the value of `M` and the intended application of the pseudoinverse.
The default relative tolerance is `n*ϵ`, where `n` is the size of the smallest
dimension of `M`, and `ϵ` is the [`eps`](@ref) of the element type of `M`.

For solving dense, ill-conditioned equations in a least-square sense, it
is better to *not* explicitly form the pseudoinverse matrix, since this
can lead to numerical instability at low tolerances.  The default `M \\ b`
algorithm instead uses pivoted QR factorization ([`qr`](@ref)).  To use an
SVD-based algorithm, it is better to employ the SVD directly via `svd(M; rtol, atol) \\ b`
or `ldiv!(svd(M), b; rtol, atol)`.

One can also pass `M = svd(A)` as the argument to `pinv` in order to re-use
an existing [`SVD`](@ref) factorization.  In this case, `pinv` will return
the SVD of the pseudo-inverse, which can be applied accurately, instead of an explicit matrix.

!!! compat "Julia 1.13"
    Passing an `SVD` object to `pinv` requires Julia 1.13 or later.

For more information, see [^pr1387], [^B96], [^S84], [^KY88].

# Examples
```jldoctest
julia> M = [1.5 1.3; 1.2 1.9]
2×2 Matrix{Float64}:
 1.5  1.3
 1.2  1.9

julia> N = pinv(M)
2×2 Matrix{Float64}:
  1.47287   -1.00775
 -0.930233   1.16279

julia> M * N
2×2 Matrix{Float64}:
 1.0          -2.22045e-16
 4.44089e-16   1.0
```

[^pr1387]: PR 1387, "stable pinv least-squares", [LinearAlgebra.jl#1387](https://github.com/JuliaLang/LinearAlgebra.jl/pull/1387)

[^B96]: Åke Björck, "Numerical Methods for Least Squares Problems",  SIAM Press, Philadelphia, 1996, "Other Titles in Applied Mathematics", Vol. 51. [doi:10.1137/1.9781611971484](http://epubs.siam.org/doi/book/10.1137/1.9781611971484)

[^S84]: G. W. Stewart, "Rank Degeneracy", SIAM Journal on Scientific and Statistical Computing, 5(2), 1984, 403-413. [doi:10.1137/0905030](http://epubs.siam.org/doi/abs/10.1137/0905030)

[^KY88]: Konstantinos Konstantinides and Kung Yao, "Statistical analysis of effective singular values in matrix rank determination", IEEE Transactions on Acoustics, Speech and Signal Processing, 36(5), 1988, 757-763. [doi:10.1109/29.1585](https://doi.org/10.1109/29.1585)
"""
function pinv(A::AbstractMatrix{T}; atol::Real=0, rtol::Real = (eps(real(float(oneunit(T))))*min(size(A)...))*iszero(atol)) where T
    m, n = size(A)
    Tout = typeof(zero(T)/sqrt(oneunit(T) + oneunit(T)))
    if m == 0 || n == 0
        return similar(A, Tout, (n, m))
    end
    if isdiag(A)
        dA = diagview(A)
        maxabsA = maximum(abs, dA)
        tol = max(rtol * maxabsA, atol)
        B = fill!(similar(A, Tout, (n, m)), 0)
        diagview(B) .= (x -> abs(x) > tol ? pinv(x) : zero(x)).(dA)
        return B
    end
    SVD         = svd(A)
    tol2        = max(rtol*maximum(SVD.S), atol)
    Stype       = eltype(SVD.S)
    Sinv        = fill!(similar(A, Stype, length(SVD.S)), 0)
    index       = SVD.S .> tol2
    Sinv[index] .= pinv.(view(SVD.S, index))
    return SVD.Vt' * (Diagonal(Sinv) * SVD.U')
end
function pinv(x::Number)
    xi = inv(x)
    return ifelse(isfinite(xi), xi, zero(xi))
end

## Basis for null space

"""
    nullspace(M; atol::Real=0, rtol::Real=atol>0 ? 0 : n*ϵ)
    nullspace(M, rtol::Real) = nullspace(M; rtol=rtol) # to be deprecated in Julia 2.0

Computes a basis for the nullspace of `M` by including the singular
vectors of `M` whose singular values have magnitudes smaller than `max(atol, rtol*σ₁)`,
where `σ₁` is `M`'s largest singular value.

By default, the relative tolerance `rtol` is `n*ϵ`, where `n`
is the size of the smallest dimension of `M`, and `ϵ` is the [`eps`](@ref) of
the element type of `M`.

# Examples
```jldoctest
julia> M = [1 0 0; 0 1 0; 0 0 0]
3×3 Matrix{Int64}:
 1  0  0
 0  1  0
 0  0  0

julia> nullspace(M)
3×1 Matrix{Float64}:
 0.0
 0.0
 1.0

julia> nullspace(M, rtol=3)
3×3 Matrix{Float64}:
 0.0  1.0  0.0
 1.0  0.0  0.0
 0.0  0.0  1.0

julia> nullspace(M, atol=0.95)
3×1 Matrix{Float64}:
 0.0
 0.0
 1.0
```
"""
function nullspace(A::AbstractVecOrMat; atol::Real=0, rtol::Real = (min(size(A, 1), size(A, 2))*eps(real(float(oneunit(eltype(A))))))*iszero(atol))
    m, n = size(A, 1), size(A, 2)
    (m == 0 || n == 0) && return Matrix{eigtype(eltype(A))}(I, n, n)
    SVD = svd(A; full=true)
    tol = max(atol, SVD.S[1]*rtol)
    indstart = sum(s -> s .> tol, SVD.S) + 1
    return copy((@view SVD.Vt[indstart:end,:])')
end

"""
    cond(M, p::Real=2)

Condition number of the matrix `M`, computed using the operator `p`-norm. Valid values for
`p` are `1`, `2` (default), or `Inf`.
"""
function cond(A::AbstractMatrix, p::Real=2)
    if p == 2
        if isempty(A)
            checksquare(A)
            return zero(real(eigtype(eltype(A))))
        end
        v = svdvals(A)
        maxv = maximum(v)
        return iszero(maxv) ? oftype(real(maxv), Inf) : maxv / minimum(v)
    elseif p == 1 || p == Inf
        checksquare(A)
        try
            Ainv = inv(A)
            return opnorm(A, p)*opnorm(Ainv, p)
        catch e
            if isa(e, LAPACKException) || isa(e, SingularException)
                return convert(float(real(eltype(A))), Inf)
            else
                rethrow()
            end
        end
    end
    throw(ArgumentError(lazy"p-norm must be 1, 2 or Inf, got $p"))
end

## Lyapunov and Sylvester equation

# AX + XB + C = 0

"""
    sylvester(A, B, C)

Computes the solution `X` to the Sylvester equation `AX + XB + C = 0`, where `A`, `B` and
`C` have compatible dimensions and `A` and `-B` have no eigenvalues with equal real part.

# Examples
```jldoctest
julia> A = [3. 4.; 5. 6]
2×2 Matrix{Float64}:
 3.0  4.0
 5.0  6.0

julia> B = [1. 1.; 1. 2.]
2×2 Matrix{Float64}:
 1.0  1.0
 1.0  2.0

julia> C = [1. 2.; -2. 1]
2×2 Matrix{Float64}:
  1.0  2.0
 -2.0  1.0

julia> X = sylvester(A, B, C)
2×2 Matrix{Float64}:
 -4.46667   1.93333
  3.73333  -1.8

julia> A*X + X*B ≈ -C
true
```
"""
function sylvester(A::AbstractMatrix, B::AbstractMatrix, C::AbstractMatrix)
    T = promote_type(float(eltype(A)), float(eltype(B)), float(eltype(C)))
    return sylvester(copy_similar(A, T), copy_similar(B, T), copy_similar(C, T))
end
function sylvester(A::AbstractMatrix{T}, B::AbstractMatrix{T}, C::AbstractMatrix{T}) where {T<:BlasFloat}
    RA, QA = schur(A)
    RB, QB = schur(B)
    D = QA' * C * QB
    D .= .-D
    Y, scale = LAPACK.trsyl!('N', 'N', RA, RB, D)
    rmul!(QA * Y * QB', inv(scale))
end

Base.@propagate_inbounds function _sylvester_2x1!(A, B, C)
    b = B[1]
    a21, a12 = A[2, 1], A[1, 2]
    m11 = b + A[1, 1]
    m22 = b + A[2, 2]
    d = m11 * m22 - a12 * a21
    c1, c2 = C
    C[1] = (a12 * c2 - m22 * c1) / d
    C[2] = (a21 * c1 - m11 * c2) / d
    return C
end
Base.@propagate_inbounds function _sylvester_1x2!(A, B, C)
    a = A[1]
    b21, b12 = B[2, 1], B[1, 2]
    m11 = a + B[1, 1]
    m22 = a + B[2, 2]
    d = m11 * m22 - b21 * b12
    c1, c2 = C
    C[1] = (b21 * c2 - m22 * c1) / d
    C[2] = (b12 * c1 - m11 * c2) / d
    return C
end
function _sylvester_2x2!(A, B, C)
    _, scale = LAPACK.trsyl!('N', 'N', A, B, C)
    rmul!(C, -inv(scale))
    return C
end

sylvester(a::Union{Real,Complex}, b::Union{Real,Complex}, c::Union{Real,Complex}) = -c / (a + b)

# AX + XA' + C = 0

"""
    lyap(A, C)

Computes the solution `X` to the continuous Lyapunov equation `AX + XA' + C = 0`, where no
eigenvalue of `A` has a zero real part and no two eigenvalues are negative complex
conjugates of each other.

# Examples
```jldoctest
julia> A = [3. 4.; 5. 6]
2×2 Matrix{Float64}:
 3.0  4.0
 5.0  6.0

julia> B = [1. 1.; 1. 2.]
2×2 Matrix{Float64}:
 1.0  1.0
 1.0  2.0

julia> X = lyap(A, B)
2×2 Matrix{Float64}:
  0.5  -0.5
 -0.5   0.25

julia> A*X + X*A' ≈ -B
true
```
"""
function lyap(A::AbstractMatrix, C::AbstractMatrix)
    T = promote_type(float(eltype(A)), float(eltype(C)))
    return lyap(copy_similar(A, T), copy_similar(C, T))
end
function lyap(A::AbstractMatrix{T}, C::AbstractMatrix{T}) where {T<:BlasFloat}
    R, Q = schur(A)
    D = Q' * C * Q
    D .= .-D
    Y, scale = LAPACK.trsyl!('N', T <: Complex ? 'C' : 'T', R, R, D)
    rmul!(Q * Y * Q', inv(scale))
end
lyap(a::Union{Real,Complex}, c::Union{Real,Complex}) = -c/(2real(a))
