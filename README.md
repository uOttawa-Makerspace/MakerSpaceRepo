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

### run tests and load fixtures
fixtures create create active records for testing 
```bash
bundle exec rake
```

### Fire up solr with:
```bash
sunspot-solr start
```

### Fire up the rails server with:
```bash
rails s
```
