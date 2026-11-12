# Adds the language a user picked on the site (users.locale), so mail to that user can be sent in it.
# The column is nullable with no default: existing users stay NULL, which means "no choice saved yet" and
# is sent in the site's default language. A check constraint keeps it to the languages the site offers.
# `down` drops the constraint and the column; no other data is touched.
class AddLocaleToUsers < ActiveRecord::Migration[8.1]
  CONSTRAINT = "users_locale_supported"

  def up
    add_column :users, :locale, :string, if_not_exists: true
    add_check_constraint :users, "locale IN ('en', 'fr')", name: CONSTRAINT, if_not_exists: true
  end

  def down
    remove_check_constraint :users, name: CONSTRAINT, if_exists: true
    remove_column :users, :locale, if_exists: true
  end
end
