module ProficientProjectsHelper
  def return_hover_and_text_colors(proficient_project_level)
    case proficient_project_level
    when "Beginner" then
      "w3-hover-border-light-green w3-hover-text-light-green"
    when "Intermediate" then
      "w3-hover-border-yellow w3-hover-text-yellow"
    when "Advanced" then
      "w3-hover-border-red w3-hover-text-red"
    end
  end

  def return_border_color(proficient_project_level)
    case proficient_project_level
    when "Beginner" then
      "w3-border-light-green"
    when "Intermediate" then
      "w3-border-yellow"
    when "Advanced" then
      "w3-border-red"
    end
  end
end
