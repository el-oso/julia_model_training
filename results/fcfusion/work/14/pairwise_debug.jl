using LinearAlgebra

function pairwise_dist_optimized(X)
    n = size(X, 1)
    norms = sum(x -> dot(x, x), eachrow(X))
    println("norms type: ", typeof(norms))
    println("norms size: ", size(norms))
    println("norms first 3: ", norms[1:3])
    
    G = X * X'
    println("G type: ", typeof(G))
    println("G size: ", size(G))
    println("G[1,2]: ", G[1,2])
    println("dot(x1,x2): ", dot(X[1,:], X[2,:]))
    
    D2 = norms .+ norms' .- 2*G
    println("D2 type: ", typeof(D2))
    println("D2 size: ", size(D2))
    println("D2[1,2]: ", D2[1,2])
    
    D2 = max.(D2, 0.0)
    return sqrt.(D2)
end

X = rand(5, 3)
D = pairwise_dist_optimized(X)
println("\nResult:")
println(D)
