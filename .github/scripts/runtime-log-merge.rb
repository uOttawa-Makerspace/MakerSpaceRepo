#!/usr/bin/env ruby
# frozen_string_literal: true

# Merges parallel_tests runtime logs ("path:seconds" per line) into one, printed to stdout:
#
#   .github/scripts/runtime-log-merge.rb BASE_LOG PART_LOG...
#
# A later file wins for a path it lists, so each CI shard's fresh times replace the times
# the run started from, and files a shard did not record keep their earlier time. Paths
# that are no longer spec files in this checkout are dropped, and a leading ./ is removed.
# Missing logs are skipped.
runtimes = {}
ARGV.select { |log| File.file?(log) }.each do |log|
  File.foreach(log, chomp: true) do |line|
    path, _, seconds = line.rpartition(":")
    path = path.delete_prefix("./")
    runtimes[path] = seconds if path.end_with?("_spec.rb") && Float(seconds, exception: false) && File.file?(path)
  end
end

runtimes.sort.each { |path, seconds| puts "#{path}:#{seconds}" }
