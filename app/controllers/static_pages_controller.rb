# frozen_string_literal: true

class StaticPagesController < SessionsController
  before_action :current_user, except: [:reset_password]

  def home
    @volunteer_program_shadowing_scheduled =
      current_user.shadowing_hours.map do |hours|
        end_time = hours.end_time.strftime "%H:%M"
        formatted_time =
          "#{I18n.l hours.start_time, format: "%A %H:%M"} - #{end_time}"
        [hours.space.name, formatted_time]
      end

    # NOTE: This crashed before, while using get_volunteer_tasks_from_volunteer_joins so
    # It shouldn't happen again, but I added an exception handler just in case.
    @volunteer_program_your_tasks =
      begin
        current_user
          .volunteer_task_joins
          .active
          .order(updated_at: :desc)
          .joins(:volunteer_task)
          .includes(volunteer_task: :space)
          .where(volunteer_task: { status: "open" })
          .map do |task|
            task_name = task.volunteer_task.title
            space_name = task.volunteer_task.space.name
            formatted_time = task.created_at.strftime "%H:%M"
            [task_name, space_name, formatted_time, task.volunteer_task_id]
          end.take 5 # five most recent
      rescue StandardError
        []
      end

    @recent_projects =
      Repository.public_repos.order(created_at: :desc).limit(15)

    @user_skills =
      current_user.certifications.map do |cert|
        [cert.training_session.training.name, cert.training_session.level]
      end.sample 5

    # Get total tracks in all learning modules
    total_tracks = LearningModule.all.map { |x| x.training.name }.tally
    # get the total number of tracks completed
    # and in progress under the user's name
    @user_tracks =
      current_user
        .learning_module_tracks
        .group_by { |x| x.learning_module.training.name }
        .transform_values { |x| x.map(&:status).tally }
        .map do |key, value|
          [key, "#{value["Completed"]}/#{total_tracks[key]}"]
        end

    @contact_info = ContactInfo.where(show_hours: true).order(name: :asc)

    @posts = InstagramService.fetch_posts["data"] || []
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

  def get_involved
  end

  def all_resources
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
