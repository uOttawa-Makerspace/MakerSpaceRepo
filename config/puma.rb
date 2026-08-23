# Puma thread configuration
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 10 }
threads threads_count, threads_count

# Port & environment
port ENV.fetch("PORT") { 3000 }
environment ENV.fetch("RAILS_ENV") { "staging" }

# Clustered mode: 2 worker processes to leverage 6GB RAM
workers ENV.fetch("WEB_CONCURRENCY") { 2 }

# Preload app for Copy-On-Write memory savings
preload_app!

plugin :tmp_restart

# Run Solid Queue inside Puma ONLY in local development or if explicitly requested.
# In staging/production, it runs in the separate Docker worker container.
if ENV["SOLID_QUEUE_IN_PUMA"] == "true" || (ENV["RAILS_ENV"] == "development" && !ENV.key?("SOLID_QUEUE_IN_PUMA"))
  plugin :solid_queue
end