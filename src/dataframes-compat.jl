using .DataFrames

"""

# DataFrame

DataFrame constructor from a Chains object.
Returns either a DataFrame or an Array{DataFrame}

### Method
```julia
  DataFrame(
    chn::Chains,
    sections::Vector{Symbo);
    append_chains::Bool,
    remove_missing_union::Bool
  )
```

### Required arguments
```julia
* `chn` : Chains object to convert to an DataFrame
```

### Optional arguments
```julia
* `sections = Symbol[]` : Sections from the Chains object to be included
* `append_chains = true`  : Append chains into a single column
* `remove_missing_union = true`  : Remove Union{Missing, Real}
```

### Examples
```julia
* `DataFrame(chns)` : DataFrame with chain values are appended
* `DataFrame(chns[:par])` : DataFrame with single parameter (chain values are appended)
* `DataFrame(chns, [:parameters])`  : DataFrame with only :parameter section
* `DataFrame(chns, [:parameters, :internals])`  : DataFrame includes both sections
* `DataFrame(chns, append_chains=false)`  : Array of DataFrames, each chain in its own array
* `DataFrame(chns, remove_missing_union=false)` : No conversion to remove missing values
```

"""
function DataFrames.DataFrame(chn::Chains,
    sections::Union{Symbol, Vector{Symbol}}=Symbol[:parameters];
    append_chains=true,
    remove_missing_union=true,
    sorted=false,
    showall=false)
    sections = _clean_sections(chn, sections)
    sections = sections isa AbstractArray ? sections : [sections]
    sections = showall ? [] : sections
    section_list = length(sections) == 0 ? sort_sections(chn) : sections

    # If we actually have missing values, we can't remove
    # Union{Missing}.
    remove_missing_union = remove_missing_union ?
        all(!ismissing, chn.value) :
        remove_missing_union

    d, p, c = size(chn.value.data)

    local b
    if append_chains
        b = DataFrame()
        for section in section_list
            names = sorted ?
                sort(chn.name_map[section],
                    by=x->string(x), lt = natural) :
                chn.name_map[section]
            for par in names
                x = get(chn, Symbol(par))
                d, c = size(x[Symbol(par)])
                if remove_missing_union
                    b = hcat(b, DataFrame(Symbol(par) => reshape(convert(Array{Float64},
                    x[Symbol(par)]), d*c)[:, 1]))
                else
                    b = hcat(b, DataFrame(Symbol(par) => reshape(x[Symbol(par)], d*c)[:, 1]))
                end
            end
        end
    else
        b = Vector{DataFrame}(undef, c)
        for i in 1:c
            b[i] = DataFrame()
            for section in section_list
                names = sorted ?
                    sort(chn.name_map[section],
                        by=x->string(x), lt = natural) :
                    chn.name_map[section]
                for par in names
                    x = get(chn[:,:,i], Symbol(par))
                    d, c = size(x[Symbol(par)])
                    if remove_missing_union
                        b[i] = hcat(b[i], DataFrame(Symbol(par) => convert(Array{Float64},
                        x[Symbol(par)])[:, 1]))
                    else
                        b[i] = hcat(b[i], DataFrame(Symbol(par) => x[Symbol(par)][:,1]))
                    end
                end
            end
        end
    end
    return b
end

DataFrames.DataFrame(cdfs::Vector{<:ChainDataFrame}) = map(DataFrame, cdfs)
function DataFrames.DataFrame(cdf::ChainDataFrame)
    colnames = collect(keys(cdf.nt))
    cols = collect(values(cdf.nt))

    return DataFrame(cols, colnames)
end