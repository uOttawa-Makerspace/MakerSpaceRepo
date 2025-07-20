# frozen_string_literal: true

class AdminController < AdminAreaController

  def index
  end

  def manage_badges
    return unless params[:refresh].present?
      if params[:refresh] == "templates"
        update_badge_templates_helper
      elsif params[:refresh] == "badges"
        update_badge_data_helper
      end
    
  end
end
