# frozen_string_literal: true

class PrintOrdersController < ApplicationController
  before_action :current_user
  before_action :signed_in

  def index
    # TODO: Too much logic in index.html.erb
    @order = {
      'approved is NULL' => 'Waiting for Staff Approval',
      'user_approval is NULL and approved is TRUE' => 'Waiting for user Approval',
      'user_approval is TRUE and approved is TRUE and printed is NULL' => 'Waiting to be printed',
      'user_approval is TRUE and approved is TRUE and printed is TRUE' => 'Printed',
      'user_approval is FALSE or approved is FALSE' => 'Disapproved'
    }

    @print_order = if @user.staff? || @user.admin?
                     PrintOrder.all.order(expedited: :desc, created_at: :asc)
                   else
                     @user.print_orders.order(expedited: :desc, created_at: :desc)
                   end
  end

  def index_new
    @order = {
        # Postgresql request => [Completed steps, current step, [next steps ("" if none)]]
        'approved is NULL' => ["Waiting on Admin's approval", ["Waiting on your approval", "Queued to be printed", "Printed"]],
        'user_approval is NULL and approved is TRUE' => ["Approved by Admins", "Waiting on your approval", ["Queued to be printed", "Printed"]],
        'user_approval is TRUE and approved is TRUE and staff_id is NULL and printed is NULL' => ["Approved by Admins", "Approved by you", "Queued to be printed", "Currently being printed"],
        'user_approval is TRUE and approved is TRUE and staff_id is NOT NULL and printed is NULL' => ["Approved by Admins", "Approved by you", "Queue is done", "Currently being printed", ""],
        "user_approval is TRUE and approved is TRUE and staff_id is NOT NULL and printed is TRUE and updated_at > NOW() - INTERVAL '7 days'" => ["Approved by Admins", "Approved by you", "Queue is done", "Printed", ""],
        "approved is FALSE and updated_at > NOW() - INTERVAL '7 days'" => ["Disapproved by admins", ""],
        "user_approval is FALSE and updated_at > NOW() - INTERVAL '7 days'" => ["Approved by admins", "Disapproved by you", ""]
    }

    @order_old = {
        "user_approval is TRUE and approved is TRUE and staff_id is NOT NULL and printed is TRUE and updated_at < NOW() - INTERVAL '7 days'" => ["Approved by Admins", "Approved by you", "Queue is done", "Printed", ""],
        "approved is FALSE and updated_at < NOW() - INTERVAL '7 days'" => ["Disapproved by admins", ""],
        "user_approval is FALSE and updated_at < NOW() - INTERVAL '7 days'" => ["Approved by admins", "Disapproved by you", ""]
    }

    @print_order = @user.print_orders.order(expedited: :desc, created_at: :desc)
  end

  def new
    @print_order = PrintOrder.new
    prices = if (@user.identity == 'undergrad') || (@user.identity == 'grad') || (@user.identity == 'faculty_member')
               [0.15, 0.2, 0.25, 0.28, 0.38, 0.47, 15, 0.53, 5.82, 2.99, 3, 4, 15, 18]
             else
               [0.3, 0.4, 0.5, 0.56, 0.76, 0.94, 30, 0.53, 5.82, 2.99, 3, 4, 15, 18]
             end
    @table = if params[:type] == 'laser'
               [
                 ['Laser - mdf 1/8" (Per Sheet)', prices[10], 15],
                 ["Laser - mdf 1/4\" (Per Sheet)\t", prices[11], 15],
                 ['Laser - acrylic 1/8" (Per Sheet)', prices[12], 15],
                 ['Laser - acrylic 1/4" (Per Sheet)', prices[13], 15]
               ]
             else
               [
                 ['3D Low (PLA/ABS), (per g)', prices[0], 10],
                 ['3D Medium (PLA/ABS), (per g)', prices[1], 10],
                 ['3D High (PLA/ABS), (per g)', prices[2], 10],
                 ['3D Low (Other Materials), (per g)', prices[3], 10],
                 ['3D Medium (Other Materials), (per g)', prices[4], 10],
                 ['3D High (Other Materials), (per g)', prices[5], 10],
                 ['SST Printer (Per Hour)', prices[6], 10],
                 ['M2 Onyx (per cm3)', prices[7], 10],
                 ['M2 Carbon Fiber (per cm3)', prices[8], 10],
                 ["M2 Fiberglass (per cm3)\t", prices[9], 10]
               ]
             end
  end

  def create
    if params[:print_order][:material] && params[:print_order][:comments]
      params[:print_order][:comments] = params[:print_order][:material].to_s + ', ' + params[:print_order][:comments].to_s
    end

    params[:print_order][:sst] = 'true' if params[:print_order][:material] == 'SST'

    if params[:print_order][:comments] && (params[:print_order][:comments_box] != '')
      params[:print_order][:comments] = params[:print_order][:comments].to_s + ', ' + params[:print_order][:comments_box].to_s
    end

    @print_order = PrintOrder.create(print_order_params)
    if @print_order.id.nil? || @print_order.id == 0
      redirect_to index_new_print_orders_path, alert: 'The upload as failed ! Make sure the file types are STL for 3D Printing or SVG and PDF for Laser Cutting !'
    else
      MsrMailer.send_print_to_makerspace(@print_order.id).deliver_now
      redirect_to index_new_print_orders_path, notice: 'The print order has been sent for admin approval, you will receive an email in the next few days, once the admins made a decision.'
    end
  end

  def update
    # Surcharge for expedited services
    expedited_price = 20

    @print_order = PrintOrder.find(params[:id])

    params[:print_order][:timestamp_approved] = DateTime.now if params[:print_order][:timestamp_approved]

    if params[:print_order][:price_per_hour] && params[:print_order][:material_cost] && params[:print_order][:service_charge]
      params[:print_order][:quote] = params[:print_order][:service_charge].to_f + params[:print_order][:price_per_hour].to_f + params[:print_order][:material_cost].to_f
      if @print_order.expedited == true
        params[:print_order][:quote] = params[:print_order][:quote].to_f + expedited_price.to_f
      end
    elsif params[:print_order][:price_per_hour] && params[:print_order][:hours] && params[:print_order][:service_charge]
      params[:print_order][:quote] = params[:print_order][:service_charge].to_f + (params[:print_order][:price_per_hour].to_f * params[:print_order][:hours].to_f)
      if @print_order.expedited == true
        params[:print_order][:quote] = params[:print_order][:quote].to_f + expedited_price.to_f
      end

    elsif params[:print_order][:price_per_gram] && params[:print_order][:grams] && params[:print_order][:service_charge]
      if @print_order.material == "M2 Onyx"
        params[:print_order][:quote] = params[:print_order][:service_charge].to_f + (params[:print_order][:grams].to_f * params[:print_order][:price_per_gram].to_f) + (params[:print_order][:grams_fiberglass].to_f * params[:print_order][:price_per_gram_fiberglass].to_f) + (params[:print_order][:grams_carbonfiber].to_f * params[:print_order][:price_per_gram_carbonfiber].to_f)
      else
        params[:print_order][:quote] = params[:print_order][:service_charge].to_f + (params[:print_order][:grams].to_f * params[:print_order][:price_per_gram].to_f)
      end
      if @print_order.expedited == true
        params[:print_order][:quote] = params[:print_order][:quote].to_f + expedited_price.to_f
      end
    end

    @user = @print_order.user
    @print_order.update(print_order_params)

    if params[:print_order][:approved] == 'true'
      MsrMailer.send_print_quote(expedited_price, @user, @print_order, params[:print_order][:staff_comments]).deliver_now
    elsif params[:print_order][:approved] == 'false'
      MsrMailer.send_print_disapproval(@user, params[:print_order][:staff_comments], @print_order.file.filename).deliver_now
    elsif params[:print_order][:user_approval] == 'true'
      MsrMailer.send_print_user_approval_to_makerspace(@print_order.id).deliver_now
    elsif params[:print_order][:printed] == 'true'
      unless params[:email_false].present?
        if params[:email_message].present?
          message = params[:email_message].html_safe
        else
          message = "<div>Hi Arthur Fetiveau, <br>Your print has completed and is now available for pickup! Your order ID is and your quoted balance is $. Please visit <a href='https://wiki.makerepo.com/wiki/How_to_pay_for_an_Order'>https://wiki.makerepo.com/wiki/How_to_pay_for_an_Order</a> for information on how to pay for your job and email makerspace@uottawa.ca to arrange for the pick up of your part during weekdays between 9h-17h.<br><br></div><div>Best regards,<br>The Makerspace Team<br></div>".html_safe
        end
        MsrMailer.send_print_finished(@user, @print_order.id, @print_order.quote, message).deliver_now
      end
      MsrMailer.send_invoice(@user.name, @print_order).deliver_now
    end

    if @user.id == @print_order.user_id
      redirect_to index_new_print_orders_path
    else
      redirect_to print_orders_path
    end
  end

  def destroy
    @print_order = PrintOrder.find(params[:id])
    user_id = @print_order.user_id
    @print_order.destroy
    if @user.id == user_id
      redirect_to index_new_print_orders_path
    else
      redirect_to print_orders_path
    end
  end

  def edit
    @print_order = PrintOrder.find(params[:id])
  end

  def invoice
    @print_order = PrintOrder.find(params[:print_order_id])
    @expedited_price = 20
    render pdf: 'file_name', template: 'print_orders/pdf.html.erb' if @print_order.printed == true
  end

  private

  def print_order_params
    params.require(:print_order).permit(:user_id, :hours, :final_file, :sst, :material, :grams, :service_charge, :price_per_gram, :price_per_hour, :material_cost, :timestamp_approved, :order_type, :comments, :approved, :printed, :file, :quote, :user_approval, :staff_comments, :staff_id, :expedited, :comments_for_staff, :grams_carbonfiber, :price_per_gram_carbonfiber, :price_per_gram_fiberglass, :grams_fiberglass)
  end
end
