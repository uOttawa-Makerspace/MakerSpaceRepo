class CreateUniPrograms < ActiveRecord::Migration[7.0]
  def change
    create_table :uni_programs, id: false do |t|
      t.string :program, index: true, null: false
      t.string :faculty, null: false
      t.string :level, null: false
      t.string :department, null: false

      t.timestamps
    end

    reversible do |direction|
      direction.up do
        progs =
          CSV.read(Rails.root.join("lib/assets/programs.csv"), headers: true)
        UniProgram.transaction do
          UniProgram.create(
            program: "My program is not in the list",
            faculty: "",
            level: "",
            department: ""
          ).save
          progs.each do |row|
            UniProgram.create(
              program: row["program"],
              faculty: row["faculty"],
              level: row["level"],
              department: row["department"]
            ).save
          end
        end
      end
    end
  end
end
