# This file is a part of Julia. License is MIT: https://julialang.org/license

##########################
# Cholesky Factorization #
##########################

# The dispatch structure in the cholesky, and cholesky! methods is a bit
# complicated and some explanation is therefore provided in the following
#
# In the methods below, LAPACK is called when possible, i.e. StridedMatrices with Float32,
# Float64, ComplexF32, and ComplexF64 element types. For other element or
# matrix types, the unblocked Julia implementation in _chol! is used. For cholesky
# and cholesky! pivoting is supported through a RowMaximum() argument. A type argument is
# necessary for type stability since the output of cholesky and cholesky! is either
# Cholesky or CholeskyPivoted. The latter is only
# supported for the four LAPACK element types. For other types, e.g. BigFloats RowMaximum() will
# give an error. It is required that the input is Hermitian (including real symmetric) either
# through the Hermitian and Symmetric views or exact symmetric or Hermitian elements which
# is checked for and an error is thrown if the check fails.

# The internal structure is as follows
# - _chol! returns the factor and info without checking positive definiteness
# - cholesky/cholesky! returns Cholesky without checking positive definiteness

# FixMe? The dispatch below seems overly complicated. One simplification could be to
# merge the two Cholesky types into one. It would remove the need for Val completely but
# the cost would be extra unnecessary/unused fields for the unpivoted Cholesky and runtime
# checks of those fields before calls to LAPACK to check which version of the Cholesky
# factorization the type represents.
"""
    Cholesky <: Factorization

Matrix factorization type of the Cholesky factorization of a dense symmetric/Hermitian
positive definite matrix `A`. This is the return type of [`cholesky`](@ref),
the corresponding matrix factorization function.

The triangular Cholesky factor can be obtained from the factorization `F::Cholesky`
via `F.L` and `F.U`, where `A ≈ F.U' * F.U ≈ F.L * F.L'`.

The following functions are available for `Cholesky` objects: [`size`](@ref), [`\\`](@ref),
[`inv`](@ref), [`det`](@ref), [`logdet`](@ref) and [`isposdef`](@ref).

Iterating the decomposition produces the components `L` and `U`.

# Examples
```jldoctest
julia> A = [4. 12. -16.; 12. 37. -43.; -16. -43. 98.]
3×3 Matrix{Float64}:
   4.0   12.0  -16.0
  12.0   37.0  -43.0
 -16.0  -43.0   98.0

julia> C = cholesky(A)
Cholesky{Float64, Matrix{Float64}}
U factor:
3×3 UpperTriangular{Float64, Matrix{Float64}}:
 2.0  6.0  -8.0
  ⋅   1.0   5.0
  ⋅    ⋅    3.0

julia> C.U
3×3 UpperTriangular{Float64, Matrix{Float64}}:
 2.0  6.0  -8.0
  ⋅   1.0   5.0
  ⋅    ⋅    3.0

julia> C.L
3×3 LowerTriangular{Float64, Adjoint{Float64, Matrix{Float64}}}:
  2.0   ⋅    ⋅
  6.0  1.0   ⋅
 -8.0  5.0  3.0

julia> C.L * C.U == A
true

julia> l, u = C; # destructuring via iteration

julia> l == C.L && u == C.U
true
```
"""
struct Cholesky{T,S<:AbstractMatrix} <: Factorization{T}
    factors::S
    uplo::Char
    info::BlasInt

    function Cholesky{T,S}(factors, uplo, info) where {T,S<:AbstractMatrix}
        require_one_based_indexing(factors)
        new(factors, uplo, info)
    end
end
Cholesky(A::AbstractMatrix{T}, uplo::Symbol, info::Integer) where {T} =
    Cholesky{T,typeof(A)}(A, char_uplo(uplo), info)
Cholesky(A::AbstractMatrix{T}, uplo::AbstractChar, info::Integer) where {T} =
    Cholesky{T,typeof(A)}(A, uplo, info)
Cholesky(U::UpperTriangular{T}) where {T} = Cholesky{T,typeof(U.data)}(U.data, 'U', 0)
Cholesky(L::LowerTriangular{T}) where {T} = Cholesky{T,typeof(L.data)}(L.data, 'L', 0)

# iteration for destructuring into components
Base.iterate(C::Cholesky) = (C.L, Val(:U))
Base.iterate(C::Cholesky, ::Val{:U}) = (C.U, Val(:done))
Base.iterate(C::Cholesky, ::Val{:done}) = nothing


"""
    CholeskyPivoted

Matrix factorization type of the pivoted Cholesky factorization of a dense symmetric/Hermitian
positive semi-definite matrix `A`. This is the return type of [`cholesky(_, ::RowMaximum)`](@ref),
the corresponding matrix factorization function.

The triangular Cholesky factor can be obtained from the factorization `F::CholeskyPivoted`
via `F.L` and `F.U`, and the permutation via `F.p`, where `A[F.p, F.p] ≈ Ur' * Ur ≈ Lr * Lr'`
with `Ur = F.U[1:F.rank, :]` and `Lr = F.L[:, 1:F.rank]`, or alternatively
`A ≈ Up' * Up ≈ Lp * Lp'` with `Up = F.U[1:F.rank, invperm(F.p)]` and
`Lp = F.L[invperm(F.p), 1:F.rank]`.

The following functions are available for `CholeskyPivoted` objects:
[`size`](@ref), [`\\`](@ref), [`inv`](@ref), [`det`](@ref), and [`rank`](@ref).

Iterating the decomposition produces the components `L` and `U`.

# Examples
```jldoctest
julia> X = [1.0, 2.0, 3.0, 4.0];

julia> A = X * X';

julia> C = cholesky(A, RowMaximum(), check = false)
CholeskyPivoted{Float64, Matrix{Float64}, Vector{Int64}}
U factor with rank 1:
4×4 UpperTriangular{Float64, Matrix{Float64}}:
 4.0  2.0  3.0  1.0
  ⋅   0.0  6.0  2.0
  ⋅    ⋅   9.0  3.0
  ⋅    ⋅    ⋅   1.0
permutation:
4-element Vector{Int64}:
 4
 2
 3
 1

julia> C.U[1:C.rank, :]' * C.U[1:C.rank, :] ≈ A[C.p, C.p]
true

julia> l, u = C; # destructuring via iteration

julia> l == C.L && u == C.U
true
```
"""
struct CholeskyPivoted{T,S<:AbstractMatrix,P<:AbstractVector{<:Integer}} <: Factorization{T}
    factors::S
    uplo::Char
    piv::P
    rank::BlasInt
    tol::Real
    info::BlasInt

    function CholeskyPivoted{T,S,P}(factors, uplo, piv, rank, tol, info) where {T,S<:AbstractMatrix,P<:AbstractVector}
        require_one_based_indexing(factors)
        new{T,S,P}(factors, uplo, piv, rank, tol, info)
    end
end
CholeskyPivoted(A::AbstractMatrix{T}, uplo::AbstractChar, piv::AbstractVector{<:Integer},
                rank::Integer, tol::Real, info::Integer) where T =
    CholeskyPivoted{T,typeof(A),typeof(piv)}(A, uplo, piv, rank, tol, info)
# backwards-compatible constructors (remove with Julia 2.0)
@deprecate(CholeskyPivoted{T,S}(factors, uplo, piv, rank, tol, info) where {T,S<:AbstractMatrix},
           CholeskyPivoted{T,S,typeof(piv)}(factors, uplo, piv, rank, tol, info), false)


# iteration for destructuring into components
Base.iterate(C::CholeskyPivoted) = (C.L, Val(:U))
Base.iterate(C::CholeskyPivoted, ::Val{:U}) = (C.U, Val(:done))
Base.iterate(C::CholeskyPivoted, ::Val{:done}) = nothing


# make a copy that allow inplace Cholesky factorization
choltype(A) = promote_type(typeof(sqrt(oneunit(eltype(A)))), Float32)
cholcopy(A::AbstractMatrix) = eigencopy_oftype(A, choltype(A))

# _chol!. Internal methods for calling unpivoted Cholesky
## BLAS/LAPACK element types
function _chol!(A::StridedMatrix{<:BlasFloat}, ::Type{UpperTriangular})
    C, info = LAPACK.potrf!('U', A)
    return UpperTriangular(C), info
end
function _chol!(A::StridedMatrix{<:BlasFloat}, ::Type{LowerTriangular})
    C, info = LAPACK.potrf!('L', A)
    return LowerTriangular(C), info
end

## Non BLAS/LAPACK element types (generic)
function _chol!(A::AbstractMatrix, ::Type{UpperTriangular})
    require_one_based_indexing(A)
    n = checksquare(A)
    realdiag = eltype(A) <: Complex
    @inbounds begin
        for k = 1:n
            Akk = realdiag ? real(A[k,k]) : A[k,k]
            for i = 1:k - 1
                Akk -= realdiag ? abs2(A[i,k]) : A[i,k]'A[i,k]
            end
            A[k,k] = Akk
            Akk, info = _chol!(Akk, UpperTriangular)
            if info != 0
                return UpperTriangular(A), convert(BlasInt, k)
            end
            A[k,k] = Akk
            AkkInv = inv(copy(Akk'))
            for j = k + 1:n
                @simd for i = 1:k - 1
                    A[k,j] -= A[i,k]'A[i,j]
                end
                A[k,j] = AkkInv*A[k,j]
            end
        end
    end
    return UpperTriangular(A), convert(BlasInt, 0)
end
function _chol!(A::AbstractMatrix, ::Type{LowerTriangular})
    require_one_based_indexing(A)
    n = checksquare(A)
    realdiag = eltype(A) <: Complex
    @inbounds begin
        for k = 1:n
            Akk = realdiag ? real(A[k,k]) : A[k,k]
            for i = 1:k - 1
                Akk -= realdiag ? abs2(A[k,i]) : A[k,i]*A[k,i]'
            end
            A[k,k] = Akk
            Akk, info = _chol!(Akk, LowerTriangular)
            if info != 0
                return LowerTriangular(A), convert(BlasInt, k)
            end
            A[k,k] = Akk
            AkkInv = inv(copy(Akk'))
            for j = 1:k - 1
                Akjc = A[k,j]'
                @simd for i = k + 1:n
                    A[i,k] -= A[i,j]*Akjc
                end
            end
            @simd for i = k + 1:n
                A[i,k] *= AkkInv
            end
        end
     end
    return LowerTriangular(A), convert(BlasInt, 0)
end

## Numbers
function _chol!(x::Number, _)
    rx = real(x)
    iszero(rx) && return (rx, convert(BlasInt, 1))
    rxr = sqrt(abs(rx))
    rval = convert(promote_type(typeof(x), typeof(rxr)), rxr)
    return (rval, convert(BlasInt, rx != abs(x)))
end

# _cholpivoted!. Internal methods for calling pivoted Cholesky
Base.@propagate_inbounds function _swap_rowcols!(A, ::Type{UpperTriangular}, n, j, q)
    j == q && return
    @assert j < q
    # swap rows and cols without touching the possibly undef-ed triangle
    A[q, q] = A[j, j]
    for k in 1:j-1 # initial vertical segments
        A[k,j], A[k,q] = A[k,q], A[k,j]
    end
    for k in j+1:q-1 # intermediate segments
        A[j,k], A[k,q] = conj(A[k,q]), conj(A[j,k])
    end
    A[j,q] = conj(A[j,q]) # corner case
    for k in q+1:n # final horizontal segments
        A[j,k], A[q,k] = A[q,k], A[j,k]
    end
    return
end
Base.@propagate_inbounds function _swap_rowcols!(A, ::Type{LowerTriangular}, n, j, q)
    j == q && return
    @assert j < q
    # swap rows and cols without touching the possibly undef-ed triangle
    A[q, q] = A[j, j]
    for k in 1:j-1 # initial horizontal segments
        A[j,k], A[q,k] = A[q,k], A[j,k]
    end
    for k in j+1:q-1 # intermediate segments
        A[k,j], A[q,k] = conj(A[q,k]), conj(A[k,j])
    end
    A[q,j] = conj(A[q,j]) # corner case
    for k in q+1:n # final vertical segments
        A[k,j], A[k,q] = A[k,q], A[k,j]
    end
    return
end
### BLAS/LAPACK element types
_cholpivoted!(A::StridedMatrix{<:BlasFloat}, ::Type{UpperTriangular}, tol::Real, check::Bool) =
    LAPACK.pstrf!('U', A, tol)
_cholpivoted!(A::StridedMatrix{<:BlasFloat}, ::Type{LowerTriangular}, tol::Real, check::Bool) =
    LAPACK.pstrf!('L', A, tol)
## Non BLAS/LAPACK element types (generic)
function _cholpivoted!(A::AbstractMatrix, ::Type{UpperTriangular}, tol::Real, check::Bool)
    rTA = real(eltype(A))
    # checks
    Base.require_one_based_indexing(A)
    n = checksquare(A)
    # initialization
    piv = collect(1:n)
    dots = zeros(rTA, n)
    temp = similar(dots)

    @inbounds begin
        # first step
        Akk, q = findmax(i -> real(A[i,i]), 1:n)
        stop = tol < 0 ? eps(rTA)*n*abs(Akk) : tol
        Akk ≤ stop && return A, piv, convert(BlasInt, 0), convert(BlasInt, 1)
        # swap
        _swap_rowcols!(A, UpperTriangular, n, 1, q)
        piv[1], piv[q] = piv[q], piv[1]
        A[1,1] = Akk = sqrt(Akk)
        AkkInv = inv(copy(Akk'))
        @simd for j in 2:n
            A[1, j] *= AkkInv
        end

        for k in 2:n
            @simd for j in k:n
                dots[j] += abs2(A[k-1, j])
                temp[j] = real(A[j,j]) - dots[j]
            end
            Akk, q = findmax(j -> temp[j], k:n)
            Akk ≤ stop && return A, piv, convert(BlasInt, k - 1), convert(BlasInt, 1)
            q += k - 1
            # swap
            _swap_rowcols!(A, UpperTriangular, n, k, q)
            dots[k], dots[q] = dots[q], dots[k]
            piv[k], piv[q] = piv[q], piv[k]
            # update
            A[k,k] = Akk = sqrt(Akk)
            AkkInv = inv(copy(Akk'))
            for j in (k+1):n
                @simd for i in 1:(k-1)
                    A[k,j] -= A[i,k]'A[i,j]
                end
                A[k,j] = AkkInv * A[k,j]
            end
        end
        return A, piv, convert(BlasInt, n), convert(BlasInt, 0)
    end
end
function _cholpivoted!(A::AbstractMatrix, ::Type{LowerTriangular}, tol::Real, check::Bool)
    rTA = real(eltype(A))
    # checks
    Base.require_one_based_indexing(A)
    n = checksquare(A)
    # initialization
    piv = collect(1:n)
    dots = zeros(rTA, n)
    temp = similar(dots)

    @inbounds begin
        # first step
        Akk, q = findmax(i -> real(A[i,i]), 1:n)
        stop = tol < 0 ? eps(rTA)*n*abs(Akk) : tol
        Akk ≤ stop && return A, piv, convert(BlasInt, 0), convert(BlasInt, 1)
        # swap
        _swap_rowcols!(A, LowerTriangular, n, 1, q)
        piv[1], piv[q] = piv[q], piv[1]
        A[1,1] = Akk = sqrt(Akk)
        AkkInv = inv(copy(Akk'))
        @simd for i in 2:n
            A[i,1] *= AkkInv
        end

        for k in 2:n
            @simd for j in k:n
                dots[j] += abs2(A[j, k-1])
                temp[j] = real(A[j,j]) - dots[j]
            end
            Akk, q = findmax(i -> temp[i], k:n)
            Akk ≤ stop && return A, piv, convert(BlasInt, k-1), convert(BlasInt, 1)
            q += k - 1
            # swap
            _swap_rowcols!(A, LowerTriangular, n, k, q)
            dots[k], dots[q] = dots[q], dots[k]
            piv[k], piv[q] = piv[q], piv[k]
            # update
            A[k,k] = Akk = sqrt(Akk)
            for j in 1:(k-1)
                Akjc = A[k,j]'
                @simd for i in (k+1):n
                    A[i,k] -= A[i,j]*Akjc
                end
            end
            AkkInv = inv(copy(Akk'))
            @simd for i in (k+1):n
                A[i, k] *= AkkInv
            end
        end
        return A, piv, convert(BlasInt, n), convert(BlasInt, 0)
    end
end
function _cholpivoted!(x::Number, tol)
    rx = real(x)
    iszero(rx) && return (rx, convert(BlasInt, 1))
    rxr = sqrt(abs(rx))
    rval = convert(promote_type(typeof(x), typeof(rxr)), rxr)
    return (rval, convert(BlasInt, !(rx == abs(x) > tol)))
end

# cholesky!. Destructive methods for computing Cholesky factorization of real symmetric
# or Hermitian matrix
## No pivoting (default)
function cholesky!(A::SelfAdjoint, ::NoPivot = NoPivot(); check::Bool = true)
    C, info = _chol!(A.data, A.uplo == 'U' ? UpperTriangular : LowerTriangular)
    check && checkpositivedefinite(info)
    return Cholesky(C.data, A.uplo, info)
end

### for AbstractMatrix, check that matrix is symmetric/Hermitian
"""
    cholesky!(A::AbstractMatrix, NoPivot(); check = true) -> Cholesky

The same as [`cholesky`](@ref), but saves space by overwriting the input `A`,
instead of creating a copy. An [`InexactError`](@ref) exception is thrown if
the factorization produces a number not representable by the element type of
`A`, e.g. for integer types.

# Examples
```jldoctest
julia> A = [1 2; 2 50]
2×2 Matrix{Int64}:
 1   2
 2  50

julia> cholesky!(A)
ERROR: InexactError: Int64(6.782329983125268)
Stacktrace:
[...]
```
"""
function cholesky!(A::AbstractMatrix, ::NoPivot = NoPivot(); check::Bool = true)
    checksquare(A)
    if !ishermitian(A) # return with info = -1 if not Hermitian
        check && checkpositivedefinite(convert(BlasInt, -1))
        return Cholesky(A, 'U', convert(BlasInt, -1))
    else
        return cholesky!(Hermitian(A), NoPivot(); check = check)
    end
end
@deprecate cholesky!(A::StridedMatrix, ::Val{false}; check::Bool = true) cholesky!(A, NoPivot(); check) false
@deprecate cholesky!(A::RealHermSymComplexHerm, ::Val{false}; check::Bool = true) cholesky!(A, NoPivot(); check) false

## With pivoting
### Non BLAS/LAPACK element types (generic).
function cholesky!(A::SelfAdjoint, ::RowMaximum; tol = 0.0, check::Bool = true)
    AA, piv, rank, info = _cholpivoted!(A.data, A.uplo == 'U' ? UpperTriangular : LowerTriangular, tol, check)
    C = CholeskyPivoted(AA, A.uplo, piv, rank, tol, info)
    check && chkfullrank(C)
    return C
end
@deprecate cholesky!(A::RealHermSymComplexHerm{<:Real}, ::Val{true}; kwargs...) cholesky!(A, RowMaximum(); kwargs...) false

"""
    cholesky!(A::AbstractMatrix, RowMaximum(); tol = 0.0, check = true) -> CholeskyPivoted

The same as [`cholesky`](@ref), but saves space by overwriting the input `A`,
instead of creating a copy. An [`InexactError`](@ref) exception is thrown if the
factorization produces a number not representable by the element type of `A`,
e.g. for integer types.
"""
function cholesky!(A::AbstractMatrix, ::RowMaximum; tol = 0.0, check::Bool = true)
    checksquare(A)
    if !ishermitian(A)
        C = CholeskyPivoted(A, 'U', Vector{BlasInt}(), convert(BlasInt, 1),
                            tol, convert(BlasInt, -1))
        check && checkpositivedefinite(convert(BlasInt, -1))
        return C
    else
        return cholesky!(Hermitian(A), RowMaximum(); tol, check)
    end
end
@deprecate cholesky!(A::StridedMatrix, ::Val{true}; kwargs...) cholesky!(A, RowMaximum(); kwargs...) false

# cholesky. Non-destructive methods for computing Cholesky factorization of real symmetric
# or Hermitian matrix
## No pivoting (default)
"""
    cholesky(A, NoPivot(); check = true) -> Cholesky

Compute the Cholesky factorization of a dense symmetric positive definite matrix `A`
and return a [`Cholesky`](@ref) factorization. The matrix `A` can either be a [`Symmetric`](@ref) or [`Hermitian`](@ref)
[`AbstractMatrix`](@ref) or a *perfectly* symmetric or Hermitian `AbstractMatrix`.

The triangular Cholesky factor can be obtained from the factorization `F` via `F.L` and `F.U`,
where `A ≈ F.U' * F.U ≈ F.L * F.L'`.

The following functions are available for `Cholesky` objects: [`size`](@ref), [`\\`](@ref),
[`inv`](@ref), [`det`](@ref), [`logdet`](@ref) and [`isposdef`](@ref).

If you have a matrix `A` that is slightly non-Hermitian due to roundoff errors in its construction,
wrap it in `Hermitian(A)` before passing it to `cholesky` in order to treat it as perfectly Hermitian.

When `check = true`, an error is thrown if the decomposition fails.
When `check = false`, responsibility for checking the decomposition's
validity (via [`issuccess`](@ref)) lies with the user.

# Examples
```jldoctest
julia> A = [4. 12. -16.; 12. 37. -43.; -16. -43. 98.]
3×3 Matrix{Float64}:
   4.0   12.0  -16.0
  12.0   37.0  -43.0
 -16.0  -43.0   98.0

julia> C = cholesky(A)
Cholesky{Float64, Matrix{Float64}}
U factor:
3×3 UpperTriangular{Float64, Matrix{Float64}}:
 2.0  6.0  -8.0
  ⋅   1.0   5.0
  ⋅    ⋅    3.0

julia> C.U
3×3 UpperTriangular{Float64, Matrix{Float64}}:
 2.0  6.0  -8.0
  ⋅   1.0   5.0
  ⋅    ⋅    3.0

julia> C.L
3×3 LowerTriangular{Float64, Adjoint{Float64, Matrix{Float64}}}:
  2.0   ⋅    ⋅
  6.0  1.0   ⋅
 -8.0  5.0  3.0

julia> C.L * C.U == A
true
```
"""
cholesky(A::AbstractMatrix, ::NoPivot=NoPivot(); check::Bool = true) =
    _cholesky(cholcopy(A); check)
@deprecate cholesky(A::Union{StridedMatrix,RealHermSymComplexHerm{<:Real,<:StridedMatrix}}, ::Val{false}; check::Bool = true) cholesky(A, NoPivot(); check) false

function cholesky(A::AbstractMatrix{Float16}, ::NoPivot=NoPivot(); check::Bool = true)
    X = _cholesky(cholcopy(A); check = check)
    return Cholesky{Float16}(X)
end
@deprecate cholesky(A::Union{StridedMatrix{Float16},RealHermSymComplexHerm{Float16,<:StridedMatrix}}, ::Val{false}; check::Bool = true) cholesky(A, NoPivot(); check) false
# allow packages like SparseArrays.jl to hook into here and redirect to out-of-place `cholesky`
_cholesky(A::AbstractMatrix, args...; kwargs...) = cholesky!(A, args...; kwargs...)

# allow cholesky of cholesky
cholesky(A::Cholesky) = A

## With pivoting
"""
    cholesky(A, RowMaximum(); tol = 0.0, check = true) -> CholeskyPivoted

Compute the pivoted Cholesky factorization of a dense symmetric positive semi-definite matrix `A`
and return a [`CholeskyPivoted`](@ref) factorization. The matrix `A` can either be a [`Symmetric`](@ref)
or [`Hermitian`](@ref) [`AbstractMatrix`](@ref) or a *perfectly* symmetric or Hermitian `AbstractMatrix`.

The triangular Cholesky factor can be obtained from the factorization `F` via `F.L` and `F.U`,
and the permutation via `F.p`, where `A[F.p, F.p] ≈ Ur' * Ur ≈ Lr * Lr'` with `Ur = F.U[1:F.rank, :]`
and `Lr = F.L[:, 1:F.rank]`, or alternatively `A ≈ Up' * Up ≈ Lp * Lp'` with
`Up = F.U[1:F.rank, invperm(F.p)]` and `Lp = F.L[invperm(F.p), 1:F.rank]`.

The following functions are available for `CholeskyPivoted` objects:
[`size`](@ref), [`\\`](@ref), [`inv`](@ref), [`det`](@ref), and [`rank`](@ref).

The argument `tol` determines the tolerance for determining the rank.
For negative values, the tolerance is equal to `eps()*size(A,1)*maximum(diag(A))`.

If you have a matrix `A` that is slightly non-Hermitian due to roundoff errors in its construction,
wrap it in `Hermitian(A)` before passing it to `cholesky` in order to treat it as perfectly Hermitian.

When `check = true`, an error is thrown if the decomposition fails.
When `check = false`, responsibility for checking the decomposition's
validity (via [`issuccess`](@ref)) lies with the user.

# Examples
```jldoctest
julia> X = [1.0, 2.0, 3.0, 4.0];

julia> A = X * X';

julia> C = cholesky(A, RowMaximum(), check = false)
CholeskyPivoted{Float64, Matrix{Float64}, Vector{Int64}}
U factor with rank 1:
4×4 UpperTriangular{Float64, Matrix{Float64}}:
 4.0  2.0  3.0  1.0
  ⋅   0.0  6.0  2.0
  ⋅    ⋅   9.0  3.0
  ⋅    ⋅    ⋅   1.0
permutation:
4-element Vector{Int64}:
 4
 2
 3
 1

julia> C.U[1:C.rank, :]' * C.U[1:C.rank, :] ≈ A[C.p, C.p]
true

julia> l, u = C; # destructuring via iteration

julia> l == C.L && u == C.U
true
```
"""
cholesky(A::AbstractMatrix, ::RowMaximum; tol = 0.0, check::Bool = true) =
    _cholesky(cholcopy(A), RowMaximum(); tol, check)
@deprecate cholesky(A::Union{StridedMatrix,RealHermSymComplexHerm{<:Real,<:StridedMatrix}}, ::Val{true}; tol = 0.0, check::Bool = true) cholesky(A, RowMaximum(); tol, check) false

function cholesky(A::AbstractMatrix{Float16}, ::RowMaximum; tol = 0.0, check::Bool = true)
    X = _cholesky(cholcopy(A), RowMaximum(); tol, check)
    return CholeskyPivoted{Float16}(X)
end

## Number
function cholesky(x::Number, uplo::Symbol=:U)
    C, info = _chol!(x, uplo)
    xf = fill(C, 1, 1)
    Cholesky(xf, uplo, info)
end


function Cholesky{T}(C::Cholesky) where T
    Cnew = convert(AbstractMatrix{T}, C.factors)
    Cholesky{T, typeof(Cnew)}(Cnew, C.uplo, C.info)
end
Cholesky{T,S}(C::Cholesky) where {T,S<:AbstractMatrix} = Cholesky{T,S}(C.factors, C.uplo, C.info)
Factorization{T}(C::Cholesky{T}) where {T} = C
Factorization{T}(C::Cholesky) where {T} = Cholesky{T}(C)
CholeskyPivoted{T}(C::CholeskyPivoted{T}) where {T} = C
CholeskyPivoted{T}(C::CholeskyPivoted) where {T} =
    CholeskyPivoted(AbstractMatrix{T}(C.factors), C.uplo, C.piv, C.rank, C.tol, C.info)
CholeskyPivoted{T,S}(C::CholeskyPivoted) where {T,S<:AbstractMatrix} =
    CholeskyPivoted{T,S,typeof(C.piv)}(C.factors, C.uplo, C.piv, C.rank, C.tol, C.info)
CholeskyPivoted{T,S,P}(C::CholeskyPivoted) where {T,S<:AbstractMatrix,P<:AbstractVector{<:Integer}} =
    CholeskyPivoted{T,S,P}(C.factors, C.uplo, C.piv, C.rank, C.tol, C.info)
Factorization{T}(C::CholeskyPivoted{T}) where {T} = C
Factorization{T}(C::CholeskyPivoted) where {T} = CholeskyPivoted{T}(C)

AbstractMatrix(C::Cholesky) = C.uplo == 'U' ? C.U'C.U : C.L*C.L'
AbstractArray(C::Cholesky) = AbstractMatrix(C)
Matrix(C::Cholesky) = Array(AbstractArray(C))
Array(C::Cholesky) = Matrix(C)

function AbstractMatrix(F::CholeskyPivoted)
    ip = invperm(F.p)
    U = F.U[1:F.rank,ip]
    U'U
end
AbstractArray(F::CholeskyPivoted) = AbstractMatrix(F)
Matrix(F::CholeskyPivoted) = Array(AbstractArray(F))
Array(F::CholeskyPivoted) = Matrix(F)

copy(C::Cholesky) = Cholesky(copy(C.factors), C.uplo, C.info)
copy(C::CholeskyPivoted) = CholeskyPivoted(copy(C.factors), C.uplo, C.piv, C.rank, C.tol, C.info)

size(C::Union{Cholesky, CholeskyPivoted}) = size(C.factors)
size(C::Union{Cholesky, CholeskyPivoted}, d::Integer) = size(C.factors, d)

function getproperty(C::Cholesky, d::Symbol)
    Cfactors = getfield(C, :factors)
    Cuplo    = getfield(C, :uplo)
    if d === :U
        UpperTriangular(Cuplo == 'U' ? Cfactors : Cfactors')
    elseif d === :L
        LowerTriangular(Cuplo == 'L' ? Cfactors : Cfactors')
    elseif d === :UL
        return (Cuplo == 'U' ? UpperTriangular(Cfactors) : LowerTriangular(Cfactors))
    else
        return getfield(C, d)
    end
end
Base.propertynames(F::Cholesky, private::Bool=false) =
    (:U, :L, :UL, (private ? fieldnames(typeof(F)) : ())...)

function Base.:(==)(C1::C, C2::D) where {C<:Cholesky, D<:Cholesky}
    C1.uplo == C2.uplo || return false
    C1.uplo == 'L' ? (C1.L == C2.L) : (C1.U == C2.U)
end

function getproperty(C::CholeskyPivoted{T}, d::Symbol) where {T}
    Cfactors = getfield(C, :factors)
    Cuplo    = getfield(C, :uplo)
    if d === :U
        UpperTriangular(Cuplo == 'U' ? Cfactors : Cfactors')
    elseif d === :L
        LowerTriangular(Cuplo == 'L' ? Cfactors : Cfactors')
    elseif d === :p
        return getfield(C, :piv)
    elseif d === :P
        n = size(C, 1)
        P = zeros(T, n, n)
        for i = 1:n
            P[getfield(C, :piv)[i], i] = one(T)
        end
        return P
    else
        return getfield(C, d)
    end
end
Base.propertynames(F::CholeskyPivoted, private::Bool=false) =
    (:U, :L, :p, :P, (private ? fieldnames(typeof(F)) : ())...)

function Base.:(==)(C1::CholeskyPivoted, C2::CholeskyPivoted)
    (C1.uplo == C2.uplo && C1.p == C2.p) || return false
    C1.uplo == 'L' ? (C1.L == C2.L) : (C1.U == C2.U)
end

issuccess(C::Union{Cholesky,CholeskyPivoted}) = C.info == 0

adjoint(C::Union{Cholesky,CholeskyPivoted}) = C

function show(io::IO, mime::MIME{Symbol("text/plain")}, C::Cholesky)
    if issuccess(C)
        summary(io, C); println(io)
        println(io, "$(C.uplo) factor:")
        show(io, mime, C.UL)
    else
        print(io, "Failed factorization of type $(typeof(C))")
    end
end

function show(io::IO, mime::MIME{Symbol("text/plain")}, C::CholeskyPivoted)
    summary(io, C); println(io)
    println(io, "$(C.uplo) factor with rank $(rank(C)):")
    show(io, mime, C.uplo == 'U' ? C.U : C.L)
    println(io, "\npermutation:")
    show(io, mime, C.p)
end

ldiv!(C::Cholesky{T,<:StridedMatrix}, B::StridedVecOrMat{T}) where {T<:BlasFloat} =
    LAPACK.potrs!(C.uplo, C.factors, B)

function ldiv!(C::Cholesky, B::AbstractVecOrMat)
    if C.uplo == 'L'
        return ldiv!(adjoint(LowerTriangular(C.factors)), ldiv!(LowerTriangular(C.factors), B))
    else
        return ldiv!(UpperTriangular(C.factors), ldiv!(adjoint(UpperTriangular(C.factors)), B))
    end
end

function ldiv!(C::CholeskyPivoted{T,<:StridedMatrix}, B::StridedVector{T}) where T<:BlasFloat
    invpermute!(LAPACK.potrs!(C.uplo, C.factors, permute!(B, C.piv)), C.piv)
end
function ldiv!(C::CholeskyPivoted{T,<:StridedMatrix}, B::StridedMatrix{T}) where T<:BlasFloat
    n = size(C, 1)
    for i=1:size(B, 2)
        permute!(view(B, 1:n, i), C.piv)
    end
    LAPACK.potrs!(C.uplo, C.factors, B)
    for i=1:size(B, 2)
        invpermute!(view(B, 1:n, i), C.piv)
    end
    B
end

function ldiv!(C::CholeskyPivoted, B::AbstractVector)
    if C.uplo == 'L'
        ldiv!(adjoint(LowerTriangular(C.factors)),
            ldiv!(LowerTriangular(C.factors), permute!(B, C.piv)))
    else
        ldiv!(UpperTriangular(C.factors),
            ldiv!(adjoint(UpperTriangular(C.factors)), permute!(B, C.piv)))
    end
    invpermute!(B, C.piv)
end

function ldiv!(C::CholeskyPivoted, B::AbstractMatrix)
    n = size(C, 1)
    for i in 1:size(B, 2)
        permute!(view(B, 1:n, i), C.piv)
    end
    if C.uplo == 'L'
        ldiv!(adjoint(LowerTriangular(C.factors)),
            ldiv!(LowerTriangular(C.factors), B))
    else
        ldiv!(UpperTriangular(C.factors),
            ldiv!(adjoint(UpperTriangular(C.factors)), B))
    end
    for i in 1:size(B, 2)
        invpermute!(view(B, 1:n, i), C.piv)
    end
    B
end

function rdiv!(B::AbstractMatrix, C::Cholesky)
    if C.uplo == 'L'
        return rdiv!(rdiv!(B, adjoint(LowerTriangular(C.factors))), LowerTriangular(C.factors))
    else
        return rdiv!(rdiv!(B, UpperTriangular(C.factors)), adjoint(UpperTriangular(C.factors)))
    end
end

function rdiv!(B::AbstractMatrix, C::CholeskyPivoted)
    n = size(C, 2)
    for i in 1:size(B, 1)
        permute!(view(B, i, 1:n), C.piv)
    end
    if C.uplo == 'L'
        rdiv!(rdiv!(B, adjoint(LowerTriangular(C.factors))),
            LowerTriangular(C.factors))
    else
        rdiv!(rdiv!(B, UpperTriangular(C.factors)),
            adjoint(UpperTriangular(C.factors)))
    end
    for i in 1:size(B, 1)
        invpermute!(view(B, i, 1:n), C.piv)
    end
    B
end

isposdef(C::Union{Cholesky,CholeskyPivoted}) = C.info == 0

function det(C::Cholesky)
    dd = one(real(eltype(C)))
    @inbounds for i in 1:size(C.factors,1)
        dd *= real(C.factors[i,i])^2
    end
    return dd
end

function logdet(C::Cholesky)
    dd = zero(real(eltype(C)))
    @inbounds for i in 1:size(C.factors,1)
        dd += log(real(C.factors[i,i]))
    end
    dd + dd # instead of 2.0dd which can change the type
end

function det(C::CholeskyPivoted)
    if C.rank < size(C.factors, 1)
        return zero(real(eltype(C)))
    else
        dd = one(real(eltype(C)))
        for i in 1:size(C.factors,1)
            dd *= real(C.factors[i,i])^2
        end
        return dd
    end
end

function logdet(C::CholeskyPivoted)
    if C.rank < size(C.factors, 1)
        return real(eltype(C))(-Inf)
    else
        dd = zero(real(eltype(C)))
        for i in 1:size(C.factors,1)
            dd += log(real(C.factors[i,i]))
        end
        return dd + dd # instead of 2.0dd which can change the type
    end
end

logabsdet(C::Union{Cholesky, CholeskyPivoted}) = logdet(C), one(eltype(C)) # since C is p.s.d.

inv!(C::Cholesky{<:BlasFloat,<:StridedMatrix}) =
    copytri!(LAPACK.potri!(C.uplo, C.factors), C.uplo, true)

inv(C::Cholesky{<:BlasFloat,<:StridedMatrix}) = inv!(copy(C))

function inv(C::CholeskyPivoted{<:BlasFloat,<:StridedMatrix})
    ipiv = invperm(C.piv)
    copytri!(LAPACK.potri!(C.uplo, copy(C.factors)), C.uplo, true)[ipiv, ipiv]
end

function chkfullrank(C::CholeskyPivoted)
    if C.rank < size(C.factors, 1)
        throw(RankDeficientException(C.rank))
    end
end

rank(C::CholeskyPivoted) = C.rank

"""
    lowrankupdate!(C::Cholesky, v::AbstractVector) -> CC::Cholesky

Update a Cholesky factorization `C` with the vector `v`. If `A = C.U'C.U` then
`CC = cholesky(C.U'C.U + v*v')` but the computation of `CC` only uses `O(n^2)`
operations. The input factorization `C` is updated in place such that on exit `C == CC`.
The vector `v` is destroyed during the computation.
"""
function lowrankupdate!(C::Cholesky, v::AbstractVector)
    A = C.factors
    n = length(v)
    if size(C, 1) != n
        throw(DimensionMismatch("updating vector must fit size of factorization"))
    end
    if C.uplo == 'U'
        conj!(v)
    end

    for i = 1:n

        # Compute Givens rotation
        c, s, r = givensAlgorithm(A[i,i], v[i])

        # Store new diagonal element
        A[i,i] = r

        # Update remaining elements in row/column
        if C.uplo == 'U'
            for j = i + 1:n
                Aij = A[i,j]
                vj  = v[j]
                A[i,j]  =   c*Aij + s*vj
                v[j]    = -s'*Aij + c*vj
            end
        else
            for j = i + 1:n
                Aji = A[j,i]
                vj  = v[j]
                A[j,i]  =   c*Aji + s*vj
                v[j]    = -s'*Aji + c*vj
            end
        end
    end
    return C
end

"""
    lowrankdowndate!(C::Cholesky, v::AbstractVector) -> CC::Cholesky

Downdate a Cholesky factorization `C` with the vector `v`. If `A = C.U'C.U` then
`CC = cholesky(C.U'C.U - v*v')` but the computation of `CC` only uses `O(n^2)`
operations. The input factorization `C` is updated in place such that on exit `C == CC`.
The vector `v` is destroyed during the computation.
"""
function lowrankdowndate!(C::Cholesky, v::AbstractVector)
    A = C.factors
    n = length(v)
    if size(C, 1) != n
        throw(DimensionMismatch("updating vector must fit size of factorization"))
    end
    if C.uplo == 'U'
        conj!(v)
    end

    for i = 1:n

        Aii = A[i,i]

        # Compute Givens rotation
        s = conj(v[i]/Aii)
        s2 = abs2(s)
        if s2 > 1
            throw(PosDefException(i))
        end
        c = sqrt(1 - abs2(s))

        # Store new diagonal element
        A[i,i] = c*Aii

        # Update remaining elements in row/column
        if C.uplo == 'U'
            for j = i + 1:n
                vj = v[j]
                Aij = (A[i,j] - s*vj)/c
                A[i,j] = Aij
                v[j] = -s'*Aij + c*vj
            end
        else
            for j = i + 1:n
                vj = v[j]
                Aji = (A[j,i] - s*vj)/c
                A[j,i] = Aji
                v[j] = -s'*Aji + c*vj
            end
        end
    end
    return C
end

"""
    lowrankupdate(C::Cholesky, v::AbstractVector) -> CC::Cholesky

Update a Cholesky factorization `C` with the vector `v`. If `A = C.U'C.U`
then `CC = cholesky(C.U'C.U + v*v')` but the computation of `CC` only uses
`O(n^2)` operations.
"""
lowrankupdate(C::Cholesky, v::AbstractVector) = lowrankupdate!(copy(C), copy(v))

"""
    lowrankdowndate(C::Cholesky, v::AbstractVector) -> CC::Cholesky

Downdate a Cholesky factorization `C` with the vector `v`. If `A = C.U'C.U`
then `CC = cholesky(C.U'C.U - v*v')` but the computation of `CC` only uses
`O(n^2)` operations.
"""
lowrankdowndate(C::Cholesky, v::AbstractVector) = lowrankdowndate!(copy(C), copy(v))

function diag(C::Cholesky{T}, k::Int = 0) where {T}
    N = size(C, 1)
    absk = abs(k)
    iabsk = N - absk
    z = Vector{T}(undef, iabsk)
    UL = C.factors
    if C.uplo == 'U'
        for i in 1:iabsk
            z[i] = zero(T)
            for j in 1:min(i, i+absk)
                z[i] += UL[j, i]'UL[j, i+absk]
            end
        end
    else
        for i in 1:iabsk
            z[i] = zero(T)
            for j in 1:min(i, i+absk)
                z[i] += UL[i, j]*UL[i+absk, j]'
            end
        end
    end
    if !(T <: Real) && k < 0
        z .= adjoint.(z)
    end
    return z
end
