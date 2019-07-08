class PrintOrderController < ApplicationController
  before_action :current_user
  before_action :signed_in

  def index
      @users = User.all
      if (@user.staff? || @user.admin?)
        @print_order = PrintOrder.all
      else
        @print_order = PrintOrder.where(userid: @user.id)
      end

    end

    def show
      @print_order = PrintOrder.find(params[:id])
    end

    def new
      @print_order = PrintOrder.new
    end

    def create
      @print_order = PrintOrder.create(print_order_params)
      redirect_to print_order_index_path
    end

    def update
      @print_order = PrintOrder.find(params[:id])
      @user = User.find(@print_order.userid)
      @print_order.update(print_order_params)

      if params[:print_order][:approved] == "true"
        MsrMailer.send_print_quote(@user, @print_order.quote, params[:print_order][:StaffComments]).deliver_now
      elsif params[:print_order][:approved] == "false"
        MsrMailer.send_print_disapproval(@user, params[:print_order][:StaffComments]).deliver_now
      elsif params[:print_order][:printed] == "true"
        MsrMailer.send_print_finished(@user).deliver_now
      end

      redirect_to print_order_index_path
    end

    def destroy
      @print_order = PrintOrder.find(params[:id])
      @print_order.destroy
      redirect_to print_order_index_path
    end

    def edit
      @print_order = PrintOrder.find(params[:id])
    end

    private

    def print_order_params
      params.require(:print_order).permit(:userid, :comments, :approved, :printed, :file, :quote, :UserApproval, :StaffComments, :staffid)
    end

end
