class RenameGngCategories < ActiveRecord::Migration
  def up
    Category.where(name: "gng1103").update_all(name: "gng1103/gng1503")
    CategoryOption.where(name: "gng1103").update_all(name: "gng1103/gng1503") 

    Category.where(name: "gng2101").update_all(name: "gng2101/gng2501")
    CategoryOption.where(name: "gng2101").update_all(name: "gng2101/gng2501")
  end
end
