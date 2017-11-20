class FixCategories < ActiveRecord::Migration
  def up
    @gng1103CatsA = Category.where(name: "GNG1103")
    @gng1103CatsA.each do |cat|
      cat.name = "GNG1103/GNG1503"
      if cat.save
        print("good 1103")
      else
        print("bad 1103")
    end

    @gng1103CatsB = Category.where(name: "gng1103")
    @gng1103CatsB.each do |cat|
      cat.name = "GNG1103/GNG1503"
      if cat.save
        print("good 1103")
      else
        print("bad 1103")
    end

    @gng2101CatsA = Category.where(name: "GNG2101")
    @gng2101CatsA.each do |cat|
      cat.name = "GNG2101/GNG2501"
      if cat.save
        print("good 2101")
      else
        print("bad 2101")
    end

    @gng2101CatsB = Category.where(name: "gng2101")
    @gng2101CatsB.each do |cat|
      cat.name = "GNG2101/GNG2501"
      if cat.save
        print("good 2101")
      else
        print("bad 2101")
    end

  end
end
