# MakerRepo

A website where makers can publish projects. An initiative by the University of Ottawa's
[Centre for Entrepreneurship and Engineering Design (CEED)](https://engineering.uottawa.ca/CEED).

[![Actions Status](https://github.com/uOttawa-Makerspace/MakerSpaceRepo/workflows/CI/badge.svg)](https://github.com/uOttawa-Makerspace/MakerSpaceRepo/actions)

[![Build Status](https://travis-ci.com/uOttawa-Makerspace/MakerSpaceRepo.svg?branch=master)](https://travis-ci.com/uOttawa-Makerspace/MakerSpaceRepo)

## New Developer Setup

### Windows

1. Open Powershell & Install WSL for Ubuntu

   ```bash
   wsl --install -d Ubuntu
   ```

2. Follow the [Debian-based Linux Distributions](#Debian-based-Linux-distributions) setup instructions using WSL.

- **Note**: When cloning the repository in step 6, make sure to not clone it within the `/mnt` directory as this directory is shared with windows and may cause performance issues.

### macOS

1. Install Homebrew if not already installed

   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

2. Install PostgreSQL and libpq-dev with homebrew:

   ```bash
   brew install postgresql@14 libpq
   ```

3. Start PostgreSQL & Access a PostgreSQL Shell

   ```bash
   brew services start postgresql@14
   psql -U postgres
   ```

4. Run the following commands in a PostgreSQL shell to allow MakerRepo to connect:

   ```SQL
   ALTER USER "postgres" WITH PASSWORD 'postgres';
   CREATE DATABASE makerspacerepo;
   exit
   ```

5. Install rbenv and Ruby 3.1.2
   ```bash
   brew install rbenv
   rbenv install 3.1.2
   ```
6. Install NVM and Node 18 LTS

   ```bash
   # Check to see if '.zshrc' is present in home directory
   cd ~
   ls -a

   # If '.zshrc' is not present, create .zshrc profile in home directory
   touch .zshrc

   # Install NVM
   curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash
   source .zshrc

   # Install Node 18 LTS
   nvm install 18 --lts
   ```

7. Clone this repository and go into it:

   ```bash
   git clone https://github.com/uOttawa-Makerspace/MakerSpaceRepo.git
   cd MakerSpaceRepo
   ```

8. Install gems:

   ```bash
   bundle install
   ```

9. Create X.509 certificates for SAML:

   ```bash
   mkdir certs
   openssl req -x509 -newkey rsa:4096 -keyout certs/saml.key -out certs/saml.crt -days 365 -nodes
   ```

10. Move the master credentials key into config (Ask for master.key file)

```bash
mv ~/Downloads/master.key config/master.key
```

11. Configure Postgres for port 5433, ctrl+w to search for port, replace 5432 with 5433.

```bash
# Locate configuration file
psql -U postgres -c 'SHOW config_file'

# edit configuration file and change port variable
nano <your configuration file location>
```

12. Set up the database:

```bash
rake db:setup
rake db:setup RAILS_ENV=test
```

13. Run all tests to load clean fixtures into the database (You will fail one test because you do not have wkhtmltopdf, you may optionally install it if it is compatible with your distro.):

```bash
bundle exec rake
```

14. Install yarn and yarn packages

```bash
npm install -g yarn
yarn install
```

15. Start the Rails server:

```bash
foreman start -f Procfile.dev
```

### Debian-based Linux distributions

1. Install PostgreSQL and libpq-dev if they are not already installed:

   ```bash
   sudo apt-get install postgresql libpq-dev git curl
   ```

2. Access a PostgreSQL Shell:

   ```bash
   sudo -i -u postgres psql
   ```

3. Run the following commands in a PostgreSQL shell to allow MakerRepo to connect:

   ```SQL
   ALTER USER "postgres" WITH PASSWORD 'postgres';
   CREATE DATABASE makerspacerepo;
   exit
   ```

4. Install rbenv and Ruby 3.1.2:

   ```bash
   curl -fsSL https://github.com/rbenv/rbenv-installer/raw/HEAD/bin/rbenv-installer | bash
   echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
   echo 'eval "$(rbenv init -)"' >> ~/.bashrc
   source ~/.bashrc
   rbenv install 3.1.2
   ```

5. Install NVM and Node 18 LTS:

   ```bash
   curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash
   export NVM_DIR="$HOME/.nvm"
   [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
   [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
   nvm install 18 --lts
   ```

6. Clone this repository and go into it:

- **Note**: For WSL users, make sure the repository isn't cloned within the `/mnt`directory
  ```bash
  git clone https://github.com/uOttawa-Makerspace/MakerSpaceRepo.git
  cd MakerSpaceRepo
  ```

7. Install gems:

   ```bash
   bundle install
   ```

8. Create X.509 certificates for SAML:

   ```bash
   mkdir certs
   openssl req -x509 -newkey rsa:4096 -keyout certs/saml.key -out certs/saml.crt -days 365 -nodes
   ```

9. Move the master credentials key into config (Ask for master.key file)

   ```bash
   mv ~/Downloads/master.key config/master.key
   ```

10. Configure Postgres for port 5433, ctrl+w to search for port, replace 5432 with 5433.

```bash
sudo nano $(sudo -u postgres psql -c 'SHOW config_file' | sed -n '3p')
sudo systemctl restart postgresql
```

11. Set up the database:

```bash
rake db:setup
rake db:setup RAILS_ENV=test
```

12. Run all tests to load clean fixtures into the database (You will fail one test because you do not have wkhtmltopdf, you may optionally install it if it is compatible with your distro.):

```bash
bundle exec rake
```

13. Install yarn and yarn packages

```bash
npm install -g yarn
yarn install
```

14. Start the Rails server:

```bash
foreman start -f Procfile.dev
```

Note: You will want to change the remote origin from https to an ssh source, git@github.com:uOttawa-Makerspace/MakerSpaceRepo.git, in order to push.

Happy coding!
