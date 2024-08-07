class RemoveShortformFromPrinterNumbers < ActiveRecord::Migration[7.0]
  def change
    reversible do |direction|
      direction.up do
        Printer.all.each do |p|
          p.update(number: p.number.split("-").last.squish) # remove short form
        end
      end
    end
  end
end
