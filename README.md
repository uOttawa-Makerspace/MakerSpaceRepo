## Rails 4.2

## Ruby 2.3.4

## Initial setup of postgresql database in linux
### Install libpq
```bash
sudo apt-get install libpq-dev
```

### Run bundle install
```bash
bundle install
```

### Install postgresql server
```bash
sudo apt-get install postgresql
```

### Set the password for postgres user
In a postgresql shell run the following query:
```SQL
ALTER USER "postgres" WITH PASSWORD 'postgres';
```

### Create the database
In a postgresql shell run the following query:
```SQL
CREATE DATABASE makerspacerepo;
```

### rake db setup
run the following command in a bash shell in the same directory as Rakefile (main project directory)
```bash
rake db:setup
```

### Run all tests to load clean fixtures in the database
Fixtures are dummy instances of models for testing and development
```bash
bundle exec rake
```

### Fire up the rails server with:
```bash
rails s
```
