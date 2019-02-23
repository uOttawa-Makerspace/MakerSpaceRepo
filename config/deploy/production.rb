role :app, %w{makerrepo@138.197.167.242}
role :web, %w{makerrepo@138.197.167.242}
role :db,  %w{makerrepo@138.197.167.242}

set :default_env, { 'PASSENGER_INSTANCE_REGISTRY_DIR' => '/var/www/makerrepo/passenger_instance_registry' }