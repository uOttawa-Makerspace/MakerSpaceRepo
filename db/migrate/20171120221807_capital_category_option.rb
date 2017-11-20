class CapitalCategoryOption < ActiveRecord::Migration
  def up
    CategoryOption.where(name: "gng1103/gng1503").update_all(name: "GNG1103/GNG1503")
    CategoryOption.where(name: "gng2101/gng2501").update_all(name: "GNG2101/GNG2501")

    Category.where(name: "gng1103/gng1503").update_all(name: "GNG1103/GNG1503")
    Category.where(name: "gng2101/gng2501").update_all(name: "GNG2101/GNG2501")

  end
end
