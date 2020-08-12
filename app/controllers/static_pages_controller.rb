# frozen_string_literal: true

class StaticPagesController < SessionsController
  before_action :current_user, except: [:reset_password]

  def home; end

  def about; end

  def contact; end

  def terms_of_service; end

  def hours; end

  def calendar; end

  def forgot_password; end

  def volunteer_program_info; end

  def development_program_info; end

  def reset_password
    @user = User.find_by(email: params[:email])

    begin
      random_password = Array.new(10).map { rand(65..122).chr }.join
      @user.pword = random_password

      if @user.save!
        MsrMailer.reset_password_email(@user.email, random_password).deliver_now
        flash[:notice] = 'Check your email for your new password.'
        redirect_to root_path
      end
    rescue StandardError
      flash[:alert] = 'Something went wrong, try again.'
      redirect_to forgot_password_path
    end
  end

  def report_repository
    if signed_in?
      repository = Repository.find params[:repository_id]
      user = current_user
      MsrMailer.repo_report(repository, user).deliver_now
      flash[:alert] = 'Repository has been reported'
    else
      flash[:alert] = 'Please login if you wish to report this repository'
    end
    redirect_back(fallback_location: root_path)
  end
end
