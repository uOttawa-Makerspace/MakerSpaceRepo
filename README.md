README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...


## Initial DB setup
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
rake db:migrate
```

