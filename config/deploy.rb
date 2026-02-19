# frozen_string_literal: true

set :application, 'MakerRepo'
set :repo_url, 'https://github.com/uOttawa-Makerspace/MakerSpaceRepo.git'
set :rbenv_type, :user
# set :rbenv_ruby, '3.4.7'

set :linked_files, %w[config/master.key]
set :linked_files, fetch(:linked_files, []).push('config/secrets.yml')
set :linked_dirs,
    fetch(:linked_dirs, []).push(
      'log',
      'tmp/pids',
      'tmp/cache',
      'tmp/sockets',
      'vendor/bundle',
      'public/system',
      'certs',
      'node_modules',
      'public/packs'
    )

# set :puma_user, 'deploy'
# puma:enable tries to enable lingering but that needs a sudo password. Disable
# since we already have it enabled on servers
set :puma_enable_lingering, false

# We seem to be hitting an IO bug because yjit is lazy-enabled. Startup ruby
# with YJIT enabled immediately
# NOTE: This doesn't have an effect because systemd starts a separate user
# session and does not load .profile either
set :default_env, { 'RUBYOPT' => '--yjit' }

# before "deploy:assets:precompile", "deploy:yarn_install"
# namespace :deploy do
#   desc "Run rake yarn install"
#   task :yarn_install do
#     on roles(:web) do
#       within release_path do
#         execute("cd #{release_path} && yarn install --silent --no-progress --no-audit --no-optional")
#       end
#     end
#   end
# end
