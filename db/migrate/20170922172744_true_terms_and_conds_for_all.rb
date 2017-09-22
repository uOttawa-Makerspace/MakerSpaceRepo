class TrueTermsAndCondsForAll < ActiveRecord::Migration
  def up
    User.where(terms_and_conditions: false).update_all(terms_and_conditions: true);
  end
end
