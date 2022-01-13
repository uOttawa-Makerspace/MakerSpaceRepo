class ConvertBelongsToToHasAndBelongsToManyShiftsUsers < ActiveRecord::Migration[6.1]
  def up

    create_join_table :shifts, :users do |t|
      t.index :shift_id
      t.index :user_id
    end

    Shift.belongs_to :single_user, class_name: 'User', foreign_key: 'user_id'

    Shift.all.each do |shift|
      unless shift.single_user.nil?
        shift.users << shift.single_user
        shift.save
      end
    end

    remove_column :shifts, :user_id
  end

  def down
    add_column :shifts, :user_id, :integer

    Shift.belongs_to :single_user, class_name: 'User', foreign_key: 'user_id'

    Shift.all.each do |shift|
      shift.single_user = shift.users.first unless shift.users.empty?
      shift.save
    end

    drop_table :shifts_users
  end
end
