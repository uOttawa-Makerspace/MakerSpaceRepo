# MakerRepo

A website where makers can publish projects. An initiative by the University of Ottawa's
[Centre for Entrepreneurship and Engineering Design (CEED)](https://engineering.uottawa.ca/CEED).

[![Actions Status](https://github.com/uOttawa-Makerspace/MakerSpaceRepo/workflows/CI/badge.svg)](https://github.com/uOttawa-Makerspace/MakerSpaceRepo/actions)

## New developer setup

You'll need Ruby via rbenv, PostgreSQL, and NodeJS via NVM to run the website locally.
Then you'll need the master encryption key `config/master.key` and a database backup (referred to as `msr-backup.bak` here) to have a proper local installation.

### Windows

Windows developers need to [install WSL](https://learn.microsoft.com/en-us/windows/wsl/install) then follow the Linux-specific instructions below inside the WSL environment.

```powershell
wsl --install -d Ubuntu # Or any distro
```

**Note**: When cloning the repository make sure to not clone it within the `/mnt` directory, as this directory is shared with windows and may cause performance issues.

### macOS

macOS developers need to install [Homebrew if not already installed](https://brew.sh/). Homebrew is a macOS package manager, similar to `apt` or `pacman`. It also manages services, used to start PostgreSQL. To start the database after installation, run `brew services start postgresql`

### General instructions

1. Install external dependencies and libraries.
   For macOS:

   ```bash
   brew install postgresql@17 libpq imagemagick
   brew services start postgresql
   ```

   For Linux:

   ```bash
   sudo apt-get install postgresql libpq-dev imagemagick
   sudo systemctl enable postgresql --now
   ```

2. Clone and install required ruby version

   **IMPORTANT:** [Make sure that you have all ruby-build requirements present](https://github.com/rbenv/ruby-build/wiki#suggested-build-environment), before starting Ruby compilation, or else you'll get an error after a long wait. Note that the requirements are different for each system.

   ```bash
   # Install rbenv
   curl -fsSL https://github.com/rbenv/rbenv-installer/raw/HEAD/bin/rbenv-installer | bash
   # Clone repository using SSH if you're planning to make commits
   git clone ssh://git@github.com:uOttawa-Makerspace/MakerSpaceRepo.git
   cd ./Install
   # MakerSpaceRepo version in .ruby-version
   rbenv install
   # Install ruby dependencies
   bundler install
   # Install foreman
   gem install foreman
   ```

3. [Install NVM](https://github.com/nvm-sh/nvm), Node, then Yarn.
   ```bash
   curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
   nvm install 24 --lts
   nvm use 24
   npm install -g yarn
   yarn install
   ```
4. Make SAML certificates
   ```bash
   mkdir certs
   openssl req -x509 -newkey rsa:4096 -keyout certs/saml.key -out certs/saml.crt -days 365 -nodes
   ```
5. Move the master credentials key into config

   ```bash
   mv ~/Downloads/master.key config/master.key
   ```

6. Start PostgreSQL and access a PostgreSQL shell. When inside nano, press `Ctrl-W` to start search.

   ```bash
   # Find the postgres config file and open in nano
   sudo nano $(sudo -u postgres -i psql -c 'SHOW config_file' | sed -n '3p')
   sudo systemctl restart postgresql
   psql -U postgres
   # or
   sudo -u postgres -i psql
   ```

   Set the password for the `postgres` user to `postgres`. Then load a staging database backup

   ```SQL
   ALTER USER "postgres" WITH PASSWORD 'postgres';
   CREATE DATABASE makerspacerepo;
   \c makerspacerepo
   \i ./path/to/msr-backup.bak
   exit
   ```

7. Setup development and test databases
   ```bash
   rake db:setup
   RAILS_ENV=test rake db:setup
   ```
8. Run tests from the project root. If this doesn't immediately fail, you should have a functioning backend
   ```bash
   rake
   ```
9. Start the server
   ```bash
   foreman start -f Procfile.dev
   ```

Then visit http://localhost:3000 to view the home page locally.

**NOTE:** You'll receive a lot of AWS errors because you're accessing production images using development credentials.

### Background jobs in development

Development does not use the same job backend as staging and production.

- **Development** sets `config.active_job.queue_adapter = :async` (`config/environments/development.rb`). A job queued with `perform_later` runs on a thread inside the process that queued it (the web server or the console). Nothing is written to the queue database, there is no retry after a restart, and a job still running when the process stops is lost. `config/recurring.yml` has no `development` block, so no scheduled task runs on its own.
- **Staging and production** use Solid Queue (`config/application.rb`). Jobs are stored in the queue database and run by the `worker` container (`bundle exec rake solid_queue:start`), which also runs the schedule in `config/recurring.yml`.
- **Tests** use the `:test` adapter (`config/environments/test.rb`).

The Solid Queue supervisor that `Procfile.dev` (the `worker` line) and Puma (with `SOLID_QUEUE_IN_PUMA=true`, as the devcontainer sets) start in development has nothing to run while the adapter is `:async`.

To run a scheduled task by hand, open a console (`bin/rails console`) and call `perform_now` on the task's `class:` from `config/recurring.yml`, or paste its `command:`.

To try a change against Solid Queue itself (retries, concurrency limits, the `/solid_queue` dashboard):

1. Create the queue database once: `bin/rails db:prepare` (it loads `db/queue_schema.rb` into `makerspacerepo_queue_development`).
2. In your local copy only, change the adapter line in `config/environments/development.rb` to `:solid_queue`. Do not commit that change.
3. Start the supervisor with `bin/jobs` (or the `worker` line of `Procfile.dev`), and start the web server as usual.
4. To run scheduled tasks too, copy the tasks you need into a `development:` block in `config/recurring.yml`, locally and uncommitted.

## Deployment

Deployment is handled by Docker Compose through the `CI & Deploy` GitHub Actions workflow (`.github/workflows/main.yml`). After the tests and security checks pass, the workflow builds the Docker image, publishes it to GitHub Container Registry, then connects to the server over SSH, copies the matching `docker-compose.staging.yml` or `docker-compose.production.yml`, pulls the new image and restarts the containers. Pushing to the `staging` branch deploys to the staging server. Pushing to the `master` branch deploys to the production server.
