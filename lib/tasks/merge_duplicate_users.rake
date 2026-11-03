require Rails.root.join("lib/learning_module_track_merge")

# Finds all duplicated users and deletes them. This also doubles as a quick test
# for destroying user records.

namespace :users do
  desc 'Find and merge all duplicated user records. Uses the record with the
  most amount of associations to assume which record is the most-frequently
  used'

  task :merge_duplicates, [] => :environment do
    duplicated_emails = email_tally.keys

    puts "#{duplicated_emails.count} duplicated emails found."

    merged_users = []
    duplicated_emails.each do |email|
      username = merge_duplicated_email(email)
      merged_users << { username: username, email: email }
    end

    # Writes this to root by default
    File.write('merged_emails_list.json', merged_users.to_json)
    puts "Wrote merged_emails_list.json to #{Dir.pwd}"

    duplicated_usernames = username_tally.keys
    puts "After email merge, there are #{duplicated_usernames.count} usernames duplicated."

    renamed_users = []
    duplicated_usernames.each do |username|
      renamed_users << rename_duplicated_username(username)
    end

    File.write('renamed_username_list.json', renamed_users.to_json)
    puts "renamed_username_list.json written to #{Dir.pwd}"
  end

  task :notify_modified_users, [] => :environment do
    # I just like json, could've been csv
    renamed_users = JSON.parse(File.read('renamed_username_list.json'))
    renamed_users
      # .take(4)
      .each do |user|
        TaskMailer
          .with(
            email: user['email'],
            previous_username: user['previous_username'],
            new_username: user['new_username']
          )
          .renamed_user
          .deliver_later
      end
    puts 'Sent out emails for renamed usernames'

    merged_emails = JSON.parse(File.read('merged_emails_list.json'))
    merged_emails
      # .take(4)
      .each do |user|
        TaskMailer
          .with(email: user['email'], username: user['username'])
          .merged_user
          .deliver_later
      end
  end

  desc 'Count users duplicated by email'
  task :count_duplicated_emails, [] => :environment do
    duplicated_emails = email_tally.keys

    User
      .unscope(where: :deleted)
      .where('lower(email) in (?)', duplicated_emails)
      .pluck(:username, :email, :created_at)
      .sort_by(&:last)
      .each do |username, email, created_at|
        puts "#{username}, #{email}, #{created_at.to_fs(:long)}"
      end

    puts "There are #{duplicated_emails.count} duplicated emails in total"
  end

  task :count_duplicated_usernames, [] => :environment do
    duplicated = username_tally.keys
    duplicated.each do |username|
      User
        .unscope(where: :deleted)
        .where('lower(username) ilike ?', username)
        .pluck(:username, :email, :created_at)
        .sort_by(&:last)
        .each do |username, email, created_at|
          puts "#{username}, #{email}, #{created_at.to_fs(:long)}"
        end
    end

    puts "There are #{duplicated.count} duplicated usernames in total"
  end

  private

  def email_tally
    User
      .all
      .unscope(where: :deleted)
      .pluck(:email)
      .map(&:downcase)
      .sort
      .tally
      .filter { |k, v| v > 1 }
  end

  def username_tally
    User
      .all
      .unscope(where: :deleted)
      .pluck(:username)
      .map(&:downcase)
      .sort
      .tally
      .filter { |k, v| v > 1 }
  end

  def rename_duplicated_username(username)
    users =
      User.unscope(where: :deleted).where('lower(username) ilike ?', username)

    # Sanity check
    if users.count == 1
      raise "No duplicate records found for username #{username}. probably a deleted user?"
    end

    # Check if there's one and only one user deleted
    if users.where(deleted: false) == 1
      # the rest are deleted users, change those instead
      users = users.where(deleted: true)
    end

    changelog = {}

    suffixes = (111..999).to_a
    users
      .zip(suffixes.sample(users.count))
      .each do |user, suffix|
        user.username = user.username + suffix.to_s
        puts "#{user.username_was} => #{user.username}"
        changelog = {
          email: user.email,
          previous_username: user.username_was,
          new_username: user.username
        }
        user.save!
      end

    changelog
  end

  def merge_duplicated_email(email)
    users =
      User
        .where('lower(email) like ?', email)
        .unscope(where: :deleted)
        .sort_by { |u| count_associations(u) }
    if users.count == 1
      raise "Duplicated records were not found again for email #{email}. Probably a deleted user exists?"
    end
    puts "#{email} had #{users.count} records"
    # Prefer staff roles
    primary = users.find(&:staff?) || users.last # or most associations
    duplicates = users.excluding(primary)

    duplicates.each do |duplicate|
      ActiveRecord::Base.transaction { merge_record(primary, duplicate) }
    end

    # Return the username left at the end
    primary.username
  end

  def merge_record(primary, duplicate)
    # https://api.rubyonrails.org/classes/ActiveRecord/Reflection/ClassMethods.html#method-i-reflect_on_all_associations
    # Reflect on all table-level associations
    # User.reflect_on_all_associations.map(&:macro).uniq
    merge_shared_tracks(primary, duplicate)
    discard_rows_primary_already_has(primary, duplicate)
    # We're going to hit all possible assocs, need to make sure there's a record to update
    User.reflect_on_all_associations.each do |assoc|
      case assoc.macro
      when :has_many
        merge_has_many_association(primary, duplicate, assoc)
      when :has_one
        merge_has_one_association(primary, duplicate, assoc)
      when :has_and_belongs_to_many
        merge_habtm_association(primary, duplicate, assoc)
      when :belongs_to
        # No action
        next
      else
        raise "Unexpected assocation macro #{assoc.macro}"
      end
    end

    repoint_remaining_user_references(primary, duplicate)
    duplicate.destroy!
  end

  # Tracks of a module both users have are merged into the primary's track by the same
  # rule the unique-index migration uses (best status, newest SCORM state, earliest
  # created_at, latest updated_at), so nothing the duplicate recorded is lost. The
  # primary's row is the one kept; tracks only the duplicate has are moved afterwards.
  def merge_shared_tracks(primary, duplicate)
    connection = ActiveRecord::Base.connection
    LearningModuleTrackMerge.merge!(
      connection,
      group: %w[learning_module_id],
      where: ActiveRecord::Base.sanitize_sql_array(['user_id IN (?)', [primary.id, duplicate.id]]),
      keeper_order: ActiveRecord::Base.sanitize_sql_array(['(user_id = ?) DESC, created_at, id', primary.id])
    )
  end

  # Foreign keys to users that the database does not clear by itself (no action or restrict).
  def user_reference_columns
    connection = ActiveRecord::Base.connection
    connection.tables.flat_map do |table|
      connection.foreign_keys(table).filter_map do |foreign_key|
        next unless foreign_key.to_table == 'users' && [nil, :restrict].include?(foreign_key.on_delete)

        [table, foreign_key.column]
      end
    end
  end

  # Where a unique index would stop the duplicate's row from moving to the primary because
  # the primary already has a row with the same other columns, the duplicate's row is
  # dropped only when it holds exactly the same data as the primary's (every column but
  # id, the user and updated_at; created_at counts, as the signing date of a sheet). A row
  # that differs is never dropped: the merge of this pair stops with an error naming it, to be settled by hand. An index on the user
  # column alone cannot be settled by dropping anything, so it is left to fail loudly when
  # the row is moved.
  def discard_rows_primary_already_has(primary, duplicate)
    connection = ActiveRecord::Base.connection
    user_reference_columns.each do |table, column|
      connection.indexes(table).each do |index|
        next unless index.unique && index.where.nil? && index.columns.is_a?(Array) && index.columns.include?(column)

        others = index.columns - [column]
        next if others.empty?

        same_key = others.map do |other|
          "d.#{connection.quote_column_name(other)} = p.#{connection.quote_column_name(other)}"
        end
        delete_repeat_rows(connection, table, column, same_key + [same_data_condition(connection, table, column)],
                           primary, duplicate)
        raise_on_differing_rows(connection, table, column, same_key, primary, duplicate)
      end
    end
  end

  def same_data_condition(connection, table, column)
    ignored = [connection.primary_key(table), column, 'updated_at'].compact.map { |name| connection.quote(name) }
    "(to_jsonb(d) - ARRAY[#{ignored.join(', ')}]) = (to_jsonb(p) - ARRAY[#{ignored.join(', ')}])"
  end

  def raise_on_differing_rows(connection, table, column, same_key, primary, duplicate)
    quoted_table = connection.quote_table_name(table)
    quoted_column = connection.quote_column_name(column)
    differing = connection.select_values(
      ActiveRecord::Base.sanitize_sql_array(
        ["SELECT d.#{connection.quote_column_name(connection.primary_key(table) || column)} FROM #{quoted_table} d " \
           "JOIN #{quoted_table} p ON #{same_key.join(' AND ')} AND p.#{quoted_column} = ? WHERE d.#{quoted_column} = ?",
         primary.id, duplicate.id]
      )
    )
    return if differing.empty?

    raise "Cannot merge user #{duplicate.id} into #{primary.id}: #{table} rows #{differing.join(', ')} of the " \
          'duplicate differ from the primary\'s row for the same key. Settle them by hand and run the task again.'
  end

  # Columns that reference users without a User association (supervisor_id, admin_id) and
  # the join tables without a primary key (training_sessions_users, ...) are repointed to
  # the primary; the foreign key would otherwise refuse to delete the duplicate. A join row
  # the primary already has, column for column, is dropped instead of moved twice: it is
  # the same row, not lost data.
  def repoint_remaining_user_references(primary, duplicate)
    connection = ActiveRecord::Base.connection
    user_reference_columns.each do |table, column|
      if connection.primary_key(table).nil?
        same = (connection.columns(table).map(&:name) - [column]).map do |other|
          quoted = connection.quote_column_name(other)
          "d.#{quoted} IS NOT DISTINCT FROM p.#{quoted}"
        end
        delete_repeat_rows(connection, table, column, same, primary, duplicate)
      end

      connection.update(
        ActiveRecord::Base.sanitize_sql_array(
          [
            "UPDATE #{connection.quote_table_name(table)} SET #{connection.quote_column_name(column)} = ? " \
              "WHERE #{connection.quote_column_name(column)} = ?",
            primary.id,
            duplicate.id
          ]
        )
      )
    end
  end

  def delete_repeat_rows(connection, table, column, same_conditions, primary, duplicate)
    quoted_table = connection.quote_table_name(table)
    quoted_column = connection.quote_column_name(column)
    conditions = ["d.#{quoted_column} = ?", "p.#{quoted_column} = ?"]
    connection.delete(
      ActiveRecord::Base.sanitize_sql_array(
        ["DELETE FROM #{quoted_table} d USING #{quoted_table} p WHERE #{(conditions + same_conditions).join(' AND ')}",
         duplicate.id, primary.id]
      )
    )
  end

  def merge_has_many_association(primary, duplicated, assoc)
    # The association can sometimes actually be a ThroughReflection, so there is
    # a join table we need to find
    if assoc.options[:through]
      merge_through_association(primary, duplicated, assoc)
    else
      assoc
        .klass # Get model class and run a query to find duplicate
        .where(assoc.foreign_key => duplicated.id)
        .find_each do |foreign_record|
          if assoc.name == :user_booking_approvals &&
               foreign_record.identity.blank?
            foreign_record.identity = 'Other'
          end
          # update in a map to get validations to run
          foreign_record.update!(assoc.foreign_key => primary.id)
          puts "\tUpdating has_many association #{assoc.name}"
        end
    end
  end

  def merge_through_association(primary, duplicated, assoc)
    # Find through join table
    through_assoc = User.reflect_on_association(assoc.options[:through])
    raise 'Join table not found' unless through_assoc

    through_assoc
      .klass
      .where(through_assoc.foreign_key => duplicated.id)
      .find_each do |foreign_record|
        # Check if the join record itself could be discarded too. Rather unlikely
        # but I want to find out
        record_attrs =
          foreign_record.attributes.except(
            'id',
            through_assoc.foreign_key,
            'created_at',
            'updated_at'
          )
        other_records =
          through_assoc
            .klass
            .where(through_assoc.foreign_key => primary.id)
            .where(record_attrs)

        if other_records.exists?
          puts "\tRecord already has through association #{assoc.name}, discarding..."
          # No need to move this over, delete
          foreign_record.destroy
        else
          puts "\tUpdating has_many through assocation #{assoc.name}"
          # Move over this record to point to primary
          foreign_record.update!(through_assoc.foreign_key => primary.id)
        end
      end
  end

  # move an association assoc from record duplicate to primary
  # This is a bit more tricky, as we can't just append to an array
  def merge_has_one_association(primary, duplicate, assoc)
    # Call a method named 'assoc'
    # NOTE : This works because there's no polymorphic associations. You should
    # never use them anyways
    foreign_record = duplicate.send(assoc.name)
    return unless foreign_record
    # This is usually the rfid model, assuming we can simply move it over
    foreign_record.update!(assoc.foreign_key => primary.id)
  end

  def merge_habtm_association(primary, duplicate, assoc)
    # for a HABTM association the join table is only two ids, we have to run on
    # model for validations. Here we can also assume plurality of the accessor method
    duplicate
      .send(assoc.plural_name)
      .each do |foreign_record|
        # Remove duplicate
        foreign_record.users.delete(duplicate.id)
        # Add primary unless already present
        unless foreign_record.users.include? primary
          foreign_record.users << primary
        end
      end
  end

  def count_associations(user)
    count = 0
    User.reflect_on_all_associations.each do |assoc|
      next if assoc.macro == :belongs_to

      case assoc.macro
      when :has_many, :has_one
        if assoc.options[:through]
          through_assoc = User.reflect_on_association(assoc.options[:through])
          count +=
            through_assoc
              .klass
              .where(through_assoc.foreign_key => user.id)
              .count if through_assoc
        else
          fk = assoc.foreign_key.to_s
          count += assoc.klass.where(fk => user.id).count if assoc
            .klass
            .column_names
            .include?(fk)
        end
      when :has_and_belongs_to_many
        join_table = assoc.join_table
        fk = assoc.foreign_key.to_s
        count +=
          ActiveRecord::Base
            .connection
            .select_value(
              "SELECT COUNT(*) FROM #{join_table} WHERE #{fk} = #{user.id}"
            )
            .to_i
      end
    end
    count
  end
end
