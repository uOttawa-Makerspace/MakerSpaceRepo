class PrintOrdersController < ApplicationController
  before_action :current_user
  before_action :signed_in

  def index
    #TODO: Too much logic in index.html.erb
    @order = {
        "approved is NULL" => "Waiting for Staff Approval",
        "user_approval is NULL and approved is TRUE" => "Waiting for user Approval",
        "user_approval is TRUE and approved is TRUE and printed is NULL" => "Waiting to be printed",
        "user_approval is TRUE and approved is TRUE and printed is TRUE" => "Printed",
        "user_approval is FALSE or approved is FALSE" => "Disapproved"
    }

    if (@user.staff? || @user.admin?)
      @print_order = PrintOrder.all.order(expedited: :desc, created_at: :asc)
    else
      @print_order = @user.print_orders.order(expedited: :desc, created_at: :desc)
    end

  end

  def new
    @print_order = PrintOrder.new
    if (@user.identity == "undergrad") or (@user.identity == "grad") or (@user.identity == "faculty_member")
      prices = [0.15, 0.2, 0.25, 0.28, 0.38, 0.47, 15, 0.53, 5.82, 2.99, 3, 4, 15, 18]
    else
      prices = [0.3, 0.4, 0.5, 0.56, 0.76, 0.94, 30, 0.53, 5.82, 2.99, 3, 4, 15, 18]
    end
    if params[:type] == "laser"
      @table = [
          ["Laser - mdf 1/8\" (Per Sheet)", prices[10], 20],
          ["Laser - mdf 1/4\" (Per Sheet)	", prices[11], 20],
          ["Laser - acrylic 1/8\" (Per Sheet)", prices[12], 20],
          ["Laser - acrylic 1/4\" (Per Sheet)", prices[13], 20]
      ]
    else
      @table = [
          ["3D Low (PLA/ABS), (per g)", prices[0], 15],
          ["3D Medium (PLA/ABS), (per g)", prices[1], 15],
          ["3D High (PLA/ABS), (per g)", prices[2], 15],
          ["3D Low (Other Materials), (per g)", prices[3], 15],
          ["3D Medium (Other Materials), (per g)", prices[4], 15],
          ["3D High (Other Materials), (per g)", prices[5], 15],
          ["SST Printer (Per Hour)", prices[6], 15],
          ["M2 Onyx (per cm3)", prices[7], 15],
          ["M2 Carbon Fiber (per cm3)", prices[8], 15],
          ["M2 Fiberglass (per cm3)	", prices[9], 15]
      ]
    end
  end

  def create
    if params[:print_order][:material] and params[:print_order][:comments]
      params[:print_order][:comments] = params[:print_order][:material] + ", " + params[:print_order][:comments]
    end

    if params[:print_order][:material] == "SST"
      params[:print_order][:sst] = "true"
    end

    if params[:print_order][:comments] and (params[:print_order][:comments_box] != "")
      params[:print_order][:comments] = params[:print_order][:comments] + ", " + params[:print_order][:comments_box]
    end

    @print_order = PrintOrder.create(print_order_params)
    if @print_order.id.nil? || @print_order.id == 0
      redirect_to print_orders_path, :alert => "The upload as failed ! Make sure the file types are STL for 3D Printing or SVG and PDF for Laser Cutting !"
    else
      MsrMailer.send_print_to_makerspace(@print_order.id).deliver_now
      redirect_to print_orders_path, :notice => "The print order has been sent for admin approval, you will receive an email in the next few days, once the admins made a decision."
    end
  end

  def update
      # Surcharge for expedited services
      expedited_price = 20

      @print_order = PrintOrder.find(params[:id])

      if params[:print_order][:timestamp_approved]
        params[:print_order][:timestamp_approved] = DateTime.now
      end

      if params[:print_order][:price_per_hour] and params[:print_order][:material_cost] and params[:print_order][:service_charge]
        params[:print_order][:quote] = params[:print_order][:service_charge].to_f + params[:print_order][:price_per_hour].to_f + params[:print_order][:material_cost].to_f
        if @print_order.expedited == true
          params[:print_order][:quote] = params[:print_order][:quote].to_f + expedited_price.to_f
        end
        elsif params[:print_order][:price_per_hour] and params[:print_order][:hours] and params[:print_order][:service_charge]
          params[:print_order][:quote] = params[:print_order][:service_charge].to_f + (params[:print_order][:price_per_hour].to_f * params[:print_order][:hours].to_f)
          if @print_order.expedited == true
            params[:print_order][:quote] = params[:print_order][:quote].to_f + expedited_price.to_f
          end

        elsif params[:print_order][:price_per_gram] and params[:print_order][:grams] and params[:print_order][:service_charge]
        params[:print_order][:quote] = params[:print_order][:service_charge].to_f + (params[:print_order][:grams].to_f * params[:print_order][:price_per_gram].to_f)
        if @print_order.expedited == true
          params[:print_order][:quote] = params[:print_order][:quote].to_f + expedited_price.to_f
        end
      end



      @user = @print_order.user
      @print_order.update(print_order_params)

      if params[:print_order][:approved] == "true"
        MsrMailer.send_print_quote(expedited_price, @user, @print_order, params[:print_order][:staff_comments]).deliver_now
      elsif params[:print_order][:approved] == "false"
        MsrMailer.send_print_disapproval(@user, params[:print_order][:staff_comments], @print_order.file_file_name).deliver_now
      elsif params[:print_order][:user_approval] == "true"
        MsrMailer.send_print_user_approval_to_makerspace(@print_order.id).deliver_now
      elsif params[:print_order][:printed] == "true"
        MsrMailer.send_print_finished(@user, @print_order.file_file_name, @print_order.id, @print_order.quote).deliver_now
        MsrMailer.send_invoice(@user.name, @print_order.quote, @print_order.id, @print_order.order_type).deliver_now
      end

      redirect_to print_orders_path
  end

  def destroy
    @print_order = PrintOrder.find(params[:id])
    @print_order.destroy
    redirect_to print_orders_path
  end

  def edit
    @print_order = PrintOrder.find(params[:id])
  end

  def invoice
    @print_order = PrintOrder.find(params[:print_order_id])
    if @print_order.printed == true
      render :pdf => "file_name", :template => 'print_orders/pdf.html.erb'
    end
  end

  private

  def print_order_params
    params.require(:print_order).permit(:user_id, :hours, :final_file, :sst, :material, :grams, :grams2, :price_per_gram2, :service_charge, :price_per_gram, :price_per_hour, :material_cost, :timestamp_approved, :order_type, :comments, :approved, :printed, :file, :quote, :user_approval, :staff_comments, :staff_id, :expedited)
  end

end
