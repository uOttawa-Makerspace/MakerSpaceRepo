# Puma can serve each request in a thread from an internal thread pool.
# Matches default ActiveRecord pool size.
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
threads threads_count, threads_count

# Specifies the `port` that Puma will listen on (default 3000).
port ENV.fetch("PORT") { 3000 }

# Specifies the `environment` that Puma will run in.
environment ENV.fetch("RAILS_ENV") { "development" }

# Specifies the number of `workers` in clustered mode.
workers ENV.fetch("WEB_CONCURRENCY") { 2 }

# Preload app before forking workers for Copy-On-Write memory savings
preload_app!

# Disconnect database connections before forking workers
before_fork do
  ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord)
end

# Reconnect ActiveRecord inside worker processes
before_worker_boot do
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
end

# Allow puma to be restarted by `rails restart` command.
plugin :tmp_restart

# Run Solid Queue inside Puma ONLY in development.
# In staging/production, Solid Queue runs in a dedicated Docker worker container.
if ENV["SOLID_QUEUE_IN_PUMA"] == "true" || ENV["RAILS_ENV"] == "development" || ENV["RAILS_ENV"] == "production"
  plugin :solid_queue
end