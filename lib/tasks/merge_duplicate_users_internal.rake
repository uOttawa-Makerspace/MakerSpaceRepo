# Finds all duplicated users and deletes them. This also doubles as a quick test
# for destroying user records.

namespace :users do
  desc 'Find and merge all duplicated user records. Uses the record with the
  most amount of associations to assume which record is the most-frequently
  used'

  task :merge_duplicates_internal, [] => :environment do
    duplicated_emails = email_tally.keys

    puts "#{duplicated_emails.count} duplicated emails found"

    duplicated_emails.each { |email| merge_duplicated_user(email.downcase) }
  end

  private

  def email_tally
    User.all.pluck(:email).map(&:downcase).sort.tally.filter { |k, v| v > 1 }
  end

  def merge_duplicated_user(email)
    users = User.where('lower(email) like ?', email)
    puts "#{email} had #{users.count} records"

    # TODO: Find which one has the most associations
    primary = users[0]
    duplicates = users[1..]

    duplicates.each do |duplicate|
      raise 'dude what' if duplicate.id == primary.id
      ActiveRecord::Base.transaction { merge_record(primary, duplicate) }
    rescue StandardError
      binding.pry
    end
  end

  def merge_record(primary, duplicate)
    # https://api.rubyonrails.org/classes/ActiveRecord/Reflection/ClassMethods.html#method-i-reflect_on_all_associations
    # Reflect on all table-level associations
    # User.reflect_on_all_associations.map(&:macro).uniq to find all possible macros
    # We're going to hit all possible assocs, need to make sure there's a record to update
    #
    # Unfortunately, the current code base is trash and the model association
    # tables are underspecified. This uses an internal rails function to get
    # straight to the join tables when possible and replace the IDs in there
    User._reflections.each do |name, assoc|
      puts "Processing #{name}: :#{assoc.macro}"
      case assoc.macro
      when :has_many
        merge_has_many_association(primary, duplicate, assoc)
      when :has_one
        merge_has_one_association(primary, duplicate, assoc)
      when :has_and_belongs_to_many
        raise 'Should never happen using internal method'
        # merge_habtm_association(primary, duplicate, assoc)
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
    if assoc.options[:through]
      merge_through_association(primary, duplicated, assoc)
    else
      assoc
        .klass # Get model class and run a query to find duplicate
        .where(assoc.foreign_key => duplicated.id)
        .find_each do |foreign_record|
          # update in a map to get validations to run
          foreign_record.update!(assoc.foreign_key => primary.id)
        rescue ActiveRecord::RecordInvalid => e
          # At the time of writing this, there's only one space you can sign a
          # sheet for. Assuming you've signed it we can discard the second copy.
          if assoc.name == :walk_in_safety_sheets
            foreign_record.destroy
          else
            binding.pry
            raise e
          end
        end
    end
  rescue StandardError => e
    binding.pry
  end

  def merge_through_association(primary, duplicated, assoc)
    # Find through join table
    through_assoc = User._reflect_on_association(assoc.options[:through])
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
          # No need to move this over, delete
          foreign_record.destroy
        else
          # Move over this record to point to primary
          foreign_record.update(through_assoc.foreign_key => primary.id)
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
end
