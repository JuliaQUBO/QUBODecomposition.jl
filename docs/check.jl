# SPDX-License-Identifier: MPL-2.0
# Check all source Markdown, README and example instructions offline. Documenter
# validates @ref targets, manual anchors and rendered source/API links during build.
root = dirname(@__DIR__)
repo_file_prefix = "https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/"
paths = [joinpath(root, "README.md"), joinpath(root, "CONTRIBUTING.md"), joinpath(root, "RELEASE.md"), joinpath(root, "CHANGELOG.md")]
for directory in (joinpath(@__DIR__, "src"), joinpath(root, "examples"))
    for (folder, _, files) in walkdir(directory), file in files
        endswith(file, ".md") && push!(paths, joinpath(folder, file))
    end
end
for path in paths
    text = read(path, String)
    isempty(text) && error("empty documentation: $path")
    for link in eachmatch(r"\]\(([^)]+)\)", text)
        target = link.captures[1]
        directory = dirname(path)
        if startswith(target, repo_file_prefix)
            # Hosted source links still refer to files owned by this checkout.
            target = chopprefix(target, repo_file_prefix)
            directory = root
        elseif startswith(target, "https://") || startswith(target, "http://")
            continue
        end
        startswith(target, "#") && continue # Documenter validates manual anchors
        startswith(target, "@ref") && continue # Documenter resolves these
        isfile(normpath(joinpath(directory, first(split(target, '#'))))) ||
            error("missing documentation target $target in $path")
    end
end
println("Documentation file links passed ($(length(paths)) Markdown files)")
