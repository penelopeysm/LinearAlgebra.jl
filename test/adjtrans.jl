# This file is a part of Julia. License is MIT: https://julialang.org/license

module TestAdjointTranspose

isdefined(Main, :pruned_old_LA) || @eval Main include("prune_old_LA.jl")

using Test, LinearAlgebra

const TESTDIR = joinpath(dirname(pathof(LinearAlgebra)), "..", "test")
const TESTHELPERS = joinpath(TESTDIR, "testhelpers", "testhelpers.jl")
isdefined(Main, :LinearAlgebraTestHelpers) || Base.include(Main, TESTHELPERS)

using Main.LinearAlgebraTestHelpers.OffsetArrays
using Main.LinearAlgebraTestHelpers.ImmutableArrays

@testset "Adjoint and Transpose inner constructor basics" begin
    intvec, intmat = [1, 2], [1 2; 3 4]
    # Adjoint/Transpose eltype must match the type of the Adjoint/Transpose of the input eltype
    @test_throws TypeError Adjoint{Float64,Vector{Int}}(intvec)[1,1]
    @test_throws TypeError Adjoint{Float64,Matrix{Int}}(intmat)[1,1]
    @test_throws TypeError Transpose{Float64,Vector{Int}}(intvec)[1,1]
    @test_throws TypeError Transpose{Float64,Matrix{Int}}(intmat)[1,1]
    # Adjoint/Transpose wrapped array type must match the input array type
    @test_throws TypeError Adjoint{Int,Vector{Float64}}(intvec)[1,1]
    @test_throws TypeError Adjoint{Int,Matrix{Float64}}(intmat)[1,1]
    @test_throws TypeError Transpose{Int,Vector{Float64}}(intvec)[1,1]
    @test_throws TypeError Transpose{Int,Matrix{Float64}}(intmat)[1,1]
    # Adjoint/Transpose inner constructor basic functionality, concrete scalar eltype
    @test (Adjoint{Int,Vector{Int}}(intvec)::Adjoint{Int,Vector{Int}}).parent === intvec
    @test (Adjoint{Int,Matrix{Int}}(intmat)::Adjoint{Int,Matrix{Int}}).parent === intmat
    @test (Transpose{Int,Vector{Int}}(intvec)::Transpose{Int,Vector{Int}}).parent === intvec
    @test (Transpose{Int,Matrix{Int}}(intmat)::Transpose{Int,Matrix{Int}}).parent === intmat
    # Adjoint/Transpose inner constructor basic functionality, abstract scalar eltype
    anyvec, anymat = Any[1, 2], Any[1 2; 3 4]
    @test (Adjoint{Any,Vector{Any}}(anyvec)::Adjoint{Any,Vector{Any}}).parent === anyvec
    @test (Adjoint{Any,Matrix{Any}}(anymat)::Adjoint{Any,Matrix{Any}}).parent === anymat
    @test (Transpose{Any,Vector{Any}}(anyvec)::Transpose{Any,Vector{Any}}).parent === anyvec
    @test (Transpose{Any,Matrix{Any}}(anymat)::Transpose{Any,Matrix{Any}}).parent === anymat
    # Adjoint/Transpose inner constructor basic functionality, concrete array eltype
    intvecvec = [[1, 2], [3, 4]]
    intmatmat = [[[1 2]] [[3 4]] [[5 6]]; [[7 8]] [[9 10]] [[11 12]]]
    @test (X = Adjoint{Adjoint{Int,Vector{Int}},Vector{Vector{Int}}}(intvecvec);
            isa(X, Adjoint{Adjoint{Int,Vector{Int}},Vector{Vector{Int}}}) && X.parent === intvecvec)
    @test (X = Adjoint{Adjoint{Int,Matrix{Int}},Matrix{Matrix{Int}}}(intmatmat);
            isa(X, Adjoint{Adjoint{Int,Matrix{Int}},Matrix{Matrix{Int}}}) && X.parent === intmatmat)
    @test (X = Transpose{Transpose{Int,Vector{Int}},Vector{Vector{Int}}}(intvecvec);
            isa(X, Transpose{Transpose{Int,Vector{Int}},Vector{Vector{Int}}}) && X.parent === intvecvec)
    @test (X = Transpose{Transpose{Int,Matrix{Int}},Matrix{Matrix{Int}}}(intmatmat);
            isa(X, Transpose{Transpose{Int,Matrix{Int}},Matrix{Matrix{Int}}}) && X.parent === intmatmat)
end

@testset "Adjoint and Transpose outer constructor basics" begin
    intvec, intmat = [1, 2], [1 2; 3 4]
    # the wrapped array's eltype strictly determines the Adjoint/Transpose eltype
    # so Adjoint{T}/Transpose{T} constructors are somewhat unnecessary and error-prone
    # so ascertain that such calls throw whether or not T and the input eltype are compatible
    @test_throws MethodError Adjoint{Int}(intvec)
    @test_throws MethodError Adjoint{Int}(intmat)
    @test_throws MethodError Adjoint{Float64}(intvec)
    @test_throws MethodError Adjoint{Float64}(intmat)
    @test_throws MethodError Transpose{Int}(intvec)
    @test_throws MethodError Transpose{Int}(intmat)
    @test_throws MethodError Transpose{Float64}(intvec)
    @test_throws MethodError Transpose{Float64}(intmat)
    # Adjoint/Transpose outer constructor basic functionality, concrete scalar eltype
    @test (Adjoint(intvec)::Adjoint{Int,Vector{Int}}).parent === intvec
    @test (Adjoint(intmat)::Adjoint{Int,Matrix{Int}}).parent === intmat
    @test (Transpose(intvec)::Transpose{Int,Vector{Int}}).parent === intvec
    @test (Transpose(intmat)::Transpose{Int,Matrix{Int}}).parent === intmat
    # the tests for the inner constructors exercise abstract scalar and concrete array eltype, forgoing here
end

@testset "Adjoint and Transpose add additional layers to already-wrapped objects" begin
    intvec, intmat = [1, 2], [1 2; 3 4]
    @test (A = Adjoint(Adjoint(intvec))::Adjoint{Int,Adjoint{Int,Vector{Int}}}; A.parent.parent === intvec)
    @test (A = Adjoint(Adjoint(intmat))::Adjoint{Int,Adjoint{Int,Matrix{Int}}}; A.parent.parent === intmat)
    @test (A = Transpose(Transpose(intvec))::Transpose{Int,Transpose{Int,Vector{Int}}}; A.parent.parent === intvec)
    @test (A = Transpose(Transpose(intmat))::Transpose{Int,Transpose{Int,Matrix{Int}}}; A.parent.parent === intmat)
end

@testset "Adjoint and Transpose basic AbstractArray functionality" begin
    # vectors and matrices with real scalar eltype, and their adjoints/transposes
    intvec, intmat = [1, 2], [1 2 3; 4 5 6]
    tintvec, tintmat = [1 2], [1 4; 2 5; 3 6]
    @testset "length methods" begin
        @test length(Adjoint(intvec)) == length(intvec)
        @test length(Adjoint(intmat)) == length(intmat)
        @test length(Transpose(intvec)) == length(intvec)
        @test length(Transpose(intmat)) == length(intmat)
    end
    @testset "size methods" begin
        @test size(Adjoint(intvec)) == (1, length(intvec))
        @test size(Adjoint(intmat)) == reverse(size(intmat))
        @test size(Transpose(intvec)) == (1, length(intvec))
        @test size(Transpose(intmat)) == reverse(size(intmat))
    end
    @testset "axes methods" begin
        @test axes(Adjoint(intvec)) == (Base.OneTo(1), Base.OneTo(length(intvec)))
        @test axes(Adjoint(intmat)) == reverse(axes(intmat))
        @test axes(Transpose(intvec)) == (Base.OneTo(1), Base.OneTo(length(intvec)))
        @test axes(Transpose(intmat)) == reverse(axes(intmat))

        A = OffsetArray([1,2], 2)
        @test (@inferred axes(A')[2]) === axes(A,1)
        @test (@inferred axes(A')[1]) === axes(A,2)
    end
    @testset "IndexStyle methods" begin
        @test IndexStyle(Adjoint(intvec)) == IndexLinear()
        @test IndexStyle(Adjoint(intmat)) == IndexCartesian()
        @test IndexStyle(Transpose(intvec)) == IndexLinear()
        @test IndexStyle(Transpose(intmat)) == IndexCartesian()
    end
    # vectors and matrices with complex scalar eltype, and their adjoints/transposes
    complexintvec, complexintmat = [1im, 2im], [1im 2im 3im; 4im 5im 6im]
    tcomplexintvec, tcomplexintmat = [1im 2im], [1im 4im; 2im 5im; 3im 6im]
    acomplexintvec, acomplexintmat = conj.(tcomplexintvec), conj.(tcomplexintmat)
    # vectors and matrices with real-vector and real-matrix eltype, and their adjoints/transposes
    intvecvec = [[1, 2], [3, 4]]
    tintvecvec = [[[1 2]] [[3 4]]]
    intmatmat = [[[1 2]] [[3  4]] [[ 5  6]];
                 [[7 8]] [[9 10]] [[11 12]]]
    tintmatmat = [[hcat([1, 2])] [hcat([7, 8])];
                  [hcat([3, 4])] [hcat([9, 10])];
                  [hcat([5, 6])] [hcat([11, 12])]]
    # vectors and matrices with complex-vector and complex-matrix eltype, and their adjoints/transposes
    complexintvecvec, complexintmatmat = im .* (intvecvec, intmatmat)
    tcomplexintvecvec, tcomplexintmatmat = im .* (tintvecvec, tintmatmat)
    acomplexintvecvec, acomplexintmatmat = conj.(tcomplexintvecvec), conj.(tcomplexintmatmat)
    @testset "getindex methods, elementary" begin
        # implicitly test elementary definitions, for arrays with concrete real scalar eltype
        @test Adjoint(intvec) == tintvec
        @test Adjoint(intmat) == tintmat
        @test Transpose(intvec) == tintvec
        @test Transpose(intmat) == tintmat
        # implicitly test elementary definitions, for arrays with concrete complex scalar eltype
        @test Adjoint(complexintvec) == acomplexintvec
        @test Adjoint(complexintmat) == acomplexintmat
        @test Transpose(complexintvec) == tcomplexintvec
        @test Transpose(complexintmat) == tcomplexintmat
        # implicitly test elementary definitions, for arrays with concrete real-array eltype
        @test Adjoint(intvecvec) == tintvecvec
        @test Adjoint(intmatmat) == tintmatmat
        @test Transpose(intvecvec) == tintvecvec
        @test Transpose(intmatmat) == tintmatmat
        # implicitly test elementary definitions, for arrays with concrete complex-array type
        @test Adjoint(complexintvecvec) == acomplexintvecvec
        @test Adjoint(complexintmatmat) == acomplexintmatmat
        @test Transpose(complexintvecvec) == tcomplexintvecvec
        @test Transpose(complexintmatmat) == tcomplexintmatmat
    end
    @testset "getindex(::AdjOrTransVec, ::Colon, ::AbstractArray{Int}) methods that preserve wrapper type" begin
        # for arrays with concrete scalar eltype
        @test Adjoint(intvec)[:, [1, 2]] == Adjoint(intvec)
        @test Transpose(intvec)[:, [1, 2]] == Transpose(intvec)
        @test Adjoint(complexintvec)[:, [1, 2]] == Adjoint(complexintvec)
        @test Transpose(complexintvec)[:, [1, 2]] == Transpose(complexintvec)
        # for arrays with concrete array eltype
        @test Adjoint(intvecvec)[:, [1, 2]] == Adjoint(intvecvec)
        @test Transpose(intvecvec)[:, [1, 2]] == Transpose(intvecvec)
        @test Adjoint(complexintvecvec)[:, [1, 2]] == Adjoint(complexintvecvec)
        @test Transpose(complexintvecvec)[:, [1, 2]] == Transpose(complexintvecvec)
    end
    @testset "getindex(::AdjOrTransVec, ::Colon, ::Colon) methods that preserve wrapper type" begin
        # for arrays with concrete scalar eltype
        @test Adjoint(intvec)[:, :] == Adjoint(intvec)
        @test Transpose(intvec)[:, :] == Transpose(intvec)
        @test Adjoint(complexintvec)[:, :] == Adjoint(complexintvec)
        @test Transpose(complexintvec)[:, :] == Transpose(complexintvec)
        # for arrays with concrete array elype
        @test Adjoint(intvecvec)[:, :] == Adjoint(intvecvec)
        @test Transpose(intvecvec)[:, :] == Transpose(intvecvec)
        @test Adjoint(complexintvecvec)[:, :] == Adjoint(complexintvecvec)
        @test Transpose(complexintvecvec)[:, :] == Transpose(complexintvecvec)
    end
    @testset "getindex(::AdjOrTransVec, ::Colon, ::Int) should preserve wrapper type on result entries" begin
        # for arrays with concrete scalar eltype
        @test Adjoint(intvec)[:, 2] == intvec[2:2]
        @test Transpose(intvec)[:, 2] == intvec[2:2]
        @test Adjoint(complexintvec)[:, 2] == conj.(complexintvec[2:2])
        @test Transpose(complexintvec)[:, 2] == complexintvec[2:2]
        # for arrays with concrete array eltype
        @test Adjoint(intvecvec)[:, 2] == Adjoint.(intvecvec[2:2])
        @test Transpose(intvecvec)[:, 2] == Transpose.(intvecvec[2:2])
        @test Adjoint(complexintvecvec)[:, 2] == Adjoint.(complexintvecvec[2:2])
        @test Transpose(complexintvecvec)[:, 2] == Transpose.(complexintvecvec[2:2])
    end
    @testset "setindex! methods" begin
        # for vectors with real scalar eltype
        @test (wv = Adjoint(copy(intvec));
                wv === setindex!(wv, 3, 2) &&
                 wv == setindex!(copy(tintvec), 3, 1, 2)    )
        @test (wv = Transpose(copy(intvec));
                wv === setindex!(wv, 4, 2) &&
                 wv == setindex!(copy(tintvec), 4, 1, 2)    )
        # for matrices with real scalar eltype
        @test (wA = Adjoint(copy(intmat));
                wA === setindex!(wA, 7, 3, 1) &&
                 wA == setindex!(copy(tintmat), 7, 3, 1)    )
        @test (wA = Transpose(copy(intmat));
                wA === setindex!(wA, 7, 3, 1) &&
                 wA == setindex!(copy(tintmat), 7, 3, 1)    )
        # for vectors with complex scalar eltype
        @test (wz = Adjoint(copy(complexintvec));
                wz === setindex!(wz, 3im, 2) &&
                 wz == setindex!(copy(acomplexintvec), 3im, 1, 2)   )
        @test (wz = Transpose(copy(complexintvec));
                wz === setindex!(wz, 4im, 2) &&
                 wz == setindex!(copy(tcomplexintvec), 4im, 1, 2)   )
        # for  matrices with complex scalar eltype
        @test (wZ = Adjoint(copy(complexintmat));
                wZ === setindex!(wZ, 7im, 3, 1) &&
                 wZ == setindex!(copy(acomplexintmat), 7im, 3, 1)   )
        @test (wZ = Transpose(copy(complexintmat));
                wZ === setindex!(wZ, 7im, 3, 1) &&
                 wZ == setindex!(copy(tcomplexintmat), 7im, 3, 1)   )
        # for vectors with concrete real-vector eltype
        @test (wv = Adjoint(copy(intvecvec));
                wv === setindex!(wv, Adjoint([5, 6]), 2) &&
                 wv == setindex!(copy(tintvecvec), [5 6], 2))
        @test (wv = Transpose(copy(intvecvec));
                wv === setindex!(wv, Transpose([5, 6]), 2) &&
                 wv == setindex!(copy(tintvecvec), [5 6], 2))
        # for matrices with concrete real-matrix eltype
        @test (wA = Adjoint(copy(intmatmat));
                wA === setindex!(wA, Adjoint([13 14]), 3, 1) &&
                 wA == setindex!(copy(tintmatmat), hcat([13, 14]), 3, 1))
        @test (wA = Transpose(copy(intmatmat));
                wA === setindex!(wA, Transpose([13 14]), 3, 1) &&
                 wA == setindex!(copy(tintmatmat), hcat([13, 14]), 3, 1))
        # for vectors with concrete complex-vector eltype
        @test (wz = Adjoint(copy(complexintvecvec));
                wz === setindex!(wz, Adjoint([5im, 6im]), 2) &&
                 wz == setindex!(copy(acomplexintvecvec), [-5im -6im], 2))
        @test (wz = Transpose(copy(complexintvecvec));
                wz === setindex!(wz, Transpose([5im, 6im]), 2) &&
                 wz == setindex!(copy(tcomplexintvecvec), [5im 6im], 2))
        # for matrices with concrete complex-matrix eltype
        @test (wZ = Adjoint(copy(complexintmatmat));
                wZ === setindex!(wZ, Adjoint([13im 14im]), 3, 1) &&
                 wZ == setindex!(copy(acomplexintmatmat), hcat([-13im, -14im]), 3, 1))
        @test (wZ = Transpose(copy(complexintmatmat));
                wZ === setindex!(wZ, Transpose([13im 14im]), 3, 1) &&
                 wZ == setindex!(copy(tcomplexintmatmat), hcat([13im, 14im]), 3, 1))
    end
end

@testset "Adjoint and Transpose convert methods that convert underlying storage" begin
    intvec, intmat = [1, 2], [1 2 3; 4 5 6]
    @test convert(Adjoint{Float64,Vector{Float64}}, Adjoint(intvec))::Adjoint{Float64,Vector{Float64}} == Adjoint(intvec)
    @test convert(Adjoint{Float64,Matrix{Float64}}, Adjoint(intmat))::Adjoint{Float64,Matrix{Float64}} == Adjoint(intmat)
    @test convert(Transpose{Float64,Vector{Float64}}, Transpose(intvec))::Transpose{Float64,Vector{Float64}} == Transpose(intvec)
    @test convert(Transpose{Float64,Matrix{Float64}}, Transpose(intmat))::Transpose{Float64,Matrix{Float64}} == Transpose(intmat)
end

@testset "Adjoint and Transpose convert methods to AbstractArray" begin
    # tests corresponding to #34995
    intvec, intmat = [1, 2], [1 2 3; 4 5 6]
    statvec = ImmutableArray(intvec)
    statmat = ImmutableArray(intmat)

    @test convert(AbstractArray{Float64}, Adjoint(statvec))::Adjoint{Float64,ImmutableArray{Float64,1,Array{Float64,1}}} == Adjoint(statvec)
    @test convert(AbstractArray{Float64}, Adjoint(statmat))::Array{Float64,2} == Adjoint(statmat)
    @test convert(AbstractArray{Float64}, Transpose(statvec))::Transpose{Float64,ImmutableArray{Float64,1,Array{Float64,1}}} == Transpose(statvec)
    @test convert(AbstractArray{Float64}, Transpose(statmat))::Array{Float64,2} == Transpose(statmat)
    @test convert(AbstractMatrix{Float64}, Adjoint(statvec))::Adjoint{Float64,ImmutableArray{Float64,1,Array{Float64,1}}} == Adjoint(statvec)
    @test convert(AbstractMatrix{Float64}, Adjoint(statmat))::Array{Float64,2} == Adjoint(statmat)
    @test convert(AbstractMatrix{Float64}, Transpose(statvec))::Transpose{Float64,ImmutableArray{Float64,1,Array{Float64,1}}} == Transpose(statvec)
    @test convert(AbstractMatrix{Float64}, Transpose(statmat))::Array{Float64,2} == Transpose(statmat)
end

@testset "Adjoint and Transpose similar methods" begin
    intvec, intmat = [1, 2], [1 2 3; 4 5 6]
    # similar with no additional specifications, vector (rewrapping) semantics
    @test size(similar(Adjoint(intvec))::Adjoint{Int,Vector{Int}}) == size(Adjoint(intvec))
    @test size(similar(Transpose(intvec))::Transpose{Int,Vector{Int}}) == size(Transpose(intvec))
    # similar with no additional specifications, matrix (no-rewrapping) semantics
    @test size(similar(Adjoint(intmat))::Matrix{Int}) == size(Adjoint(intmat))
    @test size(similar(Transpose(intmat))::Matrix{Int}) == size(Transpose(intmat))
    # similar with element type specification, vector (rewrapping) semantics
    @test size(similar(Adjoint(intvec), Float64)::Adjoint{Float64,Vector{Float64}}) == size(Adjoint(intvec))
    @test size(similar(Transpose(intvec), Float64)::Transpose{Float64,Vector{Float64}}) == size(Transpose(intvec))
    # similar with element type specification, matrix (no-rewrapping) semantics
    @test size(similar(Adjoint(intmat), Float64)::Matrix{Float64}) == size(Adjoint(intmat))
    @test size(similar(Transpose(intmat), Float64)::Matrix{Float64}) == size(Transpose(intmat))
    # similar with element type and arbitrary dims specifications
    shape = (2, 2, 2)
    @test size(similar(Adjoint(intvec), Float64, shape)::Array{Float64,3}) == shape
    @test size(similar(Adjoint(intmat), Float64, shape)::Array{Float64,3}) == shape
    @test size(similar(Transpose(intvec), Float64, shape)::Array{Float64,3}) == shape
    @test size(similar(Transpose(intmat), Float64, shape)::Array{Float64,3}) == shape
end

@testset "Adjoint and Transpose parent methods" begin
    intvec, intmat = [1, 2], [1 2 3; 4 5 6]
    @test parent(Adjoint(intvec)) === intvec
    @test parent(Adjoint(intmat)) === intmat
    @test parent(Transpose(intvec)) === intvec
    @test parent(Transpose(intmat)) === intmat
end

@testset "Adjoint and Transpose vector vec methods" begin
    intvec = [1, 2]
    @test vec(Adjoint(intvec)) === intvec
    @test vec(Transpose(intvec)) === intvec
    cvec = [1 + 1im]
    @test vec(cvec')[1] == cvec[1]'
    mvec = [[1 2; 3 4+5im]];
    @test vec(transpose(mvec))[1] == transpose(mvec[1])
    @test vec(adjoint(mvec))[1] == adjoint(mvec[1])
end

@testset "Adjoint and Transpose view methods" begin
    intvec, intmat = [1, 2], [1 2 3; 4 5 6]
    # overload of reshape(v, Val(1)) simplifies views of row vectors:
    @test view(adjoint(intvec), 1:2) isa SubArray{Int, 1, Vector{Int}}
    @test view(transpose(intvec), 1:2) isa SubArray{Int, 1, Vector{Int}}
    cvec = [1, 2im, 3, 4im]
    @test view(transpose(cvec), 2:3) === view(cvec, 2:3)
    @test view(adjoint(cvec), 2:3) == conj(view(cvec, 2:3))

    # vector slices of transposed matrices are simplified:
    @test view(adjoint(intmat), 1, :) isa SubArray{Int, 1, Matrix{Int}}
    @test view(transpose(intmat), 1, :) isa SubArray{Int, 1, Matrix{Int}}
    @test view(adjoint(intmat), 1, :) == permutedims(intmat)[1, :]
    @test view(transpose(intmat), 1:1, :) == permutedims(intmat)[1:1, :] # not simplified
    @test view(adjoint(intmat), :, 2) isa SubArray{Int, 1, Matrix{Int}}
    @test view(transpose(intmat), :, 2) isa SubArray{Int, 1, Matrix{Int}}
    @test view(adjoint(intmat), :, 2) == permutedims(intmat)[:, 2]
    @test view(transpose(intmat), :, 2:2) == permutedims(intmat)[:, 2:2] # not simplified
    cmat = [1 2im 3; 4im 5 6im]
    @test view(transpose(cmat), 1, :) isa SubArray{Complex{Int}, 1, Matrix{Complex{Int}}}
    @test view(transpose(cmat), :, 2) == cmat[2, :]
    @test view(adjoint(cmat), :, 2) == conj(cmat[2, :]) # not simplified

    # bounds checks happen before this
    @test_throws BoundsError view(adjoint(intvec), 0:3)
    @test_throws BoundsError view(transpose(cvec), 0:3)
    @test_throws BoundsError view(adjoint(intmat), :, 3)
end

@testset "horizontal concatenation of Adjoint/Transpose-wrapped vectors and Numbers" begin
    # horizontal concatenation of Adjoint/Transpose-wrapped vectors and Numbers
    # should preserve the Adjoint/Transpose-wrapper to preserve semantics downstream
    vec, tvec, avec = [1im, 2im], [1im 2im], [-1im -2im]
    vecvec = [[1im, 2im], [3im, 4im]]
    tvecvec = [[[1im 2im]] [[3im 4im]]]
    avecvec = [[[-1im -2im]] [[-3im -4im]]]
    # for arrays with concrete scalar eltype
    @test hcat(Adjoint(vec), Adjoint(vec))::Adjoint{Complex{Int},Vector{Complex{Int}}} == hcat(avec, avec)
    @test hcat(Adjoint(vec), 1, Adjoint(vec))::Adjoint{Complex{Int},Vector{Complex{Int}}} == hcat(avec, 1, avec)
    @test hcat(Transpose(vec), Transpose(vec))::Transpose{Complex{Int},Vector{Complex{Int}}} == hcat(tvec, tvec)
    @test hcat(Transpose(vec), 1, Transpose(vec))::Transpose{Complex{Int},Vector{Complex{Int}}} == hcat(tvec, 1, tvec)
    # for arrays with concrete array eltype
    @test hcat(Adjoint(vecvec), Adjoint(vecvec))::Adjoint{Adjoint{Complex{Int},Vector{Complex{Int}}},Vector{Vector{Complex{Int}}}} == hcat(avecvec, avecvec)
    @test hcat(Transpose(vecvec), Transpose(vecvec))::Transpose{Transpose{Complex{Int},Vector{Complex{Int}}},Vector{Vector{Complex{Int}}}} == hcat(tvecvec, tvecvec)
end

@testset "map/broadcast over Adjoint/Transpose-wrapped vectors and Numbers" begin
    # map and broadcast over Adjoint/Transpose-wrapped vectors and Numbers
    # should preserve the Adjoint/Transpose-wrapper to preserve semantics downstream
    vec, tvec, avec = [1im, 2im], [1im 2im], [-1im -2im]
    vecvec = [[1im, 2im], [3im, 4im]]
    tvecvec = [[[1im 2im]] [[3im 4im]]]
    avecvec = [[[-1im -2im]] [[-3im -4im]]]
    # unary map over wrapped vectors with concrete scalar eltype
    @test map(-, Adjoint(vec))::Adjoint{Complex{Int},Vector{Complex{Int}}} == -avec
    @test map(-, Transpose(vec))::Transpose{Complex{Int},Vector{Complex{Int}}} == -tvec
    # unary map over wrapped vectors with concrete array eltype
    @test map(-, Adjoint(vecvec))::Adjoint{Adjoint{Complex{Int},Vector{Complex{Int}}},Vector{Vector{Complex{Int}}}} == -avecvec
    @test map(-, Transpose(vecvec))::Transpose{Transpose{Complex{Int},Vector{Complex{Int}}},Vector{Vector{Complex{Int}}}} == -tvecvec
    # binary map over wrapped vectors with concrete scalar eltype
    @test map(+, Adjoint(vec), Adjoint(vec))::Adjoint{Complex{Int},Vector{Complex{Int}}} == avec + avec
    @test map(+, Transpose(vec), Transpose(vec))::Transpose{Complex{Int},Vector{Complex{Int}}} == tvec + tvec
    # binary map over wrapped vectors with concrete array eltype
    @test map(+, Adjoint(vecvec), Adjoint(vecvec))::Adjoint{Adjoint{Complex{Int},Vector{Complex{Int}}},Vector{Vector{Complex{Int}}}} == avecvec + avecvec
    @test map(+, Transpose(vecvec), Transpose(vecvec))::Transpose{Transpose{Complex{Int},Vector{Complex{Int}}},Vector{Vector{Complex{Int}}}} == tvecvec + tvecvec
    # unary broadcast over wrapped vectors with concrete scalar eltype
    @test broadcast(-, Adjoint(vec))::Adjoint{Complex{Int},Vector{Complex{Int}}} == -avec
    @test broadcast(-, Transpose(vec))::Transpose{Complex{Int},Vector{Complex{Int}}} == -tvec
    # unary broadcast over wrapped vectors with concrete array eltype
    @test broadcast(-, Adjoint(vecvec))::Adjoint{Adjoint{Complex{Int},Vector{Complex{Int}}},Vector{Vector{Complex{Int}}}} == -avecvec
    @test broadcast(-, Transpose(vecvec))::Transpose{Transpose{Complex{Int},Vector{Complex{Int}}},Vector{Vector{Complex{Int}}}} == -tvecvec
    # binary broadcast over wrapped vectors with concrete scalar eltype
    @test broadcast(+, Adjoint(vec), Adjoint(vec))::Adjoint{Complex{Int},Vector{Complex{Int}}} == avec + avec
    @test broadcast(+, Transpose(vec), Transpose(vec))::Transpose{Complex{Int},Vector{Complex{Int}}} == tvec + tvec
    # binary broadcast over wrapped vectors with concrete array eltype
    @test broadcast(+, Adjoint(vecvec), Adjoint(vecvec))::Adjoint{Adjoint{Complex{Int},Vector{Complex{Int}}},Vector{Vector{Complex{Int}}}} == avecvec + avecvec
    @test broadcast(+, Transpose(vecvec), Transpose(vecvec))::Transpose{Transpose{Complex{Int},Vector{Complex{Int}}},Vector{Vector{Complex{Int}}}} == tvecvec + tvecvec
    # trinary broadcast over wrapped vectors with concrete scalar eltype and numbers
    @test broadcast(+, Adjoint(vec), 1, Adjoint(vec))::Adjoint{Complex{Int},Vector{Complex{Int}}} == avec + avec .+ 1
    @test broadcast(+, Transpose(vec), 1, Transpose(vec))::Transpose{Complex{Int},Vector{Complex{Int}}} == tvec + tvec .+ 1
    @test broadcast(+, Adjoint(vec), 1im, Adjoint(vec))::Adjoint{Complex{Int},Vector{Complex{Int}}} == avec + avec .+ 1im
    @test broadcast(+, Transpose(vec), 1im, Transpose(vec))::Transpose{Complex{Int},Vector{Complex{Int}}} == tvec + tvec .+ 1im
end

@testset "Adjoint/Transpose-wrapped vector multiplication" begin
    realvec, realmat = [1, 2, 3], [1 2 3; 4 5 6; 7 8 9]
    complexvec, complexmat = [1im, 2, -3im], [1im 2 3; 4 5 -6im; 7im 8 9]
    # Adjoint/Transpose-vector * vector
    @test Adjoint(realvec) * realvec == dot(realvec, realvec)
    @test Transpose(realvec) * realvec == dot(realvec, realvec)
    @test Adjoint(complexvec) * complexvec == dot(complexvec, complexvec)
    @test Transpose(complexvec) * complexvec == dot(conj(complexvec), complexvec)
    # vector * Adjoint/Transpose-vector
    @test realvec * Adjoint(realvec) == broadcast(*, realvec, reshape(realvec, (1, 3)))
    @test realvec * Transpose(realvec) == broadcast(*, realvec, reshape(realvec, (1, 3)))
    @test complexvec * Adjoint(complexvec) == broadcast(*, complexvec, reshape(conj(complexvec), (1, 3)))
    @test complexvec * Transpose(complexvec) == broadcast(*, complexvec, reshape(complexvec, (1, 3)))
    # Adjoint/Transpose-vector * matrix
    @test (Adjoint(realvec) * realmat)::Adjoint{Int,Vector{Int}} ==
        reshape(copy(Adjoint(realmat)) * realvec, (1, 3))
    @test (Transpose(realvec) * realmat)::Transpose{Int,Vector{Int}} ==
        reshape(copy(Transpose(realmat)) * realvec, (1, 3))
    @test (Adjoint(complexvec) * complexmat)::Adjoint{Complex{Int},Vector{Complex{Int}}} ==
        reshape(conj(copy(Adjoint(complexmat)) * complexvec), (1, 3))
    @test (Transpose(complexvec) * complexmat)::Transpose{Complex{Int},Vector{Complex{Int}}} ==
        reshape(copy(Transpose(complexmat)) * complexvec, (1, 3))
    # Adjoint/Transpose-vector * Adjoint/Transpose-matrix
    @test (Adjoint(realvec) * Adjoint(realmat))::Adjoint{Int,Vector{Int}} ==
        reshape(realmat * realvec, (1, 3))
    @test (Transpose(realvec) * Transpose(realmat))::Transpose{Int,Vector{Int}} ==
        reshape(realmat * realvec, (1, 3))
    @test (Adjoint(complexvec) * Adjoint(complexmat))::Adjoint{Complex{Int},Vector{Complex{Int}}} ==
        reshape(conj(complexmat * complexvec), (1, 3))
    @test (Transpose(complexvec) * Transpose(complexmat))::Transpose{Complex{Int},Vector{Complex{Int}}} ==
        reshape(complexmat * complexvec, (1, 3))
end

@testset "Adjoint/Transpose-wrapped vector pseudoinversion" begin
    realvec, complexvec = [1, 2, 3, 4], [1im, 2, 3im, 4]
    rowrealvec, rowcomplexvec = reshape(realvec, (1, 4)), reshape(complexvec, (1, 4))
    # pinv(Adjoint/Transpose-vector) should match matrix equivalents
    # TODO tighten type asserts once pinv yields Transpose/Adjoint
    @test pinv(Adjoint(realvec))::Vector{Float64} ≈ pinv(rowrealvec)
    @test pinv(Transpose(realvec))::Vector{Float64} ≈ pinv(rowrealvec)
    @test pinv(Adjoint(complexvec))::Vector{ComplexF64} ≈ pinv(conj(rowcomplexvec))
    @test pinv(Transpose(complexvec))::Vector{ComplexF64} ≈ pinv(rowcomplexvec)
end

@testset "Adjoint/Transpose-wrapped vector left-division" begin
    realvec, complexvec = [1., 2., 3., 4.,], [1.0im, 2., 3.0im, 4.]
    rowrealvec, rowcomplexvec = reshape(realvec, (1, 4)), reshape(complexvec, (1, 4))
    # \(Adjoint/Transpose-vector, Adjoint/Transpose-vector) should mat matrix equivalents
    @test Adjoint(realvec)\Adjoint(realvec) ≈ rowrealvec\rowrealvec
    @test Transpose(realvec)\Transpose(realvec) ≈ rowrealvec\rowrealvec
    @test Adjoint(complexvec)\Adjoint(complexvec) ≈ conj(rowcomplexvec)\conj(rowcomplexvec)
    @test Transpose(complexvec)\Transpose(complexvec) ≈ rowcomplexvec\rowcomplexvec
end

@testset "Adjoint/Transpose-wrapped vector right-division" begin
    realvec, realmat = [1, 2, 3], [1 0 0; 0 2 0; 0 0 3]
    complexvec, complexmat = [1im, 2, -3im], [2im 0 0; 0 3 0; 0 0 -5im]
    rowrealvec, rowcomplexvec = reshape(realvec, (1, 3)), reshape(complexvec, (1, 3))
    # /(Adjoint/Transpose-vector, matrix)
    @test (Adjoint(realvec) / realmat)::Adjoint ≈ rowrealvec / realmat
    @test (Adjoint(complexvec) / complexmat)::Adjoint ≈ conj(rowcomplexvec) / complexmat
    @test (Transpose(realvec) / realmat)::Transpose ≈ rowrealvec / realmat
    @test (Transpose(complexvec) / complexmat)::Transpose ≈ rowcomplexvec / complexmat
    # /(Adjoint/Transpose-vector, Adjoint matrix)
    @test (Adjoint(realvec) / Adjoint(realmat))::Adjoint ≈ rowrealvec / copy(Adjoint(realmat))
    @test (Adjoint(complexvec) / Adjoint(complexmat))::Adjoint ≈ conj(rowcomplexvec) / copy(Adjoint(complexmat))
    @test (Transpose(realvec) / Adjoint(realmat))::Transpose ≈ rowrealvec / copy(Adjoint(realmat))
    @test (Transpose(complexvec) / Adjoint(complexmat))::Transpose ≈ rowcomplexvec / copy(Adjoint(complexmat))
    # /(Adjoint/Transpose-vector, Transpose matrix)
    @test (Adjoint(realvec) / Transpose(realmat))::Adjoint ≈ rowrealvec / copy(Transpose(realmat))
    @test (Adjoint(complexvec) / Transpose(complexmat))::Adjoint ≈ conj(rowcomplexvec) / copy(Transpose(complexmat))
    @test (Transpose(realvec) / Transpose(realmat))::Transpose ≈ rowrealvec / copy(Transpose(realmat))
    @test (Transpose(complexvec) / Transpose(complexmat))::Transpose ≈ rowcomplexvec / copy(Transpose(complexmat))
end

@testset "norm and opnorm of Adjoint/Transpose-wrapped vectors" begin
    # definitions are in base/linalg/generic.jl
    realvec, complexvec = [3, -4], [3im, -4im]
    # one norm result should be sum(abs.(realvec)) == 7
    # two norm result should be sqrt(sum(abs.(realvec))) == 5
    # inf norm result should be maximum(abs.(realvec)) == 4
    for v in (realvec, complexvec)
        @test norm(Adjoint(v)) ≈ 5
        @test norm(Adjoint(v), 1) ≈ 7
        @test norm(Adjoint(v), Inf) ≈ 4
        @test norm(Transpose(v)) ≈ 5
        @test norm(Transpose(v), 1) ≈ 7
        @test norm(Transpose(v), Inf) ≈ 4
    end
    # one opnorm result should be maximum(abs.(realvec)) == 4
    # two opnorm result should be sqrt(sum(abs.(realvec))) == 5
    # inf opnorm result should be sum(abs.(realvec)) == 7
    for v in (realvec, complexvec)
        @test opnorm(Adjoint(v)) ≈ 5
        @test opnorm(Adjoint(v), 1) ≈ 4
        @test opnorm(Adjoint(v), Inf) ≈ 7
        @test opnorm(Transpose(v)) ≈ 5
        @test opnorm(Transpose(v), 1) ≈ 4
        @test opnorm(Transpose(v), Inf) ≈ 7
    end
end

@testset "adjoint and transpose of Numbers" begin
    @test adjoint(1) == 1
    @test adjoint(1.0) == 1.0
    @test adjoint(1im) == -1im
    @test adjoint(1.0im) == -1.0im
    @test transpose(1) == 1
    @test transpose(1.0) == 1.0
    @test transpose(1im) == 1im
    @test transpose(1.0im) == 1.0im
end

@testset "adjoint!(a, b) return a" begin
    a = fill(1.0+im, 5)
    b = fill(1.0+im, 1, 5)
    @test adjoint!(a, b) === a
    @test adjoint!(b, a) === b
end

@testset "copyto! uses adjoint!/transpose!" begin
    for T in (Float64, ComplexF64), f in (transpose, adjoint), sz in ((5,4), (5,))
        S = rand(T, sz)
        adjS = f(S)
        A = similar(S')
        copyto!(A, adjS)
        @test A == adjS
    end
end

@testset "aliasing with adjoint and transpose" begin
    A = collect(reshape(1:25, 5, 5)) .+ rand.().*im
    B = copy(A)
    B .= B'
    @test B == A'
    B = copy(A)
    B .= transpose(B)
    @test B == transpose(A)
    B = copy(A)
    B .= B .* B'
    @test B == A .* A'
end

@testset "test show methods for $t of Factorizations" for t in (adjoint, transpose)
    A = randn(ComplexF64, 4, 4)
    F = lu(A)
    Fop = t(F)
    @test sprint(show, Fop) ==
                  "$t of "*sprint(show, parent(Fop))
    @test sprint((io, t) -> show(io, MIME"text/plain"(), t), Fop) ==
                  "$t of "*sprint((io, t) -> show(io, MIME"text/plain"(), t), parent(Fop))
end

@testset "showarg" begin
    io = IOBuffer()

    A = ones(Float64, 3,3)

    B = Adjoint(A)
    @test summary(B) == "3×3 adjoint(::Matrix{Float64}) with eltype Float64"
    @test Base.showarg(io, B, false) === nothing
    @test String(take!(io)) == "adjoint(::Matrix{Float64})"

    B = Transpose(A)
    @test summary(B) == "3×3 transpose(::Matrix{Float64}) with eltype Float64"
    @test Base.showarg(io, B, false) === nothing
    @test String(take!(io)) == "transpose(::Matrix{Float64})"
end

@testset "show" begin
    @test repr(adjoint([1,2,3])) == "adjoint([1, 2, 3])"
    @test repr(transpose([1f0,2f0])) == "transpose(Float32[1.0, 2.0])"
end

@testset "strided transposes" begin
    for t in (Adjoint, Transpose)
        @test strides(t(rand(3))) == (3, 1)
        @test strides(t(rand(3,2))) == (3, 1)
        @test strides(t(view(rand(3, 2), :))) == (6, 1)
        @test strides(t(view(rand(3, 2), :, 1:2))) == (3, 1)

        A = rand(3)
        @test pointer(t(A)) === pointer(A)
        B = rand(3,1)
        @test pointer(t(B)) === pointer(B)
    end
    @test_throws MethodError strides(Adjoint(rand(3) .+ rand(3).*im))
    @test_throws MethodError strides(Adjoint(rand(3, 2) .+ rand(3, 2).*im))
    @test strides(Transpose(rand(3) .+ rand(3).*im)) == (3, 1)
    @test strides(Transpose(rand(3, 2) .+ rand(3, 2).*im)) == (3, 1)

    C = rand(3) .+ rand(3).*im
    @test_throws ErrorException pointer(Adjoint(C))
    @test pointer(Transpose(C)) === pointer(C)
    D = rand(3,2) .+ rand(3,2).*im
    @test_throws ErrorException pointer(Adjoint(D))
    @test pointer(Transpose(D)) === pointer(D)
end

@testset "offset axes" begin
    s = Base.Slice(-3:3)'
    @test axes(s) === (Base.OneTo(1), Base.IdentityUnitRange(-3:3))
    @test collect(LinearIndices(s)) == reshape(1:7, 1, 7)
    @test collect(CartesianIndices(s)) == reshape([CartesianIndex(1,i) for i = -3:3], 1, 7)
    @test s[1] == -3
    @test s[7] ==  3
    @test s[4] ==  0
    @test_throws BoundsError s[0]
    @test_throws BoundsError s[8]
    @test s[1,-3] == -3
    @test s[1, 3] ==  3
    @test s[1, 0] ==  0
    @test_throws BoundsError s[1,-4]
    @test_throws BoundsError s[1, 4]
end

@testset "specialized conj of Adjoint/Transpose" begin
    realmat = [1 2; 3 4]
    complexmat = ComplexF64[1+im 2; 3 4-im]
    nested = [[complexmat] [-complexmat]; [0complexmat] [3complexmat]]
    @testset "AdjOrTrans{...,$(typeof(i))}" for i in (
                                                      realmat, vec(realmat),
                                                      complexmat, vec(complexmat),
                                                      nested, vec(nested),
                                                     )
        for (t,type) in ((transpose, Adjoint), (adjoint, Transpose))
            M = t(i)
            @test conj(M) isa type
            @test conj(M) == conj(collect(M))
            @test conj(conj(M)) === M
        end
    end
    # test if `conj(transpose(::Hermitian))` is a no-op
    hermitian = Hermitian([1 2+im; 2-im 3])
    @test conj(transpose(hermitian)) === hermitian
end

@testset "empty and mismatched lengths" begin
    # issue 36678
    @test_throws DimensionMismatch [1, 2]' * [1,2,3]
    @test Int[]' * Int[] == 0
    @test transpose(Int[]) * Int[] == 0
end

@testset "reductions: $adjtrans" for adjtrans in (transpose, adjoint)
    for (reduction, reduction!, op) in ((sum, sum!, +), (prod, prod!, *), (minimum, minimum!, min), (maximum, maximum!, max))
        T = op in (max, min) ? Float64 : ComplexF64
        mat = rand(T, 3,5)
        rd1 = zeros(T, 1, 3)
        rd2 = zeros(T, 5, 1)
        rd3 = zeros(T, 1, 1)
        @test reduction(adjtrans(mat)) ≈ reduction(copy(adjtrans(mat)))
        @test reduction(adjtrans(mat), dims=1) ≈ reduction(copy(adjtrans(mat)), dims=1)
        @test reduction(adjtrans(mat), dims=2) ≈ reduction(copy(adjtrans(mat)), dims=2)
        @test reduction(adjtrans(mat), dims=(1,2)) ≈ reduction(copy(adjtrans(mat)), dims=(1,2))

        @test reduction!(rd1, adjtrans(mat)) ≈ reduction!(rd1, copy(adjtrans(mat)))
        @test reduction!(rd2, adjtrans(mat)) ≈ reduction!(rd2, copy(adjtrans(mat)))
        @test reduction!(rd3, adjtrans(mat)) ≈ reduction!(rd3, copy(adjtrans(mat)))

        @test reduction(imag, adjtrans(mat)) ≈ reduction(imag, copy(adjtrans(mat)))
        @test reduction(imag, adjtrans(mat), dims=1) ≈ reduction(imag, copy(adjtrans(mat)), dims=1)
        @test reduction(imag, adjtrans(mat), dims=2) ≈ reduction(imag, copy(adjtrans(mat)), dims=2)
        @test reduction(imag, adjtrans(mat), dims=(1,2)) ≈ reduction(imag, copy(adjtrans(mat)), dims=(1,2))

        @test Base.mapreducedim!(imag, op, rd1, adjtrans(mat)) ≈ Base.mapreducedim!(imag, op, rd1, copy(adjtrans(mat)))
        @test Base.mapreducedim!(imag, op, rd2, adjtrans(mat)) ≈ Base.mapreducedim!(imag, op, rd2, copy(adjtrans(mat)))
        @test Base.mapreducedim!(imag, op, rd3, adjtrans(mat)) ≈ Base.mapreducedim!(imag, op, rd3, copy(adjtrans(mat)))

        op in (max, min) && continue
        mat = [rand(T,2,2) for _ in 1:3, _ in 1:5]
        rd1 = fill(zeros(T, 2, 2), 1, 3)
        rd2 = fill(zeros(T, 2, 2), 5, 1)
        rd3 = fill(zeros(T, 2, 2), 1, 1)
        @test reduction(adjtrans(mat)) ≈ reduction(copy(adjtrans(mat)))
        @test reduction(adjtrans(mat), dims=1) ≈ reduction(copy(adjtrans(mat)), dims=1)
        @test reduction(adjtrans(mat), dims=2) ≈ reduction(copy(adjtrans(mat)), dims=2)
        @test reduction(adjtrans(mat), dims=(1,2)) ≈ reduction(copy(adjtrans(mat)), dims=(1,2))

        @test reduction(imag, adjtrans(mat)) ≈ reduction(imag, copy(adjtrans(mat)))
        @test reduction(x -> x[1,2], adjtrans(mat)) ≈ reduction(x -> x[1,2], copy(adjtrans(mat)))
        @test reduction(imag, adjtrans(mat), dims=1) ≈ reduction(imag, copy(adjtrans(mat)), dims=1)
        @test reduction(x -> x[1,2], adjtrans(mat), dims=1) ≈ reduction(x -> x[1,2], copy(adjtrans(mat)), dims=1)
    end
    # see #46605
    Ac = [1 2; 3 4]'
    @test mapreduce(identity, (x, y) -> 10x+y, copy(Ac)) == mapreduce(identity, (x, y) -> 10x+y, Ac) == 1234
    @test extrema([3,7,4]') == (3, 7)
    @test mapreduce(x -> [x;;;], +, [1, 2, 3]') == sum(x -> [x;;;], [1, 2, 3]') == [6;;;]
    @test mapreduce(string, *, [1 2; 3 4]') == mapreduce(string, *, copy([1 2; 3 4]')) == "1234"
end

@testset "trace" begin
    for T in (Float64, ComplexF64), t in (adjoint, transpose)
        A = randn(T, 10, 10)
        @test tr(t(A)) == tr(copy(t(A))) == t(tr(A))
    end
end

@testset "structured printing" begin
    D = Diagonal(1:3)
    @test sprint(Base.print_matrix, Adjoint(D)) == sprint(Base.print_matrix, D)
    @test sprint(Base.print_matrix, Transpose(D)) == sprint(Base.print_matrix, D)
    D = Diagonal((1:3)*im)
    D2 = Diagonal((1:3)*(-im))
    @test sprint(Base.print_matrix, Transpose(D)) == sprint(Base.print_matrix, D)
    @test sprint(Base.print_matrix, Adjoint(D)) == sprint(Base.print_matrix, D2)

    struct OneHotVecOrMat{N} <: AbstractArray{Bool,N}
        inds::NTuple{N,Int}
        sz::NTuple{N,Int}
    end
    Base.size(x::OneHotVecOrMat) = x.sz
    function Base.getindex(x::OneHotVecOrMat{N}, inds::Vararg{Int,N}) where {N}
        checkbounds(x, inds...)
        inds == x.inds
    end
    Base.replace_in_print_matrix(o::OneHotVecOrMat{1}, i::Integer, j::Integer, s::AbstractString) =
        o.inds == (i,) ? s : Base.replace_with_centered_mark(s)
    Base.replace_in_print_matrix(o::OneHotVecOrMat{2}, i::Integer, j::Integer, s::AbstractString) =
        o.inds == (i,j) ? s : Base.replace_with_centered_mark(s)

    o = OneHotVecOrMat((2,), (4,))
    @test sprint(Base.print_matrix, Transpose(o)) == sprint(Base.print_matrix, OneHotVecOrMat((1,2), (1,4)))
    @test sprint(Base.print_matrix, Adjoint(o)) == sprint(Base.print_matrix, OneHotVecOrMat((1,2), (1,4)))
end

@testset "copy_transpose!" begin
    # scalar case
    A = [randn() for _ in 1:2, _ in 1:3]
    At = copy(transpose(A))
    B = zero.(At)
    LinearAlgebra.copy_transpose!(B, axes(B, 1), axes(B, 2), A, axes(A, 1), axes(A, 2))
    @test B == At
    # matrix of matrices
    A = [randn(2,3) for _ in 1:2, _ in 1:3]
    At = copy(transpose(A))
    B = zero.(At)
    LinearAlgebra.copy_transpose!(B, axes(B, 1), axes(B, 2), A, axes(A, 1), axes(A, 2))
    @test B == At
end

@testset "error message in transpose" begin
    v = zeros(2)
    A = zeros(1,1)
    B = zeros(2,3)
    for (t1, t2) in Any[(A, v), (v, A), (A, B)]
        @test_throws "axes of the destination are incompatible with that of the source" transpose!(t1, t2)
        @test_throws "axes of the destination are incompatible with that of the source" adjoint!(t1, t2)
    end
end

@testset "band indexing" begin
    n = 3
    A = UnitUpperTriangular(Matrix(reshape(1:n^2, n, n)))
    @testset "every index" begin
        Aadj = Adjoint(A)
        for k in -(n-1):n-1
            di = diagind(Aadj, k, IndexStyle(Aadj))
            for (i,d) in enumerate(di)
                @test Aadj[LinearAlgebra.BandIndex(k,i)] == Aadj[d]
                if k < 0 # the adjoint is a unit lower triangular
                    Aadj[LinearAlgebra.BandIndex(k,i)] = n^2 + i
                    @test Aadj[d] == n^2 + i
                end
            end
        end
    end
    @testset "inference for structured matrices" begin
        function f(A, i, ::Val{band}) where {band}
            x = Adjoint(A)[LinearAlgebra.BandIndex(band,i)]
            Val(x)
        end
        v = @inferred f(A, 1, Val(0))
        @test v == Val(1)
        v = @inferred f(A, 1, Val(1))
        @test v == Val(0)
    end
    @testset "non-square matrix" begin
        r = reshape(1:6, 2, 3)
        for d in (r, r*im)
            @test d'[LinearAlgebra.BandIndex(1,1)] == adjoint(d[2,1])
            @test d'[LinearAlgebra.BandIndex(-1,2)] == adjoint(d[2,3])
            @test transpose(d)[LinearAlgebra.BandIndex(1,1)] == transpose(d[2,1])
            @test transpose(d)[LinearAlgebra.BandIndex(-1,2)] == transpose(d[2,3])
        end
    end
    @testset "block matrix" begin
        B = reshape([[1 2; 3 4]*i for i in 1:4], 2, 2)
        @test B'[LinearAlgebra.BandIndex(1,1)] == adjoint(B[2,1])
        @test transpose(B)[LinearAlgebra.BandIndex(1,1)] == transpose(B[2,1])
    end
end

@testset "diagview" begin
    for A in (rand(4, 4), rand(ComplexF64,4,4),
                fill([1 2; 3 4], 4, 4))
        for k in -3:3
            @test diagview(A', k) == diag(A', k)
            @test diagview(transpose(A), k) == diag(transpose(A), k)
        end
        @test IndexStyle(diagview(A')) == IndexLinear()
    end
end

@testset "triu!/tril!" begin
    @testset for sz in ((4,4), (3,4), (4,3))
        A = rand(sz...)
        B = similar(A)
        @testset for f in (adjoint, transpose), k in -3:3
            @test triu!(f(copy!(B, A)), k) == triu(f(A), k)
            @test tril!(f(copy!(B, A)), k) == tril!(f(A), k)
        end
    end
end

@testset "fillband!" begin
    for A in (rand(4, 4), rand(ComplexF64,4,4))
        B = similar(A)
        for op in (adjoint, transpose), k in -3:3
            B .= op(A)
            LinearAlgebra.fillband!(op(A), 1, k, k)
            LinearAlgebra.fillband!(B, 1, k, k)
            @test op(A) == B
        end
    end
end

end # module TestAdjointTranspose
