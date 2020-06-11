# MakerRepo
A website where makers can publish projects. An initiative by the University of Ottawa's
[Centre for Entrepreneurship and Engineering Design (CEED)](https://engineering.uottawa.ca/CEED).

[![Build Status](https://travis-ci.org/uOttawa-Makerspace/MakerSpaceRepo.svg?branch=master)](https://travis-ci.org/uOttawa-Makerspace/MakerSpaceRepo)

## New Developer Setup
You must have Git and Ruby 2.5.3 installed. See [the Ruby website](https://www.ruby-lang.org/) for more information.
If you are on Linux or macOS, we recommend that you use [rbenv](https://github.com/rbenv/rbenv) to manage Ruby installations on your computer.

### Windows
Coming soon.

### macOS
Coming soon.

### Debian-based Linux distributions
1. Install PostgreSQL and libpq-dev if they are not already installed:
   ```bash
   $ sudo apt-get install postgresql libpq-dev
   ```

2. Run the following commands in a PostgreSQL shell to allow MakerRepo to connect:
   ```SQL
   ALTER USER "postgres" WITH PASSWORD 'postgres';
   CREATE DATABASE makerspacerepo;
   ```

3. Clone this repository and go into it:
   ```bash
   $ git clone git@github.com:uOttawa-Makerspace/MakerSpaceRepo
   $ cd MakerSpaceRepo
   ```

4. Install gems:
   ```bash
   $ bundle install
   ```
   
5. Create X.509 certificates for SAML:
   ```
   $ openssl req -x509 -newkey rsa:4096 -keyout certs/saml.key -out certs/saml.crt -days 365 -nodes
   ```
   
6. Set up the database:
   ```bash
   $ rake db:setup
   ```
   
7. Run all tests to load clean fixtures into the database (fixtures are dummy instances of models for testing and development):
   ```bash
   $ bundle exec rake
   ```

8. Start the Rails server:
   ```bash
   $ rails s
   ```

Happy coding!

## Deployment
Deployment is managed by [Capistrano](https://github.com/capistrano/capistrano). To deploy to production, run the following command:
```bash
$ bundle exec cap production deploy
```
