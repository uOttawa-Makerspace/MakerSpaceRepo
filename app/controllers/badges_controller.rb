class BadgesController < ApplicationController
  layout 'development_program'

  def index
    begin
      if (@user.admin? || @user.staff?)
        @acclaim_data = Badge.all
      else
        @acclaim_data = @user.badges
      end
    end
  end
end
