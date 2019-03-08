class ProgramList

  # TODO figure out a better way to do this
  def self.fetch_all
   @programs = []
   File.read("#{Rails.root}/lib/assets/programs.txt").each_line do |line|
     @programs << line.chop
   end
   @programs
  end

end
