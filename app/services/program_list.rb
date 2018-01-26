class ProgramList

  def self.fetch_all
   @programs = []
   File.read("#{Rails.root}/public/programs.txt").each_line do |line|
     @programs << line.chop
   end
   @programs
  end

end
