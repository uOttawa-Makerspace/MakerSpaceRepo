class AdminController < AdminAreaController
  include BadgesHelper

  def index
  end

  def manage_badges
    if params[:refresh].present?
      if params[:refresh] == "templates"
        update_badge_data_helper
      elsif params[:refresh] == "badges"
        update_badge_templates_helper
      end
    end
  end

end
