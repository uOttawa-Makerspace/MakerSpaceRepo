# Useful Terminal Commands

1. Display all HTTP routes (useful if you can't find the HTML file for a page)

```bash
rails routes
```

2. Create a Database Migration

```bash
rails generate migration YOUR_MIGRATION_NAME
```

3. Connect to remote servers

```bash
# production server
ssh deploy@prod-server.makerepo.com

# staging server
ssh deploy@staging-server.makerepo.com

# Wiki server
ssh deploy@wiki-server.makerepo.com
```

4. Launch Rails Console (Dev Environment)

```bash
rails c -e development
```

If the console exits after each exception, try doing `$SAFE=0` first or place it in your `.pryrc` file

5. Launch Rails Console (Staging/Production Environment)

- **Note**: It is a good idea to create a [manual database backup](#create-a-database-backup) if you are using the console to create, modify, or delete data in the production environment
- Run the following after [connecting to remote servers](#connecting-to-remote-servers)

```bash
# production server
cd ~/../../var/www/makerrepo/current
bundle exec rails c -e production

# staging server
cd ~/../../var/www/makerrepo-staging/current
bundle exec rails c -e staging
```

6. Create a Database Backup in AWS (Production Environment)

```bash
cd ~

sh backup-db.sh
```
