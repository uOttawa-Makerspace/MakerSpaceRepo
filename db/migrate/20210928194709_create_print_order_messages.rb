class CreatePrintOrderMessages < ActiveRecord::Migration[6.0]
  def change
    create_table :print_order_messages do |t|
      t.text :name
      t.text :message
      t.timestamps
    end

    JobOrderMessage.create(
      name: "I_Printed_It",
      message:
        "<div>Your print has completed and is now available for pickup! Your order ID is [PRINT_ID] and your quoted balance is [QUOTED_BALANCE]. Please visit <a href='https://wiki.makerepo.com/wiki/How_to_pay_for_an_Order'>https://wiki.makerepo.com/wiki/How_to_pay_for_an_Order</a> for information on how to pay for your job and email makerspace@uottawa.ca to arrange for the pick up of your part during weekdays between 9h-17h.<br><br></div>"
    )
  end
end
