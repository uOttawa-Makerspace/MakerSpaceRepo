set :application, 'MakerRepo'
set :repo_url, 'https://github.com/nicoco007/MakerSpaceRepo.git'
set :branch, 'new-server'
set :rbenv_ruby, '2.3.1'
set :deploy_to, '/var/www/makerrepo'
set :linked_files, fetch(:linked_files, []).push('config/database.yml', 'config/secrets.yml')
set :linked_dirs, fetch(:linked_dirs, []).push('bin', 'log', 'tmp/pids', 'tmp/cache', 'tmp/sockets', 'vendor/bundle', 'public/system', 'certs')