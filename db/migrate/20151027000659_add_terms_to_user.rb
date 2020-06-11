# frozen_string_literal: true

class AddTermsToUser < ActiveRecord::Migration[5.0]
  def change
    add_column :users, :terms_and_conditions, :boolean, default: true
  end
end
