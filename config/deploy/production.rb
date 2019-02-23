role :app, %w{deploy@138.197.167.242}
role :web, %w{deploy@138.197.167.242}
role :db,  %w{deploy@138.197.167.242}

set :default_env, { 'PASSENGER_INSTANCE_REGISTRY_DIR' => '/var/www/makerrepo/passenger_instance_registry' }