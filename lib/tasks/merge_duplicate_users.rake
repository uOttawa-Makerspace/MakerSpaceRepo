# Finds all duplicated users and deletes them. This also doubles as a quick test
# for destroying user records.

namespace :users do
  desc 'Find and merge all duplicated user records. Uses the record with the
  most amount of associations to assume which record is the most-frequently
  used'

  task :merge_duplicates, [] => :environment do
    duplicated_emails = email_tally.keys

    puts "#{duplicated_emails.count} duplicated emails found."

    duplicated_emails.each { |email| merge_duplicated_email(email) }

    duplicated_usernames = username_tally.keys
    puts "After email merge, there are #{duplicated_usernames.count} usernames duplicated."

    duplicated_usernames.each do |username|
      rename_duplicated_username(username)
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
    users = User
              .unscope(where: :deleted)
              .where('lower(username) ilike ?', username)
    
    # Sanity check
    if users.count == 1
      raise "No duplicate records found for username #{username}. probably a deleted user?"
    end

    # Check if there's one and only one user deleted
    if users.where(deleted: false) == 1
      # the rest are deleted users, change those instead
      users = users.where(deleted: true)
    end
    
    suffixes = (111..999).to_a
    users
      .zip(suffixes.sample(users.count))
      .each do |user, suffix|
        user.username = user.username + suffix.to_s
        puts "#{user.username_was} => #{user.username}"
        user.save!
      end
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
  end

  def merge_record(primary, duplicate)
    # https://api.rubyonrails.org/classes/ActiveRecord/Reflection/ClassMethods.html#method-i-reflect_on_all_associations
    # Reflect on all table-level associations
    # User.reflect_on_all_associations.map(&:macro).uniq
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

    duplicate.destroy!
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
        rescue ActiveRecord::RecordInvalid => e
          # At the time of writing this, there's only one space you can sign a
          # sheet for. Assuming you've signed it we can discard the second copy.
          if assoc.name == :walk_in_safety_sheets
            puts "\tRecord already has a safety sheet, discarding..."
            foreign_record.destroy
          else
            raise e
          end
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
