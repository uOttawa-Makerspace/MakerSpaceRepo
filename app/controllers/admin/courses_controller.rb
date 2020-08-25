class Admin::CoursesController < AdminAreaController
  layout 'admin_area'
  before_action :changed_course, only: %i[update destroy]

  def index
    @courses = Course.all.order(:name)
  end

  def new
    @new_course = Course.new
  end

  def edit
    @course = Course.find(params[:id])
  end

  def create
    @new_course = Course.new(course_params)
    if @new_course.save
      flash[:notice] = 'Course added successfully!'
    else
      flash[:alert] = 'Input is invalid'
    end
    redirect_to admin_courses_path
  end

  def update
    @changed_course.update(course_params)
    if @changed_course.save
      flash[:notice] = 'Course renamed successfully'
    else
      flash[:alert] = 'Input is invalid'
    end
    redirect_to admin_courses_path
  end

  def destroy
    flash[:notice] = 'Course removed successfully' if @changed_course.destroy
    redirect_to admin_courses_path
  end

  private

  def course_params
    params.require(:course).permit(:name)
  end

  def changed_course
    @changed_course = Course.find(params['id'])
  end

end

