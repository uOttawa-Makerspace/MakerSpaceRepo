class String
    def slug_to_title (string)
      exclusions = "of, to, and, in, on, the, and"
      string.split("-").map { |word| 
        if exclusions.include?(word) then
          word
        elsif ((word=="3d")||(word=="cnc")||(word=="pcb"))
          word.upcase
        elsif ((word=="uottawa")||(word=="ipad"))
          word[1] = word[1].upcase
          word  
        else
          word.capitalize
        end
        }.join(" ")
    end
end