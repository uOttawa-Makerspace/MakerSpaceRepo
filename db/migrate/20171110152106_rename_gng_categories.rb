class RenameGngCategories < ActiveRecord::Migration
  def change
    Category.where(name: "gng1103").update_all(name: "gng1103/gng1503")
    CategoryOption.where(name: "gng2101").update_all(name: "gng2101/gng1501")    
  end
end
