# SPDX-License-Identifier: MPL-2.0
# Source documentation is plain Markdown. Validate package-relative file links;
# public URL evidence belongs to the PR and does not gate offline docs checks.
root = dirname(@__DIR__)
for path in [joinpath(root, "README.md"); filter(p -> endswith(p, ".md"), readdir(@__DIR__; join=true))]
    text = read(path, String)
    isempty(text) && error("empty documentation: $path")
    for link in eachmatch(r"\]\(([^)]+)\)", text)
        target = link.captures[1]
        startswith(target, "https://") && continue
        startswith(target, "#") && continue
        isfile(normpath(joinpath(dirname(path), first(split(target, '#'))))) ||
            error("missing documentation target $target in $path")
    end
end
println("Documentation file links passed")
