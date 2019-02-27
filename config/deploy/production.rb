role :app, %w{deploy@server.makerepo.com}
role :web, %w{deploy@server.makerepo.com}
role :db,  %w{deploy@server.makerepo.com}

set :default_env, { 'PASSENGER_INSTANCE_REGISTRY_DIR' => '/var/www/makerrepo/passenger_instance_registry' }
