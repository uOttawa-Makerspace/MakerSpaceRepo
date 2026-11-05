# frozen_string_literal: true

# Keeps the repository zip cache within its size cap and free-space floor, and removes partial zips and old
# repo_file* temporary files. Only cached or derived files are touched (Repository::ZipCache).
class RepositoryZipCacheCleanupJob < ApplicationJob
  queue_as :default

  def perform
    Repository::ZipCache.cleanup!
  end
end
