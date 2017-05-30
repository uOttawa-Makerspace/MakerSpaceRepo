# config valid only for current version of Capistrano
lock '3.6.1'

#TODO update this to the final IP
server '159.203.28.176', port: 22, roles: [:web, :app, :db], primary: true

set :application, 'Makerepo'
set :repo_url,    'https://github.com/uOttawa-Makerspace/MakerSpaceRepo'
set :user,        'deploy'

set :branch, 'master'
# Don't change these unless you know what you're doing
set :pty,             true
set :use_sudo,        false
set :stage,           :production
set :deploy_via,      :remote_cache
set :deploy_to,       "/home/#{fetch(:user)}/apps/#{fetch(:application)}"
set :ssh_options,     { forward_agent: true, user: fetch(:user), keys: %w(~/.ssh/id_rsa.pub) }

namespace :deploy do
  desc "Make sure local git is in sync with remote."
  task :check_revision do
    on roles(:app) do
      unless `git rev-parse HEAD` == `git rev-parse origin/master`
        puts "WARNING: HEAD is not the same as origin/master"
        puts "Run `git push` to sync changes."
        exit
      end
    end
  end

  desc 'Initial Deploy'
  task :initial do
    on roles(:app) do
      before 'deploy:restart'
      invoke 'deploy'
    end
  end

  before :starting,     :check_revision
  after  :finishing,    :compile_assets
  after  :finishing,    :cleanup
  after  :finishing,    :restart
end

# Default value for :linked_files is []
append :linked_files, 'config/secrets.yml'


# Default value for default_env is {}
# set :default_env, { path: "/opt/ruby/bin:$PATH" }

set :unicorn_config_path, 'config/unicorn.rb'
after 'deploy:publishing', 'deploy:restart'
namespace :deploy do
  task :restart do
    invoke 'unicorn:restart'
  end
end
