role :app, %w{deploy@server.makerepo.com}
role :web, %w{deploy@server.makerepo.com}
role :db,  %w{deploy@server.makerepo.com}

set :branch, 'master'
set :deploy_to, '/var/www/makerrepo'