class AddInitialLockerTypes < ActiveRecord::Migration[7.0]
  def up
    LockerType.new(
      short_form: "MLAB119",
      description: "By Makerlab 119",
      available_for: :staff,
      quantity: 50,
      cost: 20
    ).save
    LockerType.new(
      short_form: "MLAB121",
      description: "By Makerlab 121",
      available_for: :staff,
      quantity: 50,
      cost: 20
    ).save
    LockerType.new(
      short_form: "BRUNS",
      description: "By the Brunsfield Centre",
      available_for: :staff,
      quantity: 50,
      cost: 20
    ).save
  end

  def down
    LockerType.delete_all
  end
end
