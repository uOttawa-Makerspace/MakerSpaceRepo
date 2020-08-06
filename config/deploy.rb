# frozen_string_literal: true

set :application, 'MakerRepo'
set :repo_url, 'https://github.com/uOttawa-Makerspace/MakerSpaceRepo.git'
set :rbenv_type, :user
set :rbenv_ruby, '2.5.3'
set :linked_files, %w{config/master.key}
set :linked_files, fetch(:linked_files, []).push('config/database.yml', 'config/secrets.yml')
set :linked_dirs, fetch(:linked_dirs, []).push('bin', 'log', 'tmp/pids', 'tmp/cache', 'tmp/sockets', 'vendor/bundle', 'public/system', 'certs', 'node_modules', 'public/packs')
set :default_env, { 'PASSENGER_INSTANCE_REGISTRY_DIR' => '/var/passenger_instance_registry' }

before "deploy:assets:precompile", "deploy:yarn_install"
namespace :deploy do
  desc "Run rake yarn install"
  task :yarn_install do
    on roles(:web) do
      within release_path do
        execute("cd #{release_path} && yarn install --silent --no-progress --no-audit --no-optional")
      end
    end
  end
end