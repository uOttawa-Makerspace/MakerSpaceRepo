class Staff::TrainingSessionController < ApplicationController
  before_action :load_user, only: [:show, :edit, :update]

  layout 'staff_dashboard'

  
end
