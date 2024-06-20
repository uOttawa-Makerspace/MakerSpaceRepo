#!/bin/bash

set -e

DB="makerspacerepo"
DB_USER="postgres"

function main {
  if [ -z "$1" ]; then
    echo "please pass in filename of db dump";
    exit -1;
  fi

  echo "WARNING: This will delete all current db data and replace it with the backup"
  read -p "Do you want to continue? (yN): " yn
  case $yn in
    [Yy]* )
      drop_and_restore $1
      ;;
  esac
}

function drop_and_restore {
  dropdb -U $DB_USER -W -p 5432 -h localhost $DB
  createdb -U $DB_USER -W -p 5432 -h localhost $DB
  psql -U $DB_USER -W -p 5432 -h localhost --set ON_ERROR_STOP=on --single-transaction $DB < $1
}

main $1
