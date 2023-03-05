class Admin::CourseNamesController < AdminAreaController
  layout "admin_area"
  before_action :changed_course, only: %i[update destroy]

  def index
    @courses = CourseName.all.order(:name)
  end

  def new
    @new_course = CourseName.new
  end

  def edit
    @course = CourseName.find(params[:id])
  end

  def create
    @new_course = CourseName.new(course_params)
    if @new_course.save
      flash[:notice] = "Course added successfully!"
    else
      flash[:alert] = "Input is invalid"
    end
    redirect_to admin_course_names_path
  end

  def update
    @changed_course.update(name: params[:course_name][:name])
    if @changed_course.save
      flash[:notice] = "Course renamed successfully"
    else
      flash[:alert] = "Input is invalid"
    end
    redirect_to admin_course_names_path
  end

  def destroy
    flash[:notice] = "Course removed successfully" if @changed_course.destroy
    redirect_to admin_course_names_path
  end

  private

  def course_params
    params.permit(:course_name, :name)
  end

  def changed_course
    @changed_course = CourseName.find(params["id"])
  end
end
