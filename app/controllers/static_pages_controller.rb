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
    repository = Repository.find params[:repository_id]
    MsrMailer.repo_report(repository).deliver_now
    flash[:alert] = 'Repository has been reported'
    redirect_back(fallback_location: root_path)
  end
end
