# frozen_string_literal: true

class PrintOrdersController < ApplicationController
  before_action :current_user
  before_action :signed_in
  before_action :set_pricing, only: %i[new edit]
  before_action :grant_access, only: ['index']

  $expedited_price = 20 # Surcharge for expedited services
  $clean_part_price = 5 # Surcharge for cleaning the parts

  def index
    # TODO: Too much logic in index.html.erb
    @order = {
      'approved is NULL' => 'Waiting for Staff Approval',
      'user_approval is NULL and approved is TRUE' => 'Waiting for user Approval',
      'user_approval is TRUE and approved is TRUE and printed is NULL' => 'Waiting to be printed',
      'user_approval is TRUE and approved is TRUE and printed is TRUE' => 'Printed',
      'user_approval is FALSE or approved is FALSE' => 'Declined'
    }

    @print_order = if @user.staff? || @user.admin?
                     PrintOrder.filter_by_date(params[:start_date], params[:end_date]).order(expedited: :desc, created_at: :asc).includes(:user, file_attachment: :blob, final_file_attachments: :blob, pdf_form_attachment: :blob)
                   else
                     @user.print_orders.filter_by_date(params[:start_date], params[:end_date]).order(expedited: :desc, created_at: :desc).includes(:user, file_attachment: :blob, final_file_attachments: :blob, pdf_form_attachment: :blob)
                   end
  end

  def index_new
    @order = {
      # Postgresql request => [Completed steps, current step, [next steps ("" if none)]]
      'approved is NULL' => ["Waiting on Admin's approval", ['Waiting on your approval', 'Queued to be printed', 'Printed']],
      'user_approval is NULL and approved is TRUE' => ['Approved by Admins', 'Waiting on your approval', ['Queued to be printed', 'Printed']],
      'user_approval is TRUE and approved is TRUE and staff_id is NULL and printed is NULL' => ['Approved by Admins', 'Approved by you', 'Queued to be printed', 'Currently being printed'],
      'user_approval is TRUE and approved is TRUE and staff_id is NOT NULL and printed is NULL' => ['Approved by Admins', 'Approved by you', 'Queue is done', 'Currently being printed', ''],
      "user_approval is TRUE and approved is TRUE and staff_id is NOT NULL and printed is TRUE and updated_at > NOW() - INTERVAL '7 days'" => ['Approved by Admins', 'Approved by you', 'Queue is done', 'Printed', ''],
      "approved is FALSE and updated_at > NOW() - INTERVAL '7 days'" => ['Declined by admins', ''],
      "user_approval is FALSE and updated_at > NOW() - INTERVAL '7 days'" => ['Approved by admins', 'Declined by you', '']
    }

    @order_old = {
      "user_approval is TRUE and approved is TRUE and staff_id is NOT NULL and printed is TRUE and updated_at < NOW() - INTERVAL '7 days'" => ['Approved by Admins', 'Approved by you', 'Queue is done', 'Printed', ''],
      "approved is FALSE and updated_at < NOW() - INTERVAL '7 days'" => ['Declined by admins', ''],
      "user_approval is FALSE and updated_at < NOW() - INTERVAL '7 days'" => ['Approved by admins', 'Declined by you', '']
    }

    @print_order = @user.print_orders.order(expedited: :desc, created_at: :desc)
  end

  def new
    @print_order = PrintOrder.new
  end

  def edit
    @print_order = PrintOrder.find(params[:id])
    @comments = @print_order.comments.split(",")

    unless @print_order.approved.nil?
      if @user.admin? || @user.staff?
        redirect_to print_orders_path, alert: 'The print order has already been approved by admins, you cannot modify your submission'
      else
        redirect_to index_new_print_orders_path, alert: 'The print order has already been approved by admins, you cannot modify your submission'
      end
    end

  end

  def edit_approval
    @print_order = PrintOrder.find(params[:print_order_id])
    unless @user.admin? && @print_order.approved? && !@print_order.user_approval
      if @user.admin? || @user.staff?
        redirect_to print_orders_path, alert: 'You are not allowed on this page'
      else
        redirect_to index_new_print_orders_path, alert: 'You are not allowed on this page'
      end
    end
  end

  def update_submission
    @print_order = PrintOrder.find(params[:id])

    if params[:remove_files].present?
      removed_files = params[:remove_files]

      @print_order.final_file.each do |file|
        file.purge if removed_files.include? file.filename.to_s
      end
    end

    create_update_quote

    params[:print_order][:comments] = params[:print_order][:comments].split(",").join(" ") if params[:comments].present?

    if params[:print_order][:material] && params[:print_order][:comments]
      unless (params[:print_order][:comments] == '1/8" MDF') || (params[:print_order][:comments] == '1/4" MDF')
        params[:print_order][:comments] = params[:print_order][:material].to_s + ', ' + params[:print_order][:comments].to_s
      end
    end

    params[:print_order][:comments] = params[:print_order][:comments].to_s + ', ' + params[:comments_box].to_s if params[:print_order][:comments] && (params[:comments_box] != '')

    if @print_order.update(print_order_params)
      MsrMailer.send_print_quote($expedited_price, @print_order.user, @print_order, params[:print_order][:staff_comments], $clean_part_price, true).deliver_now if @print_order.approved?
      flash[:notice] = "The print order has been updated!"
    else
      flash[:alert] = "An error as occured when updating the print order..."
    end

    if @print_order.approved.nil?
      if @user.admin? || @user.staff?
        redirect_to print_orders_path
      else
        redirect_to index_new_print_orders_path
      end
    else
      redirect_to print_orders_path
    end

  end

  def create

    if params[:print_order][:material] && params[:print_order][:comments]
      params[:print_order][:comments] = params[:print_order][:material].to_s + ', ' + params[:print_order][:comments].to_s
    end

    if params[:print_order][:comments] && (params[:print_order][:comments_box] != '')
      params[:print_order][:comments] = params[:print_order][:comments].to_s + ', ' + params[:print_order][:comments_box].to_s
    end

    @print_order = PrintOrder.create(print_order_params)

    @print_order.update(sst: true) if params[:print_order][:material] == 'SST'

    if @print_order.id.nil? || @print_order.id == 0
      if @user.admin? || @user.staff?
        redirect_to print_orders_path, alert: 'The upload as failed ! Make sure the file types are STL for 3D Printing or SVG and PDF for Laser Cutting and PDF for the team drawing !'
      else
        redirect_to index_new_print_orders_path, alert: 'The upload as failed ! Make sure the file types are STL for 3D Printing or SVG and PDF for Laser Cutting and PDF for the team drawing !'
      end
    else
      MsrMailer.send_print_to_makerspace(@print_order.id).deliver_now
      redirect_to index_new_print_orders_path, notice: 'The print order has been sent for admin approval, you will receive an email in the next few days, once the admins made a decision.'
    end
  end

  def update
    @print_order = PrintOrder.find(params[:id])

    params[:print_order][:timestamp_approved] = DateTime.now if params[:print_order][:timestamp_approved]
    params[:print_order][:timestamp_printed] = DateTime.now if params[:print_order][:printed]

    create_update_quote

    if @print_order.update(print_order_params)
      if params[:print_order][:approved] == 'true'
        MsrMailer.send_print_quote($expedited_price, @print_order.user, @print_order, params[:print_order][:staff_comments], $clean_part_price, false).deliver_now
      elsif params[:print_order][:approved] == 'false'
        MsrMailer.send_print_declined(@print_order.user, params[:print_order][:staff_comments], @print_order.file.filename).deliver_now
      elsif params[:print_order][:user_approval] == 'true'
        MsrMailer.send_print_user_approval_to_makerspace(@print_order.id).deliver_now
      elsif params[:print_order][:printed] == 'true'
        if params[:email_false].blank?
          if params[:email_message].present?
            message = params[:email_message].html_safe
          else
            message = "<div>Hi #{@print_order.user.name}, <br>Your print has completed and is now available for pickup! Your order ID is #{@print_order.id} and your quoted balance is $. Please visit <a href='https://wiki.makerepo.com/wiki/How_to_pay_for_an_Order'>https://wiki.makerepo.com/wiki/How_to_pay_for_an_Order</a> for information on how to pay for your job and email makerspace@uottawa.ca to arrange for the pick up of your part during weekdays between 9h-17h.<br><br></div><div>Best regards,<br>The Makerspace Team<br></div>".html_safe
          end
          MsrMailer.send_print_finished(@print_order.user, @print_order.id, @print_order.quote, message).deliver_now
        end
        MsrMailer.send_invoice(@print_order.user.name, @print_order).deliver_now
      end
      flash[:notice] = 'Update has been completed !'
    else
      flash[:alert] = 'There has been an error, please make sure the file type is one that is accepted. You can try again later or contact: uottawa.makerepo@gmail.com'
    end

    if (@user.id == @print_order.user_id) && !(@user.admin? || @user.staff?)
      redirect_to index_new_print_orders_path
    else
      redirect_to print_orders_path
    end

  end

  def destroy
    @print_order = PrintOrder.find(params[:id])
    if @user.staff? || @print_order.approved.nil?
      user_id = @print_order.user_id
      @print_order.destroy
      flash[:notice] = "The print order has been cancelled."
    else
      flash[:alert] = "You cannot delete this print order. Please send an email to makerspace@uottawa.ca if you have any questions and add the order ID in the subject of the email."
    end
    if @user.id == user_id
      redirect_to index_new_print_orders_path
    else
      redirect_to print_orders_path
    end
  end

  def invoice
    @print_order = PrintOrder.find(params[:print_order_id])
    @expedited_price = 20
    @clean_part_price = 5
    render pdf: 'file_name', template: 'print_orders/pdf.html.erb'
  end

  private

  def print_order_params
    params.require(:print_order).permit(:user_id, :hours, :sst, :material, :grams, :service_charge, :clean_part, :price_per_gram, :price_per_hour, :material_cost, :timestamp_approved, :order_type, :comments, :approved, :printed, :file, :quote, :user_approval, :staff_comments, :staff_id, :expedited, :comments_for_staff, :grams_carbonfiber, :price_per_gram_carbonfiber, :price_per_gram_fiberglass, :grams_fiberglass, :payed, :picked_up, :pdf_form, :timestamp_printed, final_file: [])
  end

  def set_pricing
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

  def grant_access
    unless current_user.staff? || current_user.admin?
      flash[:alert] = 'You cannot access this area.'
      redirect_to root_path
    end
  end

  def create_update_quote
    params[:print_order][:sst] = 'true' if params[:print_order][:material] == 'SST'

    if params[:print_order][:price_per_hour] && params[:print_order][:material_cost] && params[:print_order][:service_charge]
      params[:print_order][:quote] = params[:print_order][:service_charge].to_f + params[:print_order][:price_per_hour].to_f + params[:print_order][:material_cost].to_f
      params[:print_order][:quote] = params[:print_order][:quote].to_f + $expedited_price.to_f if @print_order.expedited == true
      params[:print_order][:quote] = params[:print_order][:quote].to_f + $clean_part_price.to_f if @print_order.clean_part == true
    elsif params[:print_order][:price_per_hour] && params[:print_order][:hours] && params[:print_order][:service_charge]
      params[:print_order][:quote] = params[:print_order][:service_charge].to_f + (params[:print_order][:price_per_hour].to_f * params[:print_order][:hours].to_f)
      params[:print_order][:quote] = params[:print_order][:quote].to_f + $expedited_price.to_f if @print_order.expedited
      params[:print_order][:quote] = params[:print_order][:quote].to_f + $clean_part_price.to_f if @print_order.clean_part == true
    elsif params[:print_order][:price_per_gram] && params[:print_order][:grams] && params[:print_order][:service_charge]
      if @print_order.material == 'M2 Onyx'
        params[:print_order][:quote] = params[:print_order][:service_charge].to_f + (params[:print_order][:grams].to_f * params[:print_order][:price_per_gram].to_f) + (params[:print_order][:grams_fiberglass].to_f * params[:print_order][:price_per_gram_fiberglass].to_f) + (params[:print_order][:grams_carbonfiber].to_f * params[:print_order][:price_per_gram_carbonfiber].to_f)
      else
        params[:print_order][:quote] = params[:print_order][:service_charge].to_f + (params[:print_order][:grams].to_f * params[:print_order][:price_per_gram].to_f)
      end

      params[:print_order][:quote] = params[:print_order][:quote].to_f + $expedited_price.to_f if @print_order.expedited
      params[:print_order][:quote] = params[:print_order][:quote].to_f + $clean_part_price.to_f if ((@print_order.clean_part == true) && (params[:print_order][:clean_part] == true))
    end
  end

end