role :app, %w{deploy@server.makerepo.com}
role :web, %w{deploy@server.makerepo.com}
role :db,  %w{deploy@server.makerepo.com}

set :repo_url, 'https://github.com/nicoco007/MakerSpaceRepo.git'
set :branch, 'develop'
set :deploy_to, '/var/www/makerrepo-staging'