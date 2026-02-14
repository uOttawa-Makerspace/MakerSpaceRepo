class CreateLockerSizes < ActiveRecord::Migration[7.2]
  def change
    create_table :locker_sizes do |t|
      t.string :size
      # t.decimal :member_cost
      # t.decimal :non_member_cost
      t.string :shopify_gid

      t.timestamps
    end

    change_table :lockers do |t|
      t.references :locker_size
      t.boolean :staff_only
    end
  end
end
