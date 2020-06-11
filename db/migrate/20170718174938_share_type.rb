# frozen_string_literal: true

class ShareType < ActiveRecord::Migration
  def change
    add_column :repositories, :share_type, :string
  end
end
