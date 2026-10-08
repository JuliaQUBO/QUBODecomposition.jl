# SPDX-License-Identifier: MPL-2.0
# Check all source Markdown, README and example instructions offline. Documenter
# validates @ref targets, manual anchors and rendered source/API links during build.
root = dirname(@__DIR__)
paths = [joinpath(root, "README.md"), joinpath(root, "CONTRIBUTING.md")]
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
        startswith(target, "https://") && continue
        startswith(target, "http://") && continue
        startswith(target, "#") && continue # Documenter validates manual anchors
        startswith(target, "@ref") && continue # Documenter resolves these
        isfile(normpath(joinpath(dirname(path), first(split(target, '#'))))) ||
            error("missing documentation target $target in $path")
    end
end
println("Documentation file links passed ($(length(paths)) Markdown files)")
