class FixCategorieOptions < ActiveRecord::Migration
  def up
    @gng1103OptionA = CategoryOption.find_by(name: "GNG1103")
    @gng1103OptionB = CategoryOption.find_by(name: "gng1103")

    @gng2101OptionA = CategoryOption.find_by(name: "GNG2101")
    @gng2101OptionB = CategoryOption.find_by(name: "gng2101")

    @gng1103OptionA.name = "GNG1103/GNG1503"
    if @gng1103OptionA.save
      print "good gng1103OptionA"
    else
      print "bad gng1103OptionA"
    end

    @gng1103OptionB.name = "GNG1103/GNG1503"
    if @gng1103OptionB.save
      print "good gng1103OptionB"
    else
      print "bad gng1103OptionB"
    end

    @gng2101OptionA.name = "GNG2101/GNG2501"
    if @gng2101OptionA.save
      print "good gng2101OptionA"
    else
      print "bad gng2101OptionA"
    end

    @gng2101OptionB.name = "GNG2101/GNG2501"
    if @gng2101OptionB.save
      print "good gng2101OptionB"
    else
      print "bad gng2101OptionB"
    end


  end
end
