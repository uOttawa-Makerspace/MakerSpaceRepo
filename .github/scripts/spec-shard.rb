#!/usr/bin/env ruby
# frozen_string_literal: true

# Prints the spec files of one CI shard, one per line:
#
#   .github/scripts/spec-shard.rb 2/3
#
# The split is parallel_tests' own grouper, the same one bin/parallel_rspec uses for its
# workers: by the runtimes in tmp/parallel_runtime_rspec.log when it covers enough files,
# else by file size. Every shard computes all groups from the same checkout and the same
# log, so the shards are disjoint and together hold every spec file. The script checks that
# against its own list of spec/**/*_spec.rb and stops with an error when it does not hold.
require "bundler/setup"
require "parallel_tests"
require "parallel_tests/rspec/runner"

index, count = ARGV.fetch(0, "").split("/", 2).map { |n| Integer(n, exception: false) }
abort "usage: spec-shard.rb INDEX/COUNT, for example 2/3" unless index && count && index.between?(1, count)

runner = ParallelTests::RSpec::Runner
folders = [runner.default_test_folder]
every_file = Dir.glob("#{folders.first}/**/*_spec.rb").sort
# bin/parallel_rspec passes the list unquoted, so a path must not split or glob
abort "spec-shard: a spec file path contains whitespace or * ? [" if every_file.any? { |file| file.match?(/[\s*?\[]/) }

# The rule the parallel_tests CLI applies when --group-by is not given: by runtime when the
# log has times for more than two thirds of the spec files, else by file size.
log = runner.runtime_log
recorded = File.file?(log) ? File.readlines(log, chomp: true).map { |line| line.rpartition(":").first } : []
group_by = (recorded & every_file).size * 1.5 > every_file.size ? :runtime : :filesize

groups = runner.tests_in_groups(folders, count, quiet: true, group_by: group_by)
assigned = groups.flatten

abort "spec-shard: the #{count} groups do not hold every spec file exactly once" unless assigned.sort == every_file
abort "spec-shard: shard #{index}/#{count} has no spec files" if groups[index - 1].empty?

puts groups[index - 1]
