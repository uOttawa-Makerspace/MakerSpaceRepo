# frozen_string_literal: true

class Admin::BadgeTemplatesController < AdminAreaController
  layout 'admin_area'

  def index
    @badge_template = BadgeTemplate.all.order(badge_name: :asc)
  end

  def edit
    @badge_template = BadgeTemplate.find(params[:id])
  end

  def update
    badge_template = BadgeTemplate.find(params[:id])
    if badge_template.update(badge_template_params)
      flash[:notice] = 'Badge Template updated'
    else
      flash[:alert] = 'Something went wrong'
    end
    redirect_to admin_badge_templates_path
  end

  private

  def badge_template_params
    params.require(:badge_template).permit(:training_id, :training_level)
  end

end


