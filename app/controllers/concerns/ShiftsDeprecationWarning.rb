module ShiftsDeprecationWarning
  extend ActiveSupport::Concern

  included do
    before_action :show_deprecation_warning, if: -> { request.get? }
  end

  private

  def show_deprecation_warning
    flash[:alert] = deprecation_message
  end

  def deprecation_message
    "This shifts functionality is deprecated. Please use the " \
    "#{view_context.link_to('new staff calendar', staff_my_calendar_index_path)} instead."
  end
end