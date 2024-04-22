# frozen_string_literal: true

class StaticPagesController < SessionsController
  before_action :current_user, except: [:reset_password]

  def home
  end

  def about
  end

  def contact
    @contact_info = ContactInfo.all.order(name: :asc)
  end

  def terms_of_service
  end

  def hours
    @contact_info = ContactInfo.where(show_hours: true).order(name: :asc)

    respond_to do |format|
      format.html { render :hours }
      format.json do
        render json:
                 @contact_info.as_json(
                   include: :opening_hour,
                   only: %i[
                     name
                     email
                     address
                     phone_number
                     show_hours
                     opening_hour
                   ]
                 )
      end
    end
  end

  def calendar
  end

  def forgot_password
  end

  def volunteer_program_info
  end

  def development_program_info
  end

  def join_team_program
    if signed_in?
      if current_user.programs.exists?(program_type: Program::TEAMS)
        flash[:alert] = "You are already part of the Teams Program."
      else
        current_user.programs.create(program_type: Program::TEAMS)
        flash[
          :notice
        ] = "You have successfully joined the Teams Program! See below for more information."
      end
    else
      flash[:alert] = "You need to sign in to join the Teams Program."
    end
    redirect_to root_path
  end

  def reset_password
    unless verify_recaptcha
      flash[:alert] = "There was a problem with the captcha, please try again."
      redirect_to root_path
      return
    end
    if params[:email].present?
      if User.find_by_email(params[:email]).present?
        @user = User.find_by(email: params[:email])
        user_hash = Rails.application.message_verifier(:user).generate(@user.id)
        expiry_date_hash =
          Rails.application.message_verifier(:user).generate(1.day.from_now)
        MsrMailer.forgot_password(
          params[:email],
          user_hash,
          expiry_date_hash
        ).deliver_now
      end
      flash[
        :notice
      ] = "A reset link email has been sent to the email if the account exists."
    else
      flash[:alert] = "There was a problem with, please try again."
    end
    redirect_to root_path
  end

  def report_repository
    if signed_in?
      repository = Repository.find params[:repository_id]
      user = current_user
      MsrMailer.repo_report(repository, user).deliver_now
      flash[:alert] = "Repository has been reported"
    else
      flash[:alert] = "Please login if you wish to report this repository"
    end
    redirect_back(fallback_location: root_path)
  end
end
