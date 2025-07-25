# This file is a part of Julia. License is MIT: https://julialang.org/license

module TestGeneric

isdefined(Main, :pruned_old_LA) || @eval Main include("prune_old_LA.jl")

using Test, LinearAlgebra, Random
using Test: GenericArray
using LinearAlgebra: isbanded

const TESTDIR = joinpath(dirname(pathof(LinearAlgebra)), "..", "test")
const TESTHELPERS = joinpath(TESTDIR, "testhelpers", "testhelpers.jl")
isdefined(Main, :LinearAlgebraTestHelpers) || Base.include(Main, TESTHELPERS)

using Main.LinearAlgebraTestHelpers.Quaternions
using Main.LinearAlgebraTestHelpers.OffsetArrays
using Main.LinearAlgebraTestHelpers.DualNumbers
using Main.LinearAlgebraTestHelpers.FillArrays
using Main.LinearAlgebraTestHelpers.SizedArrays

Random.seed!(123)

n = 5 # should be odd

@testset for elty in (Int, Rational{BigInt}, Float32, Float64, BigFloat, ComplexF32, ComplexF64, Complex{BigFloat})
    # In the long run, these tests should step through Strang's
    #  axiomatic definition of determinants.
    # If all axioms are satisfied and all the composition rules work,
    #  all determinants will be correct except for floating point errors.
    if elty != Rational{BigInt}
        @testset "det(A::Matrix)" begin
            # The determinant of the identity matrix should always be 1.
            for i = 1:10
                A = Matrix{elty}(I, i, i)
                @test det(A) ≈ one(elty)
            end

            # The determinant of a Householder reflection matrix should always be -1.
            for i = 1:10
                A = Matrix{elty}(I, 10, 10)
                A[i, i] = -one(elty)
                @test det(A) ≈ -one(elty)
            end

            # The determinant of a rotation matrix should always be 1.
            if elty != Int
                for theta = convert(Vector{elty}, pi ./ [1:4;])
                    R = [cos(theta) -sin(theta);
                         sin(theta) cos(theta)]
                    @test convert(elty, det(R)) ≈ one(elty)
                end
            end
        end
    end
    if elty <: Int
        A = rand(-n:n, n, n) + 10I
    elseif elty <: Rational
        A = Rational{BigInt}[rand(-n:n)/rand(1:n) for i = 1:n, j = 1:n] + 10I
    elseif elty <: Real
        A = convert(Matrix{elty}, randn(n,n)) + 10I
    else
        A = convert(Matrix{elty}, complex.(randn(n,n), randn(n,n)))
    end

    @testset "logdet and logabsdet" begin
        @test logdet(A[1,1]) == log(det(A[1,1]))
        @test logdet(A) ≈ log(det(A))
        @test logabsdet(A)[1] ≈ log(abs(det(A)))
        @test logabsdet(Matrix{elty}(-I, n, n))[2] == -1
        infinity = convert(float(elty), Inf)
        @test logabsdet(zeros(elty, n, n)) == (-infinity, zero(elty))
        if elty <: Real
            @test logabsdet(A)[2] == sign(det(A))
            @test_throws DomainError logdet(Matrix{elty}(-I, n, n))
        else
            @test logabsdet(A)[2] ≈ sign(det(A))
        end
        # logabsdet for Number"
        x = A[1, 1] # getting a number of type elty
        X = fill(x, 1, 1)
        @test logabsdet(x)[1] ≈ logabsdet(X)[1]
        @test logabsdet(x)[2] ≈ logabsdet(X)[2]
        # Diagonal, upper, and lower triangular matrices
        chksign(s1, s2) = if elty <: Real s1 == s2 else s1 ≈ s2 end
        D = Matrix(Diagonal(A))
        v, s = logabsdet(D)
        @test v ≈ log(abs(det(D))) && chksign(s, sign(det(D)))
        R = triu(A)
        v, s = logabsdet(R)
        @test v ≈ log(abs(det(R))) && chksign(s, sign(det(R)))
        L = tril(A)
        v, s = logabsdet(L)
        @test v ≈ log(abs(det(L))) && chksign(s, sign(det(L)))
    end

    @testset "det with nonstandard Number type" begin
        elty <: Real && @test det(Dual.(triu(A), zero(A))) isa Dual
    end
end

@testset "diag" begin
    A = Matrix(1.0I, 4, 4)
    @test diag(A) == fill(1, 4)
    @test diag(view(A, 1:3, 1:3)) == fill(1, 3)
    @test diag(view(A, 1:2, 1:2)) == fill(1, 2)
    @test_throws ArgumentError diag(rand(10))
end

@testset "generic axpy" begin
    x = ['a','b','c','d','e']
    y = ['a','b','c','d','e']
    α, β = 'f', 'g'
    @test_throws DimensionMismatch axpy!(α, x, ['g'])
    @test_throws DimensionMismatch axpby!(α, x, β, ['g'])
    @test_throws BoundsError axpy!(α, x, Vector(-1:5), y, Vector(1:7))
    @test_throws BoundsError axpy!(α, x, Vector(1:7), y, Vector(-1:5))
    @test_throws BoundsError axpy!(α, x, Vector(1:7), y, Vector(1:7))
    @test_throws DimensionMismatch axpy!(α, x, Vector(1:3), y, Vector(1:5))
end

@testset "generic syrk & herk" begin
    for T ∈ (BigFloat, Complex{BigFloat}, Quaternion{Float64})
        α = randn(T)
        a = randn(T, 3, 4)
        csmall = similar(a, 3, 3)
        csmall_fallback = similar(a, 3, 3)
        cbig = similar(a, 4, 4)
        cbig_fallback = similar(a, 4, 4)
        mul!(csmall, a, a', real(α), false)
        LinearAlgebra._generic_matmatmul!(csmall_fallback, a, a', real(α), false)
        @test ishermitian(csmall)
        @test csmall ≈ csmall_fallback
        mul!(cbig, a', a, real(α), false)
        LinearAlgebra._generic_matmatmul!(cbig_fallback, a', a, real(α), false)
        @test ishermitian(cbig)
        @test cbig ≈ cbig_fallback
        mul!(csmall, a, transpose(a), α, false)
        LinearAlgebra._generic_matmatmul!(csmall_fallback, a, transpose(a), α, false)
        @test csmall ≈ csmall_fallback
        mul!(cbig, transpose(a), a, α, false)
        LinearAlgebra._generic_matmatmul!(cbig_fallback, transpose(a), a, α, false)
        @test cbig ≈ cbig_fallback
        if T <: Union{Real, Complex}
            @test issymmetric(csmall)
            @test issymmetric(cbig)
        end
        #make sure generic herk is not called for non-real α
        mul!(csmall, a, a', α, false)
        LinearAlgebra._generic_matmatmul!(csmall_fallback, a, a', α, false)
        @test csmall ≈ csmall_fallback
        mul!(cbig, a', a, α, false)
        LinearAlgebra._generic_matmatmul!(cbig_fallback, a', a, α, false)
        @test cbig ≈ cbig_fallback
    end
end

@test !issymmetric(fill(1,5,3))
@test !ishermitian(fill(1,5,3))
@test (x = fill(1,3); cross(x,x) == zeros(3))
@test_throws DimensionMismatch cross(fill(1,3), fill(1,4))
@test_throws DimensionMismatch cross(fill(1,2), fill(1,3))

@test tr(Bidiagonal(fill(1,5),fill(0,4),:U)) == 5


@testset "array and subarray" begin
    for aa in (reshape([1.:6;], (2,3)), fill(float.(rand(Int8,2,2)), 2,3))
        for a in (aa, view(aa, 1:2, 1:2))
            am, an = size(a)
            @testset "Scaling with rmul! and lmul" begin
                @test rmul!(copy(a), 5.) == a*5
                @test lmul!(5., copy(a)) == a*5
                b = randn(2048)
                subB = view(b, :, :)
                @test rmul!(copy(b), 5.) == b*5
                @test rmul!(copy(subB), 5.) == subB*5
                @test lmul!(Diagonal([1.; 2.]), copy(a)) == a.*[1; 2]
                @test lmul!(Diagonal([1; 2]), copy(a)) == a.*[1; 2]
                @test rmul!(copy(a), Diagonal(1.:an)) == a.*Vector(1:an)'
                @test rmul!(copy(a), Diagonal(1:an)) == a.*Vector(1:an)'
                @test_throws DimensionMismatch lmul!(Diagonal(Vector{Float64}(undef,am+1)), a)
                @test_throws DimensionMismatch rmul!(a, Diagonal(Vector{Float64}(undef,an+1)))
            end

            @testset "Scaling with rdiv! and ldiv!" begin
                @test rdiv!(copy(a), 5.) == a/5
                @test ldiv!(5., copy(a)) == a/5
                @test ldiv!(zero(a), 5., copy(a)) == a/5
            end

            @testset "Scaling with 3-argument mul!" begin
                @test mul!(similar(a), 5., a) == a*5
                @test mul!(similar(a), a, 5.) == a*5
                @test mul!(similar(a), Diagonal([1.; 2.]), a) == a.*[1; 2]
                @test mul!(similar(a), Diagonal([1; 2]), a)   == a.*[1; 2]
                @test_throws DimensionMismatch mul!(similar(a), Diagonal(Vector{Float64}(undef, am+1)), a)
                @test_throws DimensionMismatch mul!(Matrix{Float64}(undef, 3, 2), a, Diagonal(Vector{Float64}(undef, an+1)))
                @test_throws DimensionMismatch mul!(similar(a), a, Diagonal(Vector{Float64}(undef, an+1)))
                @test mul!(similar(a), a, Diagonal(1.:an)) == a.*Vector(1:an)'
                @test mul!(similar(a), a, Diagonal(1:an))  == a.*Vector(1:an)'

                @testset "different axes" begin
                    O = OffsetArray(similar(a), ntuple(_->2, ndims(a)))
                    @test mul!(O, a, 2) == OffsetArray(2a, axes(O))
                    @test mul!(O, 2, a) == OffsetArray(2a, axes(O))
                end
            end

            @testset "Scaling with 5-argument mul!" begin
                @test mul!(copy(a), 5., a, 10, 100) == a*150
                @test mul!(copy(a), a, 5., 10, 100) == a*150
                @test mul!(vec(copy(a)), 5., a, 10, 100) == vec(a*150)
                @test mul!(vec(copy(a)), a, 5., 10, 100) == vec(a*150)
                @test_throws DimensionMismatch mul!([vec(copy(a)); 0], 5., a, 10, 100)
                @test_throws DimensionMismatch mul!([vec(copy(a)); 0], a, 5., 10, 100)
                @test mul!(copy(a), Diagonal([1.; 2.]), a, 10, 100) == 10a.*[1; 2] .+ 100a
                @test mul!(copy(a), Diagonal([1; 2]), a, 10, 100)   == 10a.*[1; 2] .+ 100a
                @test mul!(copy(a), a, Diagonal(1.:an), 10, 100) == 10a.*Vector(1:an)' .+ 100a
                @test mul!(copy(a), a, Diagonal(1:an), 10, 100)  == 10a.*Vector(1:an)' .+ 100a

                @testset "different axes" begin
                    if eltype(a) <: Number
                        O = OffsetArray(ones(size(a)), ntuple(_->2, ndims(a)))
                        @test mul!(copy(O), a, 2, 3, 4) == OffsetArray(6a .+ 4, axes(O))
                        @test mul!(copy(O), 2, a, 3, 4) == OffsetArray(6a .+ 4, axes(O))
                        @test mul!(copy(O), a, 2, 3, 0) == OffsetArray(6a, axes(O))
                        @test mul!(copy(O), 2, a, 3, 0) == OffsetArray(6a, axes(O))
                        @test mul!(copy(O), a, 2, 1, 4) == OffsetArray(2a .+ 4, axes(O))
                        @test mul!(copy(O), 2, a, 1, 4) == OffsetArray(2a .+ 4, axes(O))
                        @test mul!(copy(O), a, 2, 1, 0) == OffsetArray(2a, axes(O))
                        @test mul!(copy(O), 2, a, 1, 0) == OffsetArray(2a, axes(O))
                    end
                end
            end
        end
    end
end

@testset "scale real matrix by complex type" begin
    @test_throws InexactError rmul!([1.0], 2.0im)
    @test isequal([1.0] * 2.0im,             ComplexF64[2.0im])
    @test isequal(2.0im * [1.0],             ComplexF64[2.0im])
    @test isequal(Float32[1.0] * 2.0f0im,    ComplexF32[2.0im])
    @test isequal(Float32[1.0] * 2.0im,      ComplexF64[2.0im])
    @test isequal(Float64[1.0] * 2.0f0im,    ComplexF64[2.0im])
    @test isequal(Float32[1.0] * big(2.0)im, Complex{BigFloat}[2.0im])
    @test isequal(Float64[1.0] * big(2.0)im, Complex{BigFloat}[2.0im])
    @test isequal(BigFloat[1.0] * 2.0im,     Complex{BigFloat}[2.0im])
    @test isequal(BigFloat[1.0] * 2.0f0im,   Complex{BigFloat}[2.0im])
end
@testset "* and mul! for non-commutative scaling" begin
    q = Quaternion(0.44567, 0.755871, 0.882548, 0.423612)
    qmat = [Quaternion(0.015007, 0.355067, 0.418645, 0.318373)]
    @test lmul!(q, copy(qmat)) != rmul!(copy(qmat), q)
    @test q*qmat ≉ qmat*q
    @test conj(q*qmat) ≈ conj(qmat)*conj(q)
    @test q * (q \ qmat) ≈ qmat ≈ (qmat / q) * q
    @test q\qmat ≉ qmat/q
    alpha = Quaternion(rand(4)...)
    beta = Quaternion(0, 0, 0, 0)
    @test mul!(copy(qmat), qmat, q, alpha, beta) ≈ qmat * q * alpha
    @test mul!(copy(qmat), q, qmat, alpha, beta) ≈ q * qmat * alpha
end
@testset "ops on Numbers" begin
    @testset for elty in [Float32,Float64,ComplexF32,ComplexF64]
        a = rand(elty)
        @test tr(a)            == a
        @test rank(zero(elty)) == 0
        @test rank(one(elty))  == 1
        @test !isfinite(cond(zero(elty)))
        @test cond(a)          == one(elty)
        @test cond(a,1)        == one(elty)
        @test issymmetric(a)
        @test ishermitian(one(elty))
        @test det(a) == a
        @test norm(a) == abs(a)
        @test norm(a, 0) == 1
        @test norm(0, 0) == 0
    end

    @test !issymmetric(NaN16)
    @test !issymmetric(NaN32)
    @test !issymmetric(NaN)
    @test norm(NaN)    === NaN
    @test norm(NaN, 0) === NaN
end

@test rank(zeros(4)) == 0
@test rank(1:10) == 1
@test rank(fill(0, 0, 0)) == 0
@test rank([1.0 0.0; 0.0 0.9],0.95) == 1
@test rank([1.0 0.0; 0.0 0.9],rtol=0.95) == 1
@test rank([1.0 0.0; 0.0 0.9],atol=0.95) == 1
@test rank([1.0 0.0; 0.0 0.9],atol=0.95,rtol=0.95)==1
@test qr(big.([0 1; 0 0])).R == [0 1; 0 0]

@test norm([2.4e-322, 4.4e-323]) ≈ 2.47e-322
@test norm([2.4e-322, 4.4e-323], 3) ≈ 2.4e-322
@test_throws ArgumentError opnorm(Matrix{Float64}(undef,5,5),5)

# operator norm for zero-dimensional domain is zero (see #40370)
@testset "opnorm" begin
    for m in (0, 1, 2)
        @test @inferred(opnorm(fill(1,0,m))) == 0.0
        @test @inferred(opnorm(fill(1,m,0))) == 0.0
    end
    for m in (1, 2)
        @test @inferred(opnorm(fill(1im,1,m))) ≈ sqrt(m)
        @test @inferred(opnorm(fill(1im,m,1))) ≈ sqrt(m)
    end
    @test @inferred(opnorm(fill(1,2,2))) ≈ 2
end

@testset "generic norm for arrays of arrays" begin
    x = Vector{Int}[[1,2], [3,4]]
    @test @inferred(norm(x)) ≈ sqrt(30)
    @test norm(x, 0) == length(x)
    @test norm(x, 1) ≈ 5+sqrt(5)
    @test norm(x, 3) ≈ cbrt(5^3  +sqrt(5)^3)
end

@testset "norm of transpose/adjoint equals norm of parent #32739" begin
    for t in (transpose, adjoint), elt in (Float32, Float64, BigFloat, ComplexF32, ComplexF64, Complex{BigFloat})
        # Vector/matrix of scalars
        for sz in ((2,), (2, 3))
            A = rand(elt, sz...)
            Aᵀ = t(A)
            @test norm(Aᵀ) ≈ norm(Matrix(Aᵀ))
        end

        # Vector/matrix of vectors/matrices
        for sz_outer in ((2,), (2, 3)), sz_inner in ((3,), (1, 2))
            A = [rand(elt, sz_inner...) for _ in CartesianIndices(sz_outer)]
            Aᵀ = t(A)
            @test norm(Aᵀ) ≈ norm(Matrix(Matrix.(Aᵀ)))
        end
    end
end

@testset "rotate! and reflect!" begin
    x = rand(ComplexF64, 10)
    y = rand(ComplexF64, 10)
    c = rand(Float64)
    s = rand(ComplexF64)

    x2 = copy(x)
    y2 = copy(y)
    rotate!(x, y, c, s)
    @test x ≈ c*x2 + s*y2
    @test y ≈ -conj(s)*x2 + c*y2
    @test_throws DimensionMismatch rotate!([x; x], y, c, s)

    x3 = copy(x)
    y3 = copy(y)
    reflect!(x, y, c, s)
    @test x ≈ c*x3 + s*y3
    @test y ≈ conj(s)*x3 - c*y3
    @test_throws DimensionMismatch reflect!([x; x], y, c, s)
end

@testset "LinearAlgebra.reflectorApply!" begin
    for T in (Float64, ComplexF64)
        x = rand(T, 6)
        τ = rand(T)
        A = rand(T, 6)
        B = LinearAlgebra.reflectorApply!(x, τ, copy(A))
        C = LinearAlgebra.reflectorApply!(x, τ, reshape(copy(A), (length(A), 1)))
        @test B[1] ≈ C[1] ≈ A[1] - conj(τ)*(A[1] + dot(x[2:end], A[2:end]))
        @test B[2:end] ≈ C[2:end] ≈ A[2:end] - conj(τ)*(A[1] + dot(x[2:end], A[2:end]))*x[2:end]
    end
end

@testset "axp(b)y! for element type without commutative multiplication" begin
    α = [1 2; 3 4]
    β = [5 6; 7 8]
    x = fill([ 9 10; 11 12], 3)
    y = fill([13 14; 15 16], 3)
    axpy = axpy!(α, x, deepcopy(y))
    axpby = axpby!(α, x, β, deepcopy(y))
    @test axpy == x .* [α] .+ y
    @test axpy != [α] .* x .+ y
    @test axpby == x .* [α] .+ y .* [β]
    @test axpby != [α] .* x .+ [β] .* y
    axpy = axpy!(zero(α), x, deepcopy(y))
    axpby = axpby!(zero(α), x, one(β), deepcopy(y))
    @test axpy == y
    @test axpy == y
    @test axpby == y
    @test axpby == y
end

@testset "axpy! for x and y of different dimensions" begin
    α = 5
    x = 2:5
    y = fill(1, 2, 4)
    rx = [1 4]
    ry = [2 8]
    @test axpy!(α, x, rx, y, ry) == [1 1 1 1; 11 1 1 26]
end

@testset "axp(b)y! for non strides input" begin
    a = rand(5, 5)
    @test axpby!(1, Hermitian(a), 1, zeros(size(a))) == Hermitian(a)
    @test axpby!(1, 1.:5, 1, zeros(5)) == 1.:5
    @test axpy!(1, Hermitian(a), zeros(size(a))) == Hermitian(a)
    @test axpy!(1, 1.:5, zeros(5)) == 1.:5
end

@testset "LinearAlgebra.axp(b)y! for stride-vector like input" begin
    for T in (Float32, Float64, ComplexF32, ComplexF64)
        a = rand(T, 5, 5)
        @test axpby!(1, view(a, :, 1:5), 1, zeros(T, size(a))) == a
        @test axpy!(1, view(a, :, 1:5), zeros(T, size(a))) == a
        b = view(a, 25:-2:1)
        @test axpby!(1, b, 1, zeros(T, size(b))) == b
        @test axpy!(1, b, zeros(T, size(b))) == b
    end
end

@testset "norm and normalize!" begin
    vr = [3.0, 4.0]
    for Tr in (Float32, Float64)
        for T in (Tr, Complex{Tr})
            v = convert(Vector{T}, vr)
            @test norm(v) == 5.0
            w = normalize(v)
            @test norm(w - [0.6, 0.8], Inf) < eps(Tr)
            @test norm(w) == 1.0
            @test norm(normalize!(copy(v)) - w, Inf) < eps(Tr)
            @test isempty(normalize!(T[]))
        end
    end
end

@testset "normalize for multidimensional arrays" begin

    for arr in (
        fill(10.0, ()),  # 0 dim
        [1.0],           # 1 dim
        [1.0 2.0 3.0; 4.0 5.0 6.0], # 2-dim
        rand(1,2,3),                # higher dims
        rand(1,2,3,4),
        Dual.(randn(2,3), randn(2,3)),
        OffsetArray([-1,0], (-2,))  # no index 1
    )
        @test normalize(arr) == normalize!(copy(arr))
        @test size(normalize(arr)) == size(arr)
        @test axes(normalize(arr)) == axes(arr)
        @test vec(normalize(arr)) == normalize(vec(arr))
    end

    @test typeof(normalize([1 2 3; 4 5 6])) == Array{Float64,2}
end

@testset "normalize for scalars" begin
    @test normalize(8.0) == 1.0
    @test normalize(-3.0) == -1.0
    @test normalize(-3.0, 1) == -1.0
    @test isnan(normalize(0.0))
end

@testset "Issue #30466" begin
    @test norm([typemin(Int), typemin(Int)], Inf) == -float(typemin(Int))
    @test norm([typemin(Int), typemin(Int)], 1) == -2float(typemin(Int))
end

@testset "potential overflow in normalize!" begin
    δ = inv(prevfloat(typemax(Float64)))
    v = [δ, -δ]

    @test norm(v) === 7.866824069956793e-309
    w = normalize(v)
    @test w ≈ [1/√2, -1/√2]
    @test norm(w) === 1.0
    @test norm(normalize!(v) - w, Inf) < eps()
end

@testset "normalize with Infs. Issue 29681." begin
    @test all(isequal.(normalize([1, -1, Inf]),
                       [0.0, -0.0, NaN]))
    @test all(isequal.(normalize([complex(1), complex(0, -1), complex(Inf, -Inf)]),
                       [0.0 + 0.0im, 0.0 - 0.0im, NaN + NaN*im]))
end

@testset "Issue 14657" begin
    @test det([true false; false true]) == det(Matrix(1I, 2, 2))
end

@test_throws ArgumentError LinearAlgebra.char_uplo(:Z)

@testset "Issue 17650" begin
    @test [0.01311489462160816, Inf] ≈ [0.013114894621608135, Inf]
end

@testset "Issue 19035" begin
    @test LinearAlgebra.promote_leaf_eltypes([1, 2, [3.0, 4.0]]) == Float64
    @test LinearAlgebra.promote_leaf_eltypes([[1,2, [3,4]], 5.0, [6im, [7.0, 8.0]]]) == ComplexF64
    @test [1, 2, 3] ≈ [1, 2, 3]
    @test [[1, 2], [3, 4]] ≈ [[1, 2], [3, 4]]
    @test [[1, 2], [3, 4]] ≈ [[1.0-eps(), 2.0+eps()], [3.0+2eps(), 4.0-1e8eps()]]
    @test [[1, 2], [3, 4]] ≉ [[1.0-eps(), 2.0+eps()], [3.0+2eps(), 4.0-1e9eps()]]
    @test [[1,2, [3,4]], 5.0, [6im, [7.0, 8.0]]] ≈ [[1,2, [3,4]], 5.0, [6im, [7.0, 8.0]]]
end

@testset "Issue 40128" begin
    @test det(BigInt[9 1 8 0; 0 0 8 7; 7 6 8 3; 2 9 7 7])::BigInt == -1
    @test det(BigInt[1 big(2)^65+1; 3 4])::BigInt == (4 - 3*(big(2)^65+1))
end

# Minimal modulo number type - but not subtyping Number
struct ModInt{n}
    k
    ModInt{n}(k) where {n} = new(mod(k,n))
    ModInt{n}(k::ModInt{n}) where {n} = k
end
Base.:+(a::ModInt{n}, b::ModInt{n}) where {n} = ModInt{n}(a.k + b.k)
Base.:-(a::ModInt{n}, b::ModInt{n}) where {n} = ModInt{n}(a.k - b.k)
Base.:*(a::ModInt{n}, b::ModInt{n}) where {n} = ModInt{n}(a.k * b.k)
Base.:-(a::ModInt{n}) where {n} = ModInt{n}(-a.k)
Base.inv(a::ModInt{n}) where {n} = ModInt{n}(invmod(a.k, n))
Base.:/(a::ModInt{n}, b::ModInt{n}) where {n} = a*inv(b)

Base.isfinite(a::ModInt{n}) where {n} = isfinite(a.k)
Base.zero(::Type{ModInt{n}}) where {n} = ModInt{n}(0)
Base.zero(::ModInt{n}) where {n} = ModInt{n}(0)
Base.one(::Type{ModInt{n}}) where {n} = ModInt{n}(1)
Base.one(::ModInt{n}) where {n} = ModInt{n}(1)
Base.conj(a::ModInt{n}) where {n} = a
LinearAlgebra.lupivottype(::Type{ModInt{n}}) where {n} = RowNonZero()
Base.adjoint(a::ModInt{n}) where {n} = ModInt{n}(conj(a))
Base.transpose(a::ModInt{n}) where {n} = a  # see Issue 20978
LinearAlgebra.Adjoint(a::ModInt{n}) where {n} = adjoint(a)
LinearAlgebra.Transpose(a::ModInt{n}) where {n} = transpose(a)

@testset "Issue 22042" begin
    A = [ModInt{2}(1) ModInt{2}(0); ModInt{2}(1) ModInt{2}(1)]
    b = [ModInt{2}(1), ModInt{2}(0)]

    @test A*(A\b) == b
    @test A*(lu(A)\b) == b
    @test A*(lu(A, NoPivot())\b) == b
    @test A*(lu(A, RowNonZero())\b) == b
    @test_throws MethodError lu(A, RowMaximum())

    # Needed for pivoting:
    Base.abs(a::ModInt{n}) where {n} = a
    Base.:<(a::ModInt{n}, b::ModInt{n}) where {n} = a.k < b.k
    @test A*(lu(A, RowMaximum())\b) == b

    A = [ModInt{2}(0) ModInt{2}(1); ModInt{2}(1) ModInt{2}(1)]
    @test A*(A\b) == b
    @test A*(lu(A)\b) == b
    @test A*(lu(A, RowMaximum())\b) == b
    @test A*(lu(A, RowNonZero())\b) == b
end

@testset "Issue 18742" begin
    @test_throws DimensionMismatch ones(4,5)/zeros(3,6)
    @test_throws DimensionMismatch ones(4,5)\zeros(3,6)
end
@testset "fallback throws properly for AbstractArrays with dimension > 2" begin
    @test_throws ErrorException adjoint(rand(2,2,2,2))
    @test_throws ErrorException transpose(rand(2,2,2,2))
end

@testset "generic functions for checking whether matrices have banded structure" begin
    pentadiag = [1 2 3; 4 5 6; 7 8 9]
    tridiag   = diagm(-1=>1:6, 1=>1:6)
    tridiagG  = GenericArray(tridiag)
    Tridiag   = Tridiagonal(tridiag)
    ubidiag   = [1 2 0; 0 5 6; 0 0 9]
    ubidiagG  = GenericArray(ubidiag)
    uBidiag   = Bidiagonal(ubidiag, :U)
    lbidiag   = [1 0 0; 4 5 0; 0 8 9]
    lbidiagG  = GenericArray(lbidiag)
    lBidiag   = Bidiagonal(lbidiag, :L)
    adiag     = [1 0 0; 0 5 0; 0 0 9]
    adiagG    = GenericArray(adiag)
    aDiag     = Diagonal(adiag)
    @testset "istriu" begin
        @test !istriu(pentadiag)
        @test istriu(pentadiag, -2)
        @test !istriu(tridiag)
        @test istriu(tridiag) == istriu(tridiagG) == istriu(Tridiag)
        @test istriu(tridiag, -1)
        @test istriu(tridiag, -1) == istriu(tridiagG, -1) == istriu(Tridiag, -1)
        @test istriu(ubidiag)
        @test istriu(ubidiag) == istriu(ubidiagG) == istriu(uBidiag)
        @test !istriu(ubidiag, 1)
        @test istriu(ubidiag, 1) == istriu(ubidiagG, 1) == istriu(uBidiag, 1)
        @test !istriu(lbidiag)
        @test istriu(lbidiag) == istriu(lbidiagG) == istriu(lBidiag)
        @test istriu(lbidiag, -1)
        @test istriu(lbidiag, -1) == istriu(lbidiagG, -1) == istriu(lBidiag, -1)
        @test istriu(adiag)
        @test istriu(adiag) == istriu(adiagG) == istriu(aDiag)
    end
    @testset "istril" begin
        @test !istril(pentadiag)
        @test istril(pentadiag, 2)
        @test !istril(tridiag)
        @test istril(tridiag) == istril(tridiagG) == istril(Tridiag)
        @test istril(tridiag, 1)
        @test istril(tridiag, 1) == istril(tridiagG, 1) == istril(Tridiag, 1)
        @test !istril(ubidiag)
        @test istril(ubidiag) == istril(ubidiagG) == istril(ubidiagG)
        @test istril(ubidiag, 1)
        @test istril(ubidiag, 1) == istril(ubidiagG, 1) == istril(uBidiag, 1)
        @test istril(lbidiag)
        @test istril(lbidiag) == istril(lbidiagG) == istril(lBidiag)
        @test !istril(lbidiag, -1)
        @test istril(lbidiag, -1) == istril(lbidiagG, -1) == istril(lBidiag, -1)
        @test istril(adiag)
        @test istril(adiag) == istril(adiagG) == istril(aDiag)
    end
    @testset "isbanded" begin
        @test isbanded(pentadiag, -2, 2)
        @test !isbanded(pentadiag, -1, 2)
        @test !isbanded(pentadiag, -2, 1)
        @test isbanded(tridiag, -1, 1)
        @test isbanded(tridiag, -1, 1) == isbanded(tridiagG, -1, 1) == isbanded(Tridiag, -1, 1)
        @test !isbanded(tridiag, 0, 1)
        @test isbanded(tridiag, 0, 1) == isbanded(tridiagG, 0, 1) == isbanded(Tridiag, 0, 1)
        @test !isbanded(tridiag, -1, 0)
        @test isbanded(tridiag, -1, 0) == isbanded(tridiagG, -1, 0) == isbanded(Tridiag, -1, 0)
        @test isbanded(ubidiag, 0, 1)
        @test isbanded(ubidiag, 0, 1) == isbanded(ubidiagG, 0, 1) == isbanded(uBidiag, 0, 1)
        @test !isbanded(ubidiag, 1, 1)
        @test isbanded(ubidiag, 1, 1) == isbanded(ubidiagG, 1, 1) == isbanded(uBidiag, 1, 1)
        @test !isbanded(ubidiag, 0, 0)
        @test isbanded(ubidiag, 0, 0) == isbanded(ubidiagG, 0, 0) == isbanded(uBidiag, 0, 0)
        @test isbanded(lbidiag, -1, 0)
        @test isbanded(lbidiag, -1, 0) == isbanded(lbidiagG, -1, 0) == isbanded(lBidiag, -1, 0)
        @test !isbanded(lbidiag, 0, 0)
        @test isbanded(lbidiag, 0, 0) == isbanded(lbidiagG, 0, 0) == isbanded(lBidiag, 0, 0)
        @test !isbanded(lbidiag, -1, -1)
        @test isbanded(lbidiag, -1, -1) == isbanded(lbidiagG, -1, -1) == isbanded(lBidiag, -1, -1)
        @test isbanded(adiag, 0, 0)
        @test isbanded(adiag, 0, 0) == isbanded(adiagG, 0, 0) == isbanded(aDiag, 0, 0)
        @test !isbanded(adiag, -1, -1)
        @test isbanded(adiag, -1, -1) == isbanded(adiagG, -1, -1) == isbanded(aDiag, -1, -1)
        @test !isbanded(adiag, 1, 1)
        @test isbanded(adiag, 1, 1) == isbanded(adiagG, 1, 1) == isbanded(aDiag, 1, 1)
    end
    @testset "isdiag" begin
        @test !isdiag(tridiag)
        @test isdiag(tridiag) == isdiag(tridiagG) == isdiag(Tridiag)
        @test !isdiag(ubidiag)
        @test isdiag(ubidiag) == isdiag(ubidiagG) == isdiag(uBidiag)
        @test !isdiag(lbidiag)
        @test isdiag(lbidiag) == isdiag(lbidiagG) == isdiag(lBidiag)
        @test isdiag(adiag)
        @test isdiag(adiag) ==isdiag(adiagG) == isdiag(aDiag)
    end
end

@testset "isbanded/istril/istriu with rectangular matrices" begin
    @testset "$(size(A))" for A in [zeros(0,4), zeros(2,5), zeros(5,2), zeros(4,0)]
        @testset for m in -(size(A,1)-1):(size(A,2)-1)
            A .= 0
            A[diagind(A, m)] .= 1
            G = GenericArray(A)
            @testset for (kl,ku) in Iterators.product(-6:6, -6:6)
                @test isbanded(A, kl, ku) == isbanded(G, kl, ku) == isempty(A) || (m in (kl:ku))
            end
            @testset for k in -6:6
                @test istriu(A,k) == istriu(G,k) == isempty(A) || (k <= m)
                @test istril(A,k) == istril(G,k) == isempty(A) || (k >= m)
            end
        end
    end

    tridiag   = diagm(-1=>1:6, 1=>1:6)
    A = [tridiag zeros(size(tridiag,1), 2)]
    G = GenericArray(A)
    @testset for (kl,ku) in Iterators.product(-10:10, -10:10)
        @test isbanded(A, kl, ku) == isbanded(G, kl, ku)
    end
    @testset for k in -10:10
        @test istriu(A,k) == istriu(G,k)
        @test istril(A,k) == istril(G,k)
    end
end

@testset "missing values" begin
    @test ismissing(norm(missing))
    x = [5, 6, missing]
    y = [missing, 5, 6]
    for p in (-Inf, -1, 1, 2, 3, Inf)
        @test ismissing(norm(x, p))
        @test ismissing(norm(y, p))
    end
    @test_broken ismissing(norm(x, 0))
end

@testset "avoid stackoverflow of norm on AbstractChar" begin
    @test_throws ArgumentError norm('a')
    @test_throws ArgumentError norm(['a', 'b'])
    @test_throws ArgumentError norm("s")
    @test_throws ArgumentError norm(["s", "t"])
end

@testset "peakflops" begin
    @test LinearAlgebra.peakflops(1024, eltype=Float32, ntrials=2) > 0
end

@testset "NaN handling: Issue 28972" begin
    @test all(isnan, rmul!([NaN], 0.0))
    @test all(isnan, rmul!(Any[NaN], 0.0))
    @test all(isnan, lmul!(0.0, [NaN]))
    @test all(isnan, lmul!(0.0, Any[NaN]))

    @test all(!isnan, rmul!([NaN], false))
    @test all(!isnan, rmul!(Any[NaN], false))
    @test all(!isnan, lmul!(false, [NaN]))
    @test all(!isnan, lmul!(false, Any[NaN]))
end

@testset "adjtrans dot" begin
    for t in (transpose, adjoint), T in (ComplexF64, Quaternion{Float64})
        x, y = t(rand(T, 10)), t(rand(T, 10))
        X, Y = copy(x), copy(y)
        @test dot(x, y) ≈ dot(X, Y)
        x, y = t([rand(T, 2, 2) for _ in 1:5]), t([rand(T, 2, 2) for _ in 1:5])
        X, Y = copy(x), copy(y)
        @test dot(x, y) ≈ dot(X, Y)
        x, y = t(rand(T, 10, 5)), t(rand(T, 10, 5))
        X, Y = copy(x), copy(y)
        @test dot(x, y) ≈ dot(X, Y)
        x = t([rand(T, 2, 2) for _ in 1:5, _ in 1:5])
        y = t([rand(T, 2, 2) for _ in 1:5, _ in 1:5])
        X, Y = copy(x), copy(y)
        @test dot(x, y) ≈ dot(X, Y)
        x, y = t([rand(T, 2, 2) for _ in 1:5]), t([rand(T, 2, 2) for _ in 1:5])
    end
end

@testset "avoid stackoverflow in dot" begin
    @test_throws "cannot evaluate dot recursively" dot('a', 'c')
    @test_throws "cannot evaluate dot recursively" dot('a', 'b':'c')
    @test_throws "x and y are of different lengths" dot(1, 1:2)
end

@testset "generalized dot #32739" begin
    for elty in (Int, Float32, Float64, BigFloat, ComplexF32, ComplexF64, Complex{BigFloat})
        n = 10
        if elty <: Int
            A = rand(-n:n, n, n)
            x = rand(-n:n, n)
            y = rand(-n:n, n)
        elseif elty <: Real
            A = convert(Matrix{elty}, randn(n,n))
            x = rand(elty, n)
            y = rand(elty, n)
        else
            A = convert(Matrix{elty}, complex.(randn(n,n), randn(n,n)))
            x = rand(elty, n)
            y = rand(elty, n)
        end
        @test dot(x, A, y) ≈ dot(A'x, y) ≈ *(x', A, y) ≈ (x'A)*y
        @test dot(x, A', y) ≈ dot(A*x, y) ≈ *(x', A', y) ≈ (x'A')*y
        elty <: Real && @test dot(x, transpose(A), y) ≈ dot(x, transpose(A)*y) ≈ *(x', transpose(A), y) ≈ (x'*transpose(A))*y
        B = reshape([A], 1, 1)
        x = [x]
        y = [y]
        @test dot(x, B, y) ≈ dot(B'x, y)
        @test dot(x, B', y) ≈ dot(B*x, y)
        elty <: Real && @test dot(x, transpose(B), y) ≈ dot(x, transpose(B)*y)
    end
end

@testset "condskeel #34512" begin
    A = rand(3, 3)
    @test condskeel(A) ≈ condskeel(A, [8,8,8])
end

@testset "copytrito!" begin
    n = 10
    @testset "square" begin
        for A in (rand(n, n), rand(Int8, n, n)), uplo in ('L', 'U')
            for AA in (A, view(A, reverse.(axes(A))...))
                C = uplo == 'L' ? tril(AA) : triu(AA)
                for B in (zeros(n, n), zeros(n+1, n+2))
                    copytrito!(B, AA, uplo)
                    @test view(B, 1:n, 1:n) == C
                end
            end
        end
    end
    @testset "wide" begin
        for A in (rand(n, 2n), rand(Int8, n, 2n))
            for AA in (A, view(A, reverse.(axes(A))...))
                C = tril(AA)
                for (M, N) in ((n, n), (n+1, n), (n, n+1), (n+1, n+1))
                    B = zeros(M, N)
                    copytrito!(B, AA, 'L')
                    @test view(B, 1:n, 1:n) == view(C, 1:n, 1:n)
                end
                @test_throws DimensionMismatch copytrito!(zeros(n-1, 2n), AA, 'L')
                C = triu(AA)
                for (M, N) in ((n, 2n), (n+1, 2n), (n, 2n+1), (n+1, 2n+1))
                    B = zeros(M, N)
                    copytrito!(B, AA, 'U')
                    @test view(B, 1:n, 1:2n) == view(C, 1:n, 1:2n)
                end
                @test_throws DimensionMismatch copytrito!(zeros(n+1, 2n-1), AA, 'U')
            end
        end
    end
    @testset "tall" begin
        for A in (rand(2n, n), rand(Int8, 2n, n))
            for AA in (A, view(A, reverse.(axes(A))...))
                C = triu(AA)
                for (M, N) in ((n, n), (n+1, n), (n, n+1), (n+1, n+1))
                    B = zeros(M, N)
                    copytrito!(B, AA, 'U')
                    @test view(B, 1:n, 1:n) == view(C, 1:n, 1:n)
                end
                @test_throws DimensionMismatch copytrito!(zeros(n-1, n+1), AA, 'U')
                C = tril(AA)
                for (M, N) in ((2n, n), (2n, n+1), (2n+1, n), (2n+1, n+1))
                    B = zeros(M, N)
                    copytrito!(B, AA, 'L')
                    @test view(B, 1:2n, 1:n) == view(C, 1:2n, 1:n)
                end
                @test_throws DimensionMismatch copytrito!(zeros(n-1, n+1), AA, 'L')
            end
        end
    end
    @testset "aliasing" begin
        M = Matrix(reshape(1:36, 6, 6))
        A = view(M, 1:5, 1:5)
        A2 = Matrix(A)
        B = view(M, 2:6, 2:6)
        copytrito!(B, A, 'U')
        @test UpperTriangular(B) == UpperTriangular(A2)
    end
end

@testset "immutable arrays" begin
    A = FillArrays.Fill(big(3), (4, 4))
    M = Array(A)
    @test triu(A) == triu(M)
    @test triu(A, -1) == triu(M, -1)
    @test tril(A) == tril(M)
    @test tril(A, 1) == tril(M, 1)
    @test det(A) == det(M)
end

@testset "tril/triu" begin
    @testset "with partly initialized matrices" begin
        function test_triu(M, k=nothing)
            M[1,1] = M[2,2] = M[1,2] = M[1,3] = M[2,3] = 3
            if isnothing(k)
                MU = triu(M)
            else
                MU = triu(M, k)
            end
            @test iszero(MU[2,1])
            @test MU[1,1] == MU[2,2] == MU[1,2] == MU[1,3] == MU[2,3] == 3
        end
        test_triu(Matrix{BigInt}(undef, 2, 3))
        test_triu(Matrix{BigInt}(undef, 2, 3), 0)
        test_triu(SizedArrays.SizedArray{(2,3)}(Matrix{BigInt}(undef, 2, 3)))
        test_triu(SizedArrays.SizedArray{(2,3)}(Matrix{BigInt}(undef, 2, 3)), 0)

        function test_tril(M, k=nothing)
            M[1,1] = M[2,2] = M[2,1] = 3
            if isnothing(k)
                ML = tril(M)
            else
                ML = tril(M, k)
            end
            @test ML[1,2] == ML[1,3] == ML[2,3] == 0
            @test ML[1,1] == ML[2,2] == ML[2,1] == 3
        end
        test_tril(Matrix{BigInt}(undef, 2, 3))
        test_tril(Matrix{BigInt}(undef, 2, 3), 0)
        test_tril(SizedArrays.SizedArray{(2,3)}(Matrix{BigInt}(undef, 2, 3)))
        test_tril(SizedArrays.SizedArray{(2,3)}(Matrix{BigInt}(undef, 2, 3)), 0)
    end

    @testset "block arrays" begin
        for nrows in 0:3, ncols in 0:3
            M = [randn(2,2) for _ in 1:nrows, _ in 1:ncols]
            Mu = triu(M)
            for col in axes(M,2)
                rowcutoff = min(col, size(M,1))
                @test @views Mu[1:rowcutoff, col] == M[1:rowcutoff, col]
                @test @views Mu[rowcutoff+1:end, col] == zero.(M[rowcutoff+1:end, col])
            end
            Ml = tril(M)
            for col in axes(M,2)
                @test @views Ml[col:end, col] == M[col:end, col]
                rowcutoff = min(col-1, size(M,1))
                @test @views Ml[1:rowcutoff, col] == zero.(M[1:rowcutoff, col])
            end
        end
    end
end

@testset "scaling mul" begin
    v = 1:4
    w = similar(v)
    @test mul!(w, 2, v) == 2v
    @test mul!(w, v, 2) == 2v
    # 5-arg equivalent to the 3-arg method, but with non-Bool alpha
    @test mul!(copy!(similar(v), v), 2, v, 1, 0) == 2v
    @test mul!(copy!(similar(v), v), v, 2, 1, 0) == 2v
    # 5-arg tests with alpha::Bool
    @test mul!(copy!(similar(v), v), 2, v, true, 1) == 3v
    @test mul!(copy!(similar(v), v), v, 2, true, 1) == 3v
    @test mul!(copy!(similar(v), v), 2, v, false, 2) == 2v
    @test mul!(copy!(similar(v), v), v, 2, false, 2) == 2v
    # 5-arg tests
    @test mul!(copy!(similar(v), v), 2, v, 1, 3) == 5v
    @test mul!(copy!(similar(v), v), v, 2, 1, 3) == 5v
    @test mul!(copy!(similar(v), v), 2, v, 2, 3) == 7v
    @test mul!(copy!(similar(v), v), v, 2, 2, 3) == 7v
    @test mul!(copy!(similar(v), v), 2, v, 2, 0) == 4v
    @test mul!(copy!(similar(v), v), v, 2, 2, 0) == 4v
end

@testset "aliasing in copytrito! for strided matrices" begin
    M = rand(4, 1)
    A = view(M, 1:3, 1:1)
    A2 = copy(A)
    B = view(M, 2:4, 1:1)
    copytrito!(B, A, 'L')
    @test B == A2
end

end # module TestGeneric
