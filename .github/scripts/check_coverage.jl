# SPDX-License-Identifier: MPL-2.0
# Fail before upload if the report is empty, unrelated, or has no executed source.
function check_coverage()
    report = read("lcov.info", String)
    files = String[]
    executed = 0
    measured = 0
    for line in eachline(IOBuffer(report))
        if startswith(line, "SF:")
            path = replace(chopprefix(line, "SF:"), '\\' => '/')
            startswith(path, "src/") || error("coverage outside package source: $path")
            isfile(path) || error("coverage source does not exist: $path")
            push!(files, path)
        elseif startswith(line, "DA:")
            fields = split(chopprefix(line, "DA:"), ',')
            hits = parse(Int, fields[2])
            measured += 1
            executed += hits > 0
        end
    end
    isempty(files) && error("report contains no package source files")
    executed > 0 || error("report contains no executed package source lines")
    println("Package source coverage: $executed / $measured measured lines in $(length(files)) files")
end

check_coverage()
