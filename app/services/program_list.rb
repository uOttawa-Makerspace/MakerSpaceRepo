class ProgramList

  def self.fetch_all
   @@programs ||= File.read("#{Rails.root}/public/programs.txt").lines
  end

end
