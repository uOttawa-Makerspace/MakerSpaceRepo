class PrintOrdersController < ApplicationController
  before_action :current_user
  before_action :signed_in

  def index
    #TODO: Too much logic in index.html.erb
      if (@user.staff? || @user.admin?)
        @print_order = PrintOrder.all.order(printed: :desc, expedited: :desc, approved: :desc, user_approval: :desc, created_at: :asc)
      else
        @print_order = @user.print_orders.order(expedited: :desc, created_at: :desc)
      end
    end

    def new
      @print_order = PrintOrder.new
    end

    def create
      if params[:print_order][:material] and params[:print_order][:comments]
        params[:print_order][:comments] = params[:print_order][:material]+", "+params[:print_order][:comments]
      end

      if params[:print_order][:comments] and params[:print_order][:sst]
        if params[:print_order][:sst] == "true"
          params[:print_order][:comments] = "SST, "+params[:print_order][:comments]
        end
      end

      @print_order = PrintOrder.create(print_order_params)
      MsrMailer.send_print_to_makerspace().deliver_now
      redirect_to print_orders_path
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
        MsrMailer.send_print_user_approval_to_makerspace().deliver_now
      elsif params[:print_order][:printed] == "true"
        MsrMailer.send_print_finished(@user, @print_order.file_file_name, @print_order.id).deliver_now
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

    private

    def print_order_params
      params.require(:print_order).permit(:user_id, :hours, :final_file, :sst, :material, :grams, :grams2, :price_per_gram2, :service_charge, :price_per_gram, :price_per_hour, :material_cost, :timestamp_approved, :order_type, :comments, :approved, :printed, :file, :quote, :user_approval, :staff_comments, :staff_id, :expedited)
    end

end
