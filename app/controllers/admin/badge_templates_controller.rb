# frozen_string_literal: true

class Admin::BadgeTemplatesController < AdminAreaController
  layout "admin_area"

  def index
    @badge_template =
      BadgeTemplate.all.order(updated_at: :desc, badge_name: :asc)
    @template_usage = Badge.group(:badge_template_id).count
    @templates_at_service =
      BadgeTemplate.acclaim_api_get_all_badge_templates["data"].map do |x|
        x["id"]
      end
  end

  def edit
    @badge_template = BadgeTemplate.find(params[:id])
    @usage_count = Badge.where(badge_template_id: params[:id]).count
  end

  def update
    badge_template = BadgeTemplate.find(params[:id])
    if badge_template.update(badge_template_params)
      flash[:notice] = "Badge Template updated"
    else
      flash[:alert] = "Something went wrong"
    end
    redirect_to admin_badge_templates_path
  end

  def destroy
    begin
      BadgeTemplate.find(params[:id]).destroy!
    rescue Error => e
      flash[:alert] = "Error deleting template: #{e}"
    else
      flash[:notice] = "Badge deleted successfully"
    end

    redirect_to admin_badge_templates_path, status: :see_other
  end

  private

  def badge_template_params
    params.require(:badge_template).permit(:training_id, :training_level)
  end
end
