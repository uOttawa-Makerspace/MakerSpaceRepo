# frozen_string_literal: true

class ShareType < ActiveRecord::Migration[5.0]
  def change
    add_column :repositories, :share_type, :string
  end
end
