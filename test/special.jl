# This file is a part of Julia. License is MIT: https://julialang.org/license

module TestSpecial

isdefined(Main, :pruned_old_LA) || @eval Main include("prune_old_LA.jl")

using Test, LinearAlgebra, Random
using LinearAlgebra: rmul!, BandIndex

const TESTDIR = joinpath(dirname(pathof(LinearAlgebra)), "..", "test")
const TESTHELPERS = joinpath(TESTDIR, "testhelpers", "testhelpers.jl")
isdefined(Main, :LinearAlgebraTestHelpers) || Base.include(Main, TESTHELPERS)

using Main.LinearAlgebraTestHelpers.SizedArrays

n= 10 #Size of matrix to test
Random.seed!(1)

@testset "Interconversion between special matrix types" begin
    a = [1.0:n;]
    A = Diagonal(a)
    @testset for newtype in [Diagonal, Bidiagonal, SymTridiagonal, Tridiagonal, Matrix]
       @test Matrix(convert(newtype, A)) == Matrix(A)
       @test Matrix(convert(newtype, Diagonal(GenericArray(a)))) == Matrix(A)
    end

    @testset for isupper in (true, false)
        A = Bidiagonal(a, [1.0:n-1;], ifelse(isupper, :U, :L))
        for newtype in [Bidiagonal, Tridiagonal, Matrix]
           @test Matrix(convert(newtype, A)) == Matrix(A)
           @test Matrix(newtype(A)) == Matrix(A)
        end
        @test_throws ArgumentError convert(SymTridiagonal, A)
        tritype = isupper ? UpperTriangular : LowerTriangular
        @test Matrix(tritype(A)) == Matrix(A)

        A = Bidiagonal(a, zeros(n-1), ifelse(isupper, :U, :L)) #morally Diagonal
        for newtype in [Diagonal, Bidiagonal, SymTridiagonal, Tridiagonal, Matrix]
           @test Matrix(convert(newtype, A)) == Matrix(A)
           @test Matrix(newtype(A)) == Matrix(A)
        end
        @test Matrix(tritype(A)) == Matrix(A)
    end

    A = SymTridiagonal(a, [1.0:n-1;])
    for newtype in [Tridiagonal, Matrix]
       @test Matrix(convert(newtype, A)) == Matrix(A)
    end
    for newtype in [Diagonal, Bidiagonal]
       @test_throws Union{ArgumentError,InexactError} convert(newtype,A)
    end
    A = SymTridiagonal(a, zeros(n-1))
    @test Matrix(convert(Bidiagonal,A)) == Matrix(A)

    A = Tridiagonal(zeros(n-1), [1.0:n;], zeros(n-1)) #morally Diagonal
    for newtype in [Diagonal, Bidiagonal, SymTridiagonal, Matrix]
       @test Matrix(convert(newtype, A)) == Matrix(A)
    end
    A = Tridiagonal(fill(1., n-1), [1.0:n;], fill(1., n-1)) #not morally Diagonal
    for newtype in [SymTridiagonal, Matrix]
       @test Matrix(convert(newtype, A)) == Matrix(A)
    end
    for newtype in [Diagonal, Bidiagonal]
        @test_throws Union{ArgumentError,InexactError} convert(newtype,A)
    end
    A = Tridiagonal(zeros(n-1), [1.0:n;], fill(1., n-1)) #not morally Diagonal
    @test Matrix(convert(Bidiagonal, A)) == Matrix(A)
    A = UpperTriangular(Tridiagonal(zeros(n-1), [1.0:n;], fill(1., n-1)))
    @test Matrix(convert(Bidiagonal, A)) == Matrix(A)
    A = Tridiagonal(fill(1., n-1), [1.0:n;], zeros(n-1)) #not morally Diagonal
    @test Matrix(convert(Bidiagonal, A)) == Matrix(A)
    A = LowerTriangular(Tridiagonal(fill(1., n-1), [1.0:n;], zeros(n-1)))
    @test Matrix(convert(Bidiagonal, A)) == Matrix(A)
    @test_throws ArgumentError convert(SymTridiagonal,A)

    A = LowerTriangular(Matrix(Diagonal(a))) #morally Diagonal
    for newtype in [Diagonal, Bidiagonal, SymTridiagonal, LowerTriangular, Matrix]
        @test Matrix(convert(newtype, A)) == Matrix(A)
    end
    A = UpperTriangular(Matrix(Diagonal(a))) #morally Diagonal
    for newtype in [Diagonal, Bidiagonal, SymTridiagonal, UpperTriangular, Matrix]
        @test Matrix(convert(newtype, A)) == Matrix(A)
    end
    A = UpperTriangular(triu(rand(n,n)))
    for newtype in [Diagonal, Bidiagonal, Tridiagonal, SymTridiagonal]
        @test_throws Union{ArgumentError,InexactError} convert(newtype,A)
    end


    # test operations/constructors (not conversions) permitted in the docs
    dl = [1., 1.]
    d = [-2., -2., -2.]
    T = Tridiagonal(dl, d, -dl)
    S = SymTridiagonal(d, dl)
    Bu = Bidiagonal(d, dl, :U)
    Bl = Bidiagonal(d, dl, :L)
    D = Diagonal(d)
    M = [-2. 0. 0.; 1. -2. 0.; -1. 1. -2.]
    U = UpperTriangular(M)
    L = LowerTriangular(Matrix(M'))

    for A in (T, S, Bu, Bl, D, U, L, M)
        Adense = Matrix(A)
        B = Symmetric(A)
        Bdense = Matrix(B)
        for (C,Cdense) in ((A,Adense), (B,Bdense))
            @test Diagonal(C) == Diagonal(Cdense)
            @test Bidiagonal(C, :U) == Bidiagonal(Cdense, :U)
            @test Bidiagonal(C, :L) == Bidiagonal(Cdense, :L)
            @test Tridiagonal(C) == Tridiagonal(Cdense)
            @test UpperTriangular(C) == UpperTriangular(Cdense)
            @test LowerTriangular(C) == LowerTriangular(Cdense)
        end
    end

    @testset "Matrix constructor for !isa(zero(T), T)" begin
        # the following models JuMP.jl's VariableRef and AffExpr, resp.
        struct TypeWithoutZero end
        struct TypeWithZero end
        Base.promote_rule(::Type{TypeWithoutZero}, ::Type{TypeWithZero}) = TypeWithZero
        Base.convert(::Type{TypeWithZero}, ::TypeWithoutZero) = TypeWithZero()
        Base.zero(x::Union{TypeWithoutZero, TypeWithZero}) = zero(typeof(x))
        Base.zero(::Type{<:Union{TypeWithoutZero, TypeWithZero}}) = TypeWithZero()
        LinearAlgebra.symmetric(::TypeWithoutZero, ::Symbol) = TypeWithoutZero()
        LinearAlgebra.symmetric_type(::Type{TypeWithoutZero}) = TypeWithoutZero
        Base.copy(A::TypeWithoutZero) = A
        Base.transpose(::TypeWithoutZero) = TypeWithoutZero()
        d  = fill(TypeWithoutZero(), 3)
        du = fill(TypeWithoutZero(), 2)
        dl = fill(TypeWithoutZero(), 2)
        D  = Diagonal(d)
        Bu = Bidiagonal(d, du, :U)
        Bl = Bidiagonal(d, dl, :L)
        Tri = Tridiagonal(dl, d, du)
        Sym = SymTridiagonal(d, dl)
        for M in (D, Bu, Bl, Tri, Sym)
            @test Matrix(M) == zeros(TypeWithZero, 3, 3)
        end

        mutable struct MTypeWithZero end
        Base.convert(::Type{MTypeWithZero}, ::TypeWithoutZero) = MTypeWithZero()
        Base.convert(::Type{MTypeWithZero}, ::TypeWithZero) = MTypeWithZero()
        Base.zero(x::MTypeWithZero) = zero(typeof(x))
        Base.zero(::Type{MTypeWithZero}) = MTypeWithZero()
        U = UpperTriangular(Symmetric(fill(TypeWithoutZero(), 2, 2)))
        M = Matrix{MTypeWithZero}(U)
        @test all(x -> x isa MTypeWithZero, M)
    end
end

@testset "Binary ops among special types" begin
    a=[1.0:n;]
    A=Diagonal(a)
    Spectypes = [Diagonal, Bidiagonal, Tridiagonal, Matrix]
    for (idx, type1) in enumerate(Spectypes)
        for type2 in Spectypes
           B = convert(type1,A)
           C = convert(type2,A)
           @test Matrix(B + C) ≈ Matrix(A + A)
           @test Matrix(B - C) ≈ Matrix(A - A)
       end
    end
    B = SymTridiagonal(a, fill(1., n-1))
    for Spectype in [Diagonal, Bidiagonal, Tridiagonal, Matrix]
        @test Matrix(B + convert(Spectype,A)) ≈ Matrix(B + A)
        @test Matrix(convert(Spectype,A) + B) ≈ Matrix(B + A)
        @test Matrix(B - convert(Spectype,A)) ≈ Matrix(B - A)
        @test Matrix(convert(Spectype,A) - B) ≈ Matrix(A - B)
    end

    C = rand(n,n)
    for TriType in [LinearAlgebra.UnitLowerTriangular, LinearAlgebra.UnitUpperTriangular, UpperTriangular, LowerTriangular]
        D = TriType(C)
        for Spectype in [Diagonal, Bidiagonal, Tridiagonal, Matrix]
            @test Matrix(D + convert(Spectype,A)) ≈ Matrix(D + A)
            @test Matrix(convert(Spectype,A) + D) ≈ Matrix(A + D)
            @test Matrix(D - convert(Spectype,A)) ≈ Matrix(D - A)
            @test Matrix(convert(Spectype,A) - D) ≈ Matrix(A - D)
        end
    end

    UpTri = UpperTriangular(rand(20,20))
    LoTri = LowerTriangular(rand(20,20))
    Diag = Diagonal(rand(20,20))
    Tridiag = Tridiagonal(rand(20, 20))
    UpBi = Bidiagonal(rand(20,20), :U)
    LoBi = Bidiagonal(rand(20,20), :L)
    Sym = SymTridiagonal(rand(20), rand(19))
    Dense = rand(20, 20)
    mats = Any[UpTri, LoTri, Diag, Tridiag, UpBi, LoBi, Sym, Dense]

    for op in (+,-,*)
        for A in mats
            for B in mats
                @test (op)(A, B) ≈ (op)(Matrix(A), Matrix(B)) ≈ Matrix((op)(A, B))
            end
        end
    end
end

@testset "+ and - among structured matrices with different container types" begin
    diag = 1:5
    offdiag = 1:4
    uniformscalingmats = [UniformScaling(3), UniformScaling(1.0), UniformScaling(3//5), UniformScaling(ComplexF64(1.3, 3.5))]
    mats = Any[Diagonal(diag), Bidiagonal(diag, offdiag, 'U'), Bidiagonal(diag, offdiag, 'L'), Tridiagonal(offdiag, diag, offdiag), SymTridiagonal(diag, offdiag)]
    for T in [ComplexF64, Int64, Rational{Int64}, Float64]
        push!(mats, Diagonal(Vector{T}(diag)))
        push!(mats, Bidiagonal(Vector{T}(diag), Vector{T}(offdiag), 'U'))
        push!(mats, Bidiagonal(Vector{T}(diag), Vector{T}(offdiag), 'L'))
        push!(mats, Tridiagonal(Vector{T}(offdiag), Vector{T}(diag), Vector{T}(offdiag)))
        push!(mats, SymTridiagonal(Vector{T}(diag), Vector{T}(offdiag)))
    end

    for op in (+,-,*)
        for A in mats
            for B in mats
                @test (op)(A, B) ≈ (op)(Matrix(A), Matrix(B)) ≈ Matrix((op)(A, B))
            end
        end
    end
    for op in (+,-)
        for A in mats
            for B in uniformscalingmats
                @test (op)(A, B) ≈ (op)(Matrix(A), B) ≈ Matrix((op)(A, B))
                @test (op)(B, A) ≈ (op)(B, Matrix(A)) ≈ Matrix((op)(B, A))
            end
        end
    end
    diag = [randn(ComplexF64, 2, 2) for _ in 1:3]
    odiag = [randn(ComplexF64, 2, 2) for _ in 1:2]
    for A in (Diagonal(diag),
                Bidiagonal(diag, odiag, :U),
                Bidiagonal(diag, odiag, :L),
                Tridiagonal(odiag, diag, odiag),
                SymTridiagonal(diag, odiag)), B in uniformscalingmats
        @test (A + B)::typeof(A) == (B + A)::typeof(A)
        @test (A - B)::typeof(A) == ((A + (-B))::typeof(A))
        @test (B - A)::typeof(A) == ((B + (-A))::typeof(A))
    end
end


@testset "Triangular Types and QR" begin
    for typ in (UpperTriangular, LowerTriangular, UnitUpperTriangular, UnitLowerTriangular)
        a = rand(n,n)
        atri = typ(a)
        matri = Matrix(atri)
        b = rand(n,n)
        for pivot in (ColumnNorm(), NoPivot())
            qrb = qr(b, pivot)
            @test atri * qrb.Q ≈ matri * qrb.Q
            @test atri * qrb.Q' ≈ matri * qrb.Q'
            @test qrb.Q * atri ≈ qrb.Q * matri
            @test qrb.Q' * atri ≈ qrb.Q' * matri
        end
    end
end

@testset "Multiplication of Qs" begin
    for pivot in (ColumnNorm(), NoPivot()), A in (rand(5, 3), rand(5, 5), rand(3, 5))
        Q = qr(A, pivot).Q
        m = size(A, 1)
        C = Matrix{Float64}(undef, (m, m))
        @test Q*Q ≈ (Q*I) * (Q*I) ≈ mul!(C, Q, Q)
        @test size(Q*Q) == (m, m)
        @test Q'Q ≈ (Q'*I) * (Q*I) ≈ mul!(C, Q', Q)
        @test size(Q'Q) == (m, m)
        @test Q*Q' ≈ (Q*I) * (Q'*I) ≈ mul!(C, Q, Q')
        @test size(Q*Q') == (m, m)
        @test Q'Q' ≈ (Q'*I) * (Q'*I) ≈ mul!(C, Q', Q')
        @test size(Q'Q') == (m, m)
    end
end

@testset "concatenations of combinations of special and other matrix types" begin
    N = 4
    # Test concatenating pairwise combinations of special matrices
    diagmat = Diagonal(1:N)
    bidiagmat = Bidiagonal(1:N, 1:(N-1), :U)
    tridiagmat = Tridiagonal(1:(N-1), 1:N, 1:(N-1))
    symtridiagmat = SymTridiagonal(1:N, 1:(N-1))
    abstractq = qr(tridiagmat).Q
    specialmats = (diagmat, bidiagmat, tridiagmat, symtridiagmat, abstractq, zeros(Int,N,N))
    for specialmata in specialmats, specialmatb in specialmats
        MA = collect(specialmata); MB = collect(specialmatb)
        @test hcat(specialmata, specialmatb) == hcat(MA, MB)
        @test vcat(specialmata, specialmatb) == vcat(MA, MB)
        @test hvcat((1,1), specialmata, specialmatb) == hvcat((1,1), MA, MB)
        @test cat(specialmata, specialmatb; dims=(1,2)) == cat(MA, MB; dims=(1,2))
    end
    # Test concatenating pairwise combinations of special matrices with dense matrices or dense vectors
    densevec = fill(1., N)
    densemat = diagm(0 => densevec)
    for specialmat in specialmats
        SM = Matrix(specialmat)
        # --> Tests applicable only to pairs of matrices
        @test vcat(specialmat, densemat) == vcat(SM, densemat)
        @test vcat(densemat, specialmat) == vcat(densemat, SM)
        # --> Tests applicable also to pairs including vectors
        for specialmat in specialmats, othermatorvec in (densemat, densevec)
            SM = Matrix(specialmat); OM = Array(othermatorvec)
            @test hcat(specialmat, othermatorvec) == hcat(SM, OM)
            @test hcat(othermatorvec, specialmat) == hcat(OM, SM)
            @test hvcat((2,), specialmat, othermatorvec) == hvcat((2,), SM, OM)
            @test hvcat((2,), othermatorvec, specialmat) == hvcat((2,), OM, SM)
            @test cat(specialmat, othermatorvec; dims=(1,2)) == cat(SM, OM; dims=(1,2))
            @test cat(othermatorvec, specialmat; dims=(1,2)) == cat(OM, SM; dims=(1,2))
        end
    end
end

@testset "concatenations of annotated types" begin
    N = 4
    # The tested annotation types
    testfull = Base.get_bool_env("JULIA_TESTFULL", false)
    utriannotations = (UpperTriangular, UnitUpperTriangular)
    ltriannotations = (LowerTriangular, UnitLowerTriangular)
    triannotations = (utriannotations..., ltriannotations...)
    symannotations = (Symmetric, Hermitian)
    annotations = testfull ? (triannotations..., symannotations...) : (LowerTriangular, Symmetric)
    # Concatenations involving these types, un/annotated
    diagmat = Diagonal(1:N)
    bidiagmat = Bidiagonal(1:N, 1:(N-1), :U)
    tridiagmat = Tridiagonal(1:(N-1), 1:N, 1:(N-1))
    symtridiagmat = SymTridiagonal(1:N, 1:(N-1))
    specialconcatmats = testfull ? (diagmat, bidiagmat, tridiagmat, symtridiagmat) : (diagmat,)
    # Concatenations involving strictly these types, un/annotated
    densevec = fill(1., N)
    densemat = fill(1., N, N)
    # Annotated collections
    annodmats = [annot(densemat) for annot in annotations]
    annospcmats = [annot(spcmat) for annot in annotations, spcmat in specialconcatmats]
    # Test concatenations of pairwise combinations of annotated special matrices
    for annospcmata in annospcmats, annospcmatb in annospcmats
        AM = Array(annospcmata); BM = Array(annospcmatb)
        @test vcat(annospcmata, annospcmatb) == vcat(AM, BM)
        @test hcat(annospcmata, annospcmatb) == hcat(AM, BM)
        @test hvcat((2,), annospcmata, annospcmatb) == hvcat((2,), AM, BM)
        @test cat(annospcmata, annospcmatb; dims=(1,2)) == cat(AM, BM; dims=(1,2))
    end
    # Test concatenations of pairwise combinations of annotated special matrices and other matrix/vector types
    for annospcmat in annospcmats
        AM = Array(annospcmat)
        # --> Tests applicable to pairs including only matrices
        for othermat in (densemat, annodmats..., specialconcatmats...)
            OM = Array(othermat)
            @test vcat(annospcmat, othermat) == vcat(AM, OM)
            @test vcat(othermat, annospcmat) == vcat(OM, AM)
        end
        # --> Tests applicable to pairs including other vectors or matrices
        for other in (densevec, densemat, annodmats..., specialconcatmats...)
            OM = Array(other)
            @test hcat(annospcmat, other) == hcat(AM, OM)
            @test hcat(other, annospcmat) == hcat(OM, AM)
            @test hvcat((2,), annospcmat, other) == hvcat((2,), AM, OM)
            @test hvcat((2,), other, annospcmat) == hvcat((2,), OM, AM)
            @test cat(annospcmat, other; dims=(1,2)) == cat(AM, OM; dims=(1,2))
            @test cat(other, annospcmat; dims=(1,2)) == cat(OM, AM; dims=(1,2))
        end
    end
    # Test concatenations strictly involving un/annotated dense matrices/vectors
    for densemata in (densemat, annodmats...)
        AM = Array(densemata)
        # --> Tests applicable to pairs including only matrices
        for densematb in (densemat, annodmats...)
            BM = Array(densematb)
            @test vcat(densemata, densematb) == vcat(AM, BM)
            @test vcat(densematb, densemata) == vcat(BM, AM)
        end
        # --> Tests applicable to pairs including vectors or matrices
        for otherdense in (densevec, densemat, annodmats...)
            OM = Array(otherdense)
            @test hcat(densemata, otherdense) == hcat(AM, OM)
            @test hcat(otherdense, densemata) == hcat(OM, AM)
            @test hvcat((2,), densemata, otherdense) == hvcat((2,), AM, OM)
            @test hvcat((2,), otherdense, densemata) == hvcat((2,), OM, AM)
            @test cat(densemata, otherdense; dims=(1,2)) == cat(AM, OM; dims=(1,2))
            @test cat(otherdense, densemata; dims=(1,2)) == cat(OM, AM; dims=(1,2))
        end
    end
end

@testset "zero and one for structured matrices" begin
    for elty in (Int64, Float64, ComplexF64)
        D = Diagonal(rand(elty, 10))
        Bu = Bidiagonal(rand(elty, 10), rand(elty, 9), 'U')
        Bl = Bidiagonal(rand(elty, 10), rand(elty, 9), 'L')
        T = Tridiagonal(rand(elty, 9),rand(elty, 10), rand(elty, 9))
        S = SymTridiagonal(rand(elty, 10), rand(elty, 9))
        mats = Any[D, Bu, Bl, T, S]
        for A in mats
            @test iszero(zero(A))
            @test isone(one(A))
            @test zero(A) == zero(Matrix(A))
            @test one(A) == one(Matrix(A))
        end

        @test zero(D) isa Diagonal
        @test one(D) isa Diagonal

        @test zero(Bu) isa Bidiagonal
        @test one(Bu) isa Bidiagonal
        @test zero(Bl) isa Bidiagonal
        @test one(Bl) isa Bidiagonal
        @test zero(Bu).uplo == one(Bu).uplo == Bu.uplo
        @test zero(Bl).uplo == one(Bl).uplo == Bl.uplo

        @test zero(T) isa Tridiagonal
        @test one(T) isa Tridiagonal
        @test zero(S) isa SymTridiagonal
        @test one(S) isa SymTridiagonal
    end

    # ranges
    D = Diagonal(1:10)
    Bu = Bidiagonal(1:10, 1:9, 'U')
    Bl = Bidiagonal(1:10, 1:9, 'L')
    T = Tridiagonal(1:9, 1:10, 1:9)
    S = SymTridiagonal(1:10, 1:9)
    mats = [D, Bu, Bl, T, S]
    for A in mats
        @test iszero(zero(A))
        @test isone(one(A))
        @test zero(A) == zero(Matrix(A))
        @test one(A) == one(Matrix(A))
    end

    @test zero(D) isa Diagonal
    @test one(D) isa Diagonal

    @test zero(Bu) isa Bidiagonal
    @test one(Bu) isa Bidiagonal
    @test zero(Bl) isa Bidiagonal
    @test one(Bl) isa Bidiagonal
    @test zero(Bu).uplo == one(Bu).uplo == Bu.uplo
    @test zero(Bl).uplo == one(Bl).uplo == Bl.uplo

    @test zero(T) isa Tridiagonal
    @test one(T) isa Tridiagonal
    @test zero(S) isa SymTridiagonal
    @test one(S) isa SymTridiagonal
end

@testset "== for structured matrices" begin
    diag = rand(10)
    offdiag = rand(9)
    D = Diagonal(rand(10))
    Bup = Bidiagonal(diag, offdiag, 'U')
    Blo = Bidiagonal(diag, offdiag, 'L')
    Bupd = Bidiagonal(diag, zeros(9), 'U')
    Blod = Bidiagonal(diag, zeros(9), 'L')
    T = Tridiagonal(offdiag, diag, offdiag)
    Td = Tridiagonal(zeros(9), diag, zeros(9))
    Tu = Tridiagonal(zeros(9), diag, offdiag)
    Tl = Tridiagonal(offdiag, diag, zeros(9))
    S = SymTridiagonal(diag, offdiag)
    Sd = SymTridiagonal(diag, zeros(9))

    mats = [D, Bup, Blo, Bupd, Blod, T, Td, Tu, Tl, S, Sd]

    for a in mats
        for b in mats
            @test (a == b) == (Matrix(a) == Matrix(b)) == (b == a) == (Matrix(b) == Matrix(a))
        end
    end
end

@testset "BiTriSym*Q' and Q'*BiTriSym" begin
    dl = [1, 1, 1]
    d = [1, 1, 1, 1]
    D = Diagonal(d)
    Bi = Bidiagonal(d, dl, :L)
    Tri = Tridiagonal(dl, d, dl)
    Sym = SymTridiagonal(d, dl)
    F = qr(ones(4, 1))
    A = F.Q'
    for A in (F.Q, F.Q'), B in (D, Bi, Tri, Sym)
        @test B*A ≈ Matrix(B)*A
        @test A*B ≈ A*Matrix(B)
    end
end

@testset "Ops on SymTridiagonal ev has the same length as dv" begin
    x = rand(3)
    y = rand(3)
    z = rand(2)

    S = SymTridiagonal(x, y)
    T = Tridiagonal(z, x, z)
    Bu = Bidiagonal(x, z, :U)
    Bl = Bidiagonal(x, z, :L)

    Ms = Matrix(S)
    Mt = Matrix(T)
    Mbu = Matrix(Bu)
    Mbl = Matrix(Bl)

    @test S + T ≈ Ms + Mt
    @test T + S ≈ Mt + Ms
    @test S + Bu ≈ Ms + Mbu
    @test Bu + S ≈ Mbu + Ms
    @test S + Bl ≈ Ms + Mbl
    @test Bl + S ≈ Mbl + Ms
end

@testset "Ensure Strided * (Sym)Tridiagonal is Dense" begin
    x = rand(3)
    y = rand(3)
    z = rand(2)

    l = rand(12, 12)
    # strided but not a Matrix
    v = @view l[1:4:end, 1:4:end]
    M_v = Matrix(v)
    m = rand(3, 3)

    S = SymTridiagonal(x, y)
    T = Tridiagonal(z, x, z)
    M_S = Matrix(S)
    M_T = Matrix(T)

    @test m * T ≈ m * M_T
    @test m * S ≈ m * M_S
    @test v * T ≈ M_v * T
    @test v * S ≈ M_v * S

    @test m * T isa Matrix
    @test m * S isa Matrix
    @test v * T isa Matrix
    @test v * S isa Matrix
end

@testset "copyto! between matrix types" begin
    dl, d, du = zeros(Int,4), [1:5;], zeros(Int,4)
    d_ones = ones(Int,size(du))

    @testset "from Diagonal" begin
        D = Diagonal(d)
        @testset "to Bidiagonal" begin
            BU = Bidiagonal(similar(d, BigInt), similar(du, BigInt), :U)
            BL = Bidiagonal(similar(d, BigInt), similar(dl, BigInt), :L)
            for B in (BL, BU)
                copyto!(B, D)
                @test B == D
            end

            @testset "mismatched size" begin
                for B in (BU, BL)
                    B .= 0
                    copyto!(B, Diagonal(Int[1]))
                    @test B[1,1] == 1
                    B[1,1] = 0
                    @test iszero(B)
                end
            end
        end
        @testset "to Tridiagonal" begin
            T = Tridiagonal(similar(dl, BigInt), similar(d, BigInt), similar(du, BigInt))
            copyto!(T, D)
            @test T == D

            @testset "mismatched size" begin
                T .= 0
                copyto!(T, Diagonal([1]))
                @test T[1,1] == 1
                T[1,1] = 0
                @test iszero(T)
            end
        end
        @testset "to SymTridiagonal" begin
            for du2 in (similar(du, BigInt), similar(d, BigInt))
                S = SymTridiagonal(similar(d), du2)
                copyto!(S, D)
                @test S == D
            end

            @testset "mismatched size" begin
                S = SymTridiagonal(zero(d), zero(du))
                copyto!(S, Diagonal([1]))
                @test S[1,1] == 1
                S[1,1] = 0
                @test iszero(S)
            end
        end
    end

    @testset "from Bidiagonal" begin
        BU = Bidiagonal(d, du, :U)
        BUones = Bidiagonal(d, oneunit.(du), :U)
        BL = Bidiagonal(d, dl, :L)
        BLones = Bidiagonal(d, oneunit.(dl), :L)
        @testset "to Diagonal" begin
            D = Diagonal(zero(d))
            for B in (BL, BU)
                @test copyto!(D, B) == B
                D .= 0
            end
            for B in (BLones, BUones)
                errmsg = "cannot copy a Bidiagonal with a non-zero off-diagonal band to a Diagonal"
                @test_throws errmsg copyto!(D, B)
                @test iszero(D)
            end

            @testset "mismatched size" begin
                for uplo in (:L, :U)
                    D .= 0
                    copyto!(D, Bidiagonal(Int[1], Int[], uplo))
                    @test D[1,1] == 1
                    D[1,1] = 0
                    @test iszero(D)
                end
            end
        end
        @testset "to Tridiagonal" begin
            T = Tridiagonal(similar(dl, BigInt), similar(d, BigInt), similar(du, BigInt))
            for B in (BL, BU, BLones, BUones)
                copyto!(T, B)
                @test T == B
            end

            @testset "mismatched size" begin
                T = Tridiagonal(oneunit.(dl), zero(d), oneunit.(du))
                for uplo in (:L, :U)
                    T .= 0
                    copyto!(T, Bidiagonal([1], Int[], uplo))
                    @test T[1,1] == 1
                    T[1,1] = 0
                    @test iszero(T)
                end
            end
        end
        @testset "to SymTridiagonal" begin
            for du2 in (similar(du, BigInt), similar(d, BigInt))
                S = SymTridiagonal(similar(d, BigInt), du2)
                for B in (BL, BU)
                    copyto!(S, B)
                    @test S == B
                end
                errmsg = "cannot copy a non-symmetric Bidiagonal matrix to a SymTridiagonal"
                @test_throws errmsg copyto!(S, BUones)
                @test_throws errmsg copyto!(S, BLones)
            end

            @testset "mismatched size" begin
                S = SymTridiagonal(zero(d), zero(du))
                for uplo in (:L, :U)
                    copyto!(S, Bidiagonal([1], Int[], uplo))
                    @test S[1,1] == 1
                    S[1,1] = 0
                    @test iszero(S)
                end
            end
        end
    end

    @testset "from Tridiagonal" begin
        T = Tridiagonal(dl, d, du)
        TU = Tridiagonal(dl, d, d_ones)
        TL = Tridiagonal(d_ones, d, dl)
        @testset "to Diagonal" begin
            D = Diagonal(zero(d))
            @test copyto!(D, T) == Diagonal(d)
            errmsg = "cannot copy a Tridiagonal with a non-zero off-diagonal band to a Diagonal"
            D .= 0
            @test_throws errmsg copyto!(D, TU)
            @test iszero(D)
            errmsg = "cannot copy a Tridiagonal with a non-zero off-diagonal band to a Diagonal"
            @test_throws errmsg copyto!(D, TL)
            @test iszero(D)

            @testset "mismatched size" begin
                D .= 0
                copyto!(D, Tridiagonal(Int[], Int[1], Int[]))
                @test D[1,1] == 1
                D[1,1] = 0
                @test iszero(D)
            end
        end
        @testset "to Bidiagonal" begin
            BU = Bidiagonal(zero(d), zero(du), :U)
            BL = Bidiagonal(zero(d), zero(du), :L)
            @test copyto!(BU, T) == Bidiagonal(d, du, :U)
            @test copyto!(BL, T) == Bidiagonal(d, du, :L)

            BU .= 0
            BL .= 0
            errmsg = "cannot copy a Tridiagonal with a non-zero superdiagonal to a Bidiagonal with uplo=:L"
            @test_throws errmsg copyto!(BL, TU)
            @test iszero(BL)
            @test copyto!(BU, TU) == Bidiagonal(d, d_ones, :U)

            BU .= 0
            BL .= 0
            @test copyto!(BL, TL) == Bidiagonal(d, d_ones, :L)
            errmsg = "cannot copy a Tridiagonal with a non-zero subdiagonal to a Bidiagonal with uplo=:U"
            @test_throws errmsg copyto!(BU, TL)
            @test iszero(BU)

            @testset "mismatched size" begin
                for B in (BU, BL)
                    B .= 0
                    copyto!(B, Tridiagonal(Int[], Int[1], Int[]))
                    @test B[1,1] == 1
                    B[1,1] = 0
                    @test iszero(B)
                end
            end
        end
    end

    @testset "from SymTridiagonal" begin
        S2 = SymTridiagonal(d, ones(Int,size(d)))
        for S in (SymTridiagonal(d, du), SymTridiagonal(d, zero(d)))
            @testset "to Diagonal" begin
                D = Diagonal(zero(d))
                @test copyto!(D, S) == Diagonal(d)
                D .= 0
                errmsg = "cannot copy a SymTridiagonal with a non-zero off-diagonal band to a Diagonal"
                @test_throws errmsg copyto!(D, S2)
                @test iszero(D)

                @testset "mismatched size" begin
                    D .= 0
                    copyto!(D, SymTridiagonal(Int[1], Int[]))
                    @test D[1,1] == 1
                    D[1,1] = 0
                    @test iszero(D)
                end
            end
            @testset "to Bidiagonal" begin
                BU = Bidiagonal(zero(d), zero(du), :U)
                BL = Bidiagonal(zero(d), zero(du), :L)
                @test copyto!(BU, S) == Bidiagonal(d, du, :U)
                @test copyto!(BL, S) == Bidiagonal(d, du, :L)

                BU .= 0
                BL .= 0
                errmsg = "cannot copy a SymTridiagonal with a non-zero off-diagonal band to a Bidiagonal"
                @test_throws errmsg copyto!(BU, S2)
                @test iszero(BU)
                @test_throws errmsg copyto!(BL, S2)
                @test iszero(BL)

                @testset "mismatched size" begin
                    for B in (BU, BL)
                        B .= 0
                        copyto!(B, SymTridiagonal(Int[1], Int[]))
                        @test B[1,1] == 1
                        B[1,1] = 0
                        @test iszero(B)
                    end
                end
            end
        end
    end
end

@testset "BandIndex indexing" begin
    for D in (Diagonal(1:3), Bidiagonal(1:3, 2:3, :U), Bidiagonal(1:3, 2:3, :L),
                Tridiagonal(2:3, 1:3, 1:2), SymTridiagonal(1:3, 2:3))
        M = Matrix(D)
        for band in -size(D,1)+1:size(D,1)-1
            for idx in 1:size(D,1)-abs(band)
                @test D[BandIndex(band, idx)] == M[BandIndex(band, idx)]
            end
        end
        @test_throws BoundsError D[BandIndex(size(D,1),1)]
    end
    @testset "BandIndex to CartesianIndex" begin
        b = BandIndex(1, 2)
        c = CartesianIndex(b)
        @test c == CartesianIndex(2, 3)
        @test BandIndex(c) == b
    end
end

@testset "Partly filled Hermitian and Diagonal algebra" begin
    D = Diagonal([1,2])
    for S in (Symmetric, Hermitian), uplo in (:U, :L)
        M = Matrix{BigInt}(undef, 2, 2)
        M[1,1] = M[2,2] = M[1+(uplo == :L), 1 + (uplo == :U)] = 3
        H = S(M, uplo)
        HM = Matrix(H)
        @test H + D == D + H == HM + D
        @test H - D == HM - D
        @test D - H == D - HM
    end
end

@testset "block SymTridiagonal" begin
    m = SizedArrays.SizedArray{(2,2)}(reshape([1:4;;],2,2))
    S = SymTridiagonal(fill(m,4), fill(m,3))
    SA = Array(S)
    D = Diagonal(fill(m,4))
    DA = Array(D)
    BU = Bidiagonal(fill(m,4), fill(m,3), :U)
    BUA = Array(BU)
    BL = Bidiagonal(fill(m,4), fill(m,3), :L)
    BLA = Array(BL)
    T = Tridiagonal(fill(m,3), fill(m,4), fill(m,3))
    TA = Array(T)
    IA = Array(Diagonal(fill(one(m), 4)))
    @test S + D == D + S == SA + DA
    @test S - D == -(D - S) == SA - DA
    @test S + BU == SA + BUA
    @test S - BU == -(BU - S) == SA - BUA
    @test S + BL == SA + BLA
    @test S - BL == -(BL - S) == SA - BLA
    @test S + T == SA + TA
    @test S - T == -(T - S) == SA - TA
    @test S + S == SA + SA
    @test S - S == -(S - S) == SA - SA
    @test S + I == I + S == SA + IA
    @test S - I == -(I - S) == SA - IA

    @test S == S
    @test S != D
    @test S != BL
    @test S != BU
    @test S != T

    @test_throws ArgumentError fill!(S, m)
    S_small = SymTridiagonal(fill(m,2), fill(m,1))
    @test_throws "cannot fill a SymTridiagonal with an asymmetric value" fill!(S, m)
    fill!(S_small, Symmetric(m))
    @test all(==(Symmetric(m)), S_small)

    @testset "diag" begin
        m = SizedArrays.SizedArray{(2,2)}([1 3; 3 4])
        D = Diagonal(fill(m,4))
        z = fill(zero(m),3)
        d = fill(m,4)
        BU = Bidiagonal(d, z, :U)
        BL = Bidiagonal(d, z, :L)
        T = Tridiagonal(z, d, z)
        for ev in (fill(zero(m),3), fill(zero(m),4))
            SD = SymTridiagonal(fill(m,4), ev)
            @test SD == D == SD
            @test SD == BU == SD
            @test SD == BL == SD
            @test SD == T == SD
        end
    end
end

@testset "fillstored!" begin
    dv, ev = zeros(4), zeros(3)
    D = Diagonal(dv)
    LinearAlgebra.fillstored!(D, 2)
    @test D == diagm(fill(2, length(dv)))

    dv .= 0
    B = Bidiagonal(dv, ev, :U)
    LinearAlgebra.fillstored!(B, 2)
    @test B == diagm(0=>fill(2, length(dv)), 1=>fill(2, length(ev)))

    dv .= 0
    ev .= 0
    T = Tridiagonal(ev, dv, ev)
    LinearAlgebra.fillstored!(T, 2)
    @test T == diagm(-1=>fill(2, length(ev)), 0=>fill(2, length(dv)), 1=>fill(2, length(ev)))

    dv .= 0
    ev .= 0
    ST = SymTridiagonal(dv, ev)
    LinearAlgebra.fillstored!(ST, 2)
    @test ST == diagm(-1=>fill(2, length(ev)), 0=>fill(2, length(dv)), 1=>fill(2, length(ev)))
end

end # module TestSpecial
