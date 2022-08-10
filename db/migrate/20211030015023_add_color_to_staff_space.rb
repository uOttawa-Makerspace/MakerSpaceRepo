class AddColorToStaffSpace < ActiveRecord::Migration[6.0]
  def change
    add_column :staff_spaces, :color, :string

    StaffSpace.all.each do |staff_space|
      staff_space.update(
        color: "#" + "%06x" % (staff_space.user.id.hash & 0xffffff)
      )
    end
  end
end
