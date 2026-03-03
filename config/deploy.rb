# frozen_string_literal: true

set :application, "MakerRepo"
set :repo_url, "https://github.com/uOttawa-Makerspace/MakerSpaceRepo.git"
set :rbenv_type, :user

set :linked_files, %w[config/master.key config/secrets.yml]
set :linked_dirs,
    fetch(:linked_dirs, []).push(
      "log",
      "tmp/pids",
      "tmp/cache",
      "tmp/sockets",
      "vendor/bundle",
      "public/system",
      "certs",
      "node_modules",
      "public/vite"
    )


# set :puma_user, 'deploy'
# puma:enable tries to enable lingering but that needs a sudo password. Disable
# since we already have it enabled on servers
set :puma_enable_lingering, false

# We seem to be hitting an IO bug because yjit is lazy-enabled. Startup ruby
# with YJIT enabled immediately
# NOTE: This doesn't have an effect because systemd starts a separate user
# session and does not load .profile either
set :default_env, { "RUBYOPT" => "--yjit" }

# ---------------------------------------------------------------------------
# Skip asset precompilation when no asset sources changed
# ---------------------------------------------------------------------------
set :assets_dependencies, %w[
  app/javascript
  app/assets
  vendor/assets
  lib/assets
  Gemfile.lock
  package.json
  yarn.lock
  vite.config.ts
  vite.config.js
  config/vite.json
]

namespace :deploy do
  namespace :assets do
    desc "Skip precompile if no asset files changed since last deploy"
    task :skip_if_unchanged do
      on roles(:web) do
        within repo_path do
          previous = capture(
            "cat #{current_path}/REVISION 2>/dev/null || echo ''"
          ).strip
          current = fetch(:current_revision) ||
                    capture(:git, "rev-parse", "HEAD").strip

          if !previous.empty? && previous != current
            paths = fetch(:assets_dependencies).join(" ")
            diff = capture(
              :git, "diff", "--name-only",
              previous, current, "--", paths
            ).strip

            if diff.empty?
              info "No asset changes detected — skipping precompilation"
              Rake::Task["deploy:assets:precompile"].clear_actions
            else
              info "Asset changes detected:\n#{diff}"
            end
          end
        end
      end
    end
  end
end

before "deploy:assets:precompile", "deploy:assets:skip_if_unchanged"

# ---------------------------------------------------------------------------
# Batch symlink creation into single SSH commands
# ---------------------------------------------------------------------------
Rake::Task["deploy:symlink:linked_dirs"].clear_actions
Rake::Task["deploy:symlink:linked_files"].clear_actions

namespace :deploy do
  namespace :symlink do
    task :linked_dirs do
      next unless any?(:linked_dirs)

      on release_roles(:all) do
        # Create all parent directories in one command
        parents = fetch(:linked_dirs).map { |dir|
          release_path.join(dir).dirname.to_s
        }.uniq

        execute(:mkdir, "-p", *parents)

        # Batch all rm + ln into a single SSH call
        batch = fetch(:linked_dirs).map { |dir|
          target = shared_path.join(dir)
          link   = release_path.join(dir)
          "rm -rf #{link} && ln -s #{target} #{link}"
        }.join(" && ")

        execute(batch)
      end
    end

    task :linked_files do
      next unless any?(:linked_files)

      on release_roles(:all) do
        parents = fetch(:linked_files).map { |file|
          release_path.join(file).dirname.to_s
        }.uniq

        execute(:mkdir, "-p", *parents)

        batch = fetch(:linked_files).map { |file|
          target = shared_path.join(file)
          link   = release_path.join(file)
          "rm -f #{link} && ln -s #{target} #{link}"
        }.join(" && ")

        execute(batch)
      end
    end
  end
end