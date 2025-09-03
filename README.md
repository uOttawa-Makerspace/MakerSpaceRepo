# MakerRepo

A website where makers can publish projects. An initiative by the University of Ottawa's
[Centre for Entrepreneurship and Engineering Design (CEED)](https://engineering.uottawa.ca/CEED).

[![Actions Status](https://github.com/uOttawa-Makerspace/MakerSpaceRepo/workflows/CI/badge.svg)](https://github.com/uOttawa-Makerspace/MakerSpaceRepo/actions)

[![Build Status](https://travis-ci.com/uOttawa-Makerspace/MakerSpaceRepo.svg?branch=master)](https://travis-ci.com/uOttawa-Makerspace/MakerSpaceRepo)

## New developer setup

You'll need Ruby, PostgreSQL, and NodeJS to run the website locally. Then you'll need the master encryption key `config/master.key` and a database backup (referred to as `msr-backup.bak`) to properly launch the website locally.

### Windows

Windows developers need to [install Ubuntu on WSL](https://learn.microsoft.com/en-us/windows/wsl/install) then follow the Ubuntu-specific instructions below inside the WSL environment.

```bash
wsl --install -d Ubuntu
```

**Note**: When cloning the repository in step 6, make sure to not clone it within the `/mnt` directory as this directory is shared with windows and may cause performance issues.

### macOS

1. [Install Homebrew if not already installed](https://brew.sh/)
2. Install external dependencies and libraries
   ```bash
   brew install postgresql@17 libpq imagemagick
   ```
3. Start PostgreSQL and access a PostgreSQL shell
   ```bash
   brew services start postgresql
   psql -U postgres
   ```
4. Run the following commands in a PostgreSQL shell to create a user named 'postgres' just for local development:
   ```SQL
   ALTER USER "postgres" WITH PASSWORD 'postgres';
   CREATE DATABASE makerspacerepo;
   \c makerspacerepo
   \i ./path/to/msr-backup.bak
   exit
   ```
5.
