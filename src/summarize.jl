struct ChainDataFrame{NT<:NamedTuple}
    name::String
    nt::NT
    n_rows::Int
    n_cols::Int
    digits::Int

    function ChainDataFrame(name::String, nt::NamedTuple; digits::Int=4)
        ks = collect(keys(nt))

        lengths = length(nt[ks[1]])

        for i in 2:length(ks)
            if length(nt[ks[i]]) != lengths
                error("Lengths must be equal.")
            end
        end

        return new{typeof(nt)}(name, nt, lengths, length(ks), digits)
    end
end

ChainDataFrame(nt::NamedTuple) = ChainDataFrame("", nt)

Base.size(c::ChainDataFrame) = (c.n_rows, c.n_cols)
Base.names(c::ChainDataFrame) = collect(keys(c.nt))

function Base.show(io::IO, c::ChainDataFrame)
    println(io, c.name)

    # Preallocations
    n_cols = c.n_cols
    n_rows = c.n_rows
    column_names = collect(keys(c.nt))
    digits = c.digits
    f_format_str = "%.$(digits)f"
    i_format_str = "%n"

    # Create printed array.
    arr = Array{String, 2}(undef, n_rows + 1, n_cols)

    # Add headers
    arr[1, :] = string.(column_names)

    # Add values to array, accumulate string lengths.
    lengths = length.(arr[1,:])
    for i in 1:n_cols
        k = column_names[i]
        values = c.nt[k]
        etype = eltype(values)

        if etype <: Real
            arr[2:end, i] = sprintf1.(f_format_str, values)
        elseif etype <: Integer
            arr[2:end, i] = sprintf1.(i_format_str, values)
        else 
            arr[2:end, i] = string.(values)
        end
        lengths[i] = max(maximum(length.(arr[2:end, i])), lengths[i])
    end

    # Do it array style.
    bufs = [IOBuffer() for _ in 1:(n_rows+2)]

    for i in 1:n_cols
        for j in 1:(n_rows+2)
            # Print the headers
            if j == 1
                print(bufs[j],  "  ", lpad(arr[j,i], lengths[i]))
            end

            # Print sep row.
            if j == 2
                print(bufs[j], "  ", repeat("─", lengths[i]))
            end

            # Print values.
            if j > 2
                bufs[j]
                print(bufs[j], "  ", lpad(arr[j-1,i], lengths[i]))
            end
        end
    end

    for j in 1:length(bufs)
        s = String(take!(bufs[j]))
        println(io, s)
    end
end

Base.isequal(cs1::Vector{ChainDataFrame}, cs2::Vector{ChainDataFrame}) = isequal.(cs1, cs2)
Base.isequal(c1::ChainDataFrame, c2::ChainDataFrame) = isequal(c1, c2)

function Base.show(io::IO, cs::Vector{C}) where C<:ChainDataFrame
    println(io, summary(cs))
    for i in cs
        println(io)
        show(io, i)
    end
end

# Allows overriding of `display`
function Base.show(io::IO, ::MIME"text/plain", cs::Vector{ChainDataFrame})
    show(io, cs)
end

# Index functions
function Base.getindex(c::ChainDataFrame, s::Union{Colon, Integer, UnitRange}, g::Union{Colon, Integer, UnitRange})
    convert(Array, getindex(c, c.nt[:parameters][s], collect(keys(c.nt))[g]))
end

function Base.getindex(c::ChainDataFrame, s::Union{Symbol, Vector{Symbol}}, g::Colon)
    getindex(c, c.nt[:parameters], collect(keys(c.nt)))
end

function Base.getindex(c::ChainDataFrame, s::Union{Symbol, Vector{Symbol}})
    getindex(c, s, collect(keys(c.nt)))
end

function Base.getindex(c::ChainDataFrame, s::Union{Colon, Integer, UnitRange}, ks::Union{Symbol, Vector{Symbol}})
    getindex(c, c.nt[:parameters][s], ks)
end

function Base.getindex(
    c::ChainDataFrame, 
    s::Union{String, Vector{String}, Symbol, Vector{Symbol}}, 
    ks::Union{Symbol, Vector{Symbol}}
)
    s = s isa AbstractArray ? s : [s]
    ks = ks isa AbstractArray ? ks : [ks]
    ind = indexin(Symbol.(s), Symbol.(c.nt[:parameters]))

    not_found = map(x -> x === nothing, ind)

    any(not_found) && error("Cannot find parameters $(s[not_found]) in chain")

    # If there are multiple columns, return a new CDF.
    if length(ks) > 1
        if !(:parameters in ks)
            ks = vcat(:parameters, ks)
        end
        nt = NamedTuple{tuple(ks...)}(tuple([c.nt[k][ind] for k in ks]...))
        return ChainDataFrame(c.name, nt, digits=c.digits)
    else
        # Otherwise, return a vector if there's multiple parameters
        # or just a scalar if there's one parameter.
        if length(s) == 1
            return c.nt[ks[1]][ind][1]
        else
            return c.nt[ks[1]][ind]
        end
    end
end

function Base.lastindex(c::ChainDataFrame, i::Integer)
    if i == 1
        return c.n_rows
    elseif i ==2
        return c.n_cols
    else
        error("No such dimension")
    end
end

function Base.convert(::Type{Array}, c::C) where C<:ChainDataFrame
    T = promote_eltype_namedtuple_tail(c.nt)
    arr = Array{T, 2}(undef, c.n_rows, c.n_cols - 1)
    
    for (i, k) in enumerate(Iterators.drop(keys(c.nt), 1))
        arr[:, i] = c.nt[k]
    end

    return arr
end

Base.convert(::Type{Array{ChainDataFrame,1}}, cs::Array{ChainDataFrame,1}) = cs
function Base.convert(::Type{Array}, cs::Array{C,1}) where C<:ChainDataFrame
    return mapreduce((x, y) -> cat(x, y; dims = Val(3)), cs) do c
        reshape(convert(Array, c), Val(3))
    end
end

"""

# Summarize a Chains object formatted as a DataFrame

Summarize method for a Chains object.

### Method
```julia
  summarize(
    chn::Chains,
    funs...;
    sections::Vector{Symbol}=[:parameters],
    func_names=[],
    etype=:bm
  )
```

### Required arguments
```julia
* `chn` : Chains object to convert to a DataFrame-formatted summary
```

### Optional arguments
```julia
* `funs...` : zero or more vector functions, e.g. mean, std, etc.
* `sections = [:parameters]` : Sections from the Chains object to be included
* `etype = :bm` : Default for df_mcse
```

### Examples
```julia
* `summarize(chns)` : Complete chain summary
* `summarize(chns[[:parm1, :parm2]])` : Chain summary of selected parameters
* `summarize(chns, sections=[:parameters])`  : Chain summary of :parameters section
* `summarize(chns, sections=[:parameters, :internals])` : Chain summary for multiple sections
```

"""
function summarize(chn::Chains, funs...;
        sections::Union{Symbol, Vector{Symbol}}=Symbol[:parameters],
        func_names::AbstractVector{Symbol} = Symbol[],
        append_chains::Bool=true,
        showall::Bool=false,
        name::String="",
        additional_df=nothing,
        digits::Int=4,
        sorted::Bool=false)
    # Check that we actually have :parameters.
    showall = showall ? true : !in(:parameters, keys(chn.name_map))

    # If we weren't given any functions, fall back on summary stats.
    if length(funs) == 0
        return summarystats(chn,
            sections=sections,
            showall=showall)
    end

    # Generate a dataframe to work on.
    chn = Chains(chn, sections, sorted=sorted)
    # df = DataFrame(chn, sections, showall=showall, append_chains=append_chains)

    # If no function names were given, make a new list.
    fnames = isempty(func_names) ? collect(nameof.(funs)) : func_names

    # Do all the math, make columns.
    columns = if append_chains
        vcat([names(chn)],
             [[f(chn.value.data[:,col,:]) for col in 1:size(chn, 2)] for f in funs])
    else
        [vcat([names(chn)],
             [[f(chn.value.data[:,col,i]) for col in 1:size(chn, 2)] for f in funs])
             for i in 1:size(chn, 3)]
        # [vcat([names(chn[1])],
        #       [[f(col) for col = eachcol(i, false)] for f in funs]) for i in df]
    end

    # Make a vector of column names.
    colnames = vcat(:parameters, fnames)

    # Build the dataframes.
    ret_df = if append_chains
        NamedTuple{tuple(colnames...)}(tuple(columns...))
    else
        [NamedTuple{tuple(colnames...)}(tuple(columns[i]...)) 
        for i in 1:size(chn, 3)]
    end


    if additional_df != nothing
        if append_chains
            ret_df = merge_union(ret_df, additional_df.nt)
        else
            ret_df = [merge_union(r, additional_df.nt) for r in ret_df]
        end
    end

    if append_chains
        return ChainDataFrame(name, ret_df, digits=digits)
    else
        rdf = [ChainDataFrame(name * " (Chain $i)", r, digits=digits) for (i,r) in enumerate(ret_df)]
        return map(x -> x, rdf)
    end
end