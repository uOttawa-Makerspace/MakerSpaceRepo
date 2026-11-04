# A card row always has a number: NOT NULL plus a CHECK that it is not blank.
#
# Rows without a usable number are counted first and the migration refuses to run
# while any exist; they are never repaired or removed automatically (the card they
# stand for is unknown). The CHECK is added NOT VALID, validated on its own
# (SHARE UPDATE EXCLUSIVE, writes keep flowing) and only then is the column set NOT
# NULL, which Postgres accepts without another table scan because the validated
# CHECK already proves it. No DDL transaction wraps the migration, so each step
# commits alone and a failed run can be started again.
class RequireCardNumberOnRfids < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  CHECK_NAME = "rfids_card_number_present_check"
  CHECK = "card_number IS NOT NULL AND btrim(card_number) <> ''"

  def up
    refuse_unusable_numbers
    unless check_constraint_exists?(:rfids, name: CHECK_NAME)
      add_check_constraint :rfids, CHECK, name: CHECK_NAME, validate: false
    end
    validate_check_constraint :rfids, name: CHECK_NAME
    change_column_null :rfids, :card_number, false
  end

  def down
    change_column_null :rfids, :card_number, true
    remove_check_constraint :rfids, name: CHECK_NAME, if_exists: true
  end

  def refuse_unusable_numbers
    count = select_value("SELECT COUNT(*) FROM rfids WHERE card_number IS NULL OR btrim(card_number) = ''").to_i
    return if count.zero?

    raise "#{count} rfids rows have no usable card_number (NULL or blank); " \
          "decide what to do with those rows before requiring a number"
  end
end
