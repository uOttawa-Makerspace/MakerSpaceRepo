# frozen_string_literal: true

class CreateCcMoneys < ActiveRecord::Migration[5.0]
  def change
    create_table :cc_moneys do |t|
      t.integer :user_id
      t.integer :volunteer_task_id
      t.integer :cc

      t.timestamps null: false
    end
  end
end
