class AddPixFeePercentToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :pix_fee_percent, :decimal, precision: 5, scale: 2, default: 0.0, null: false
  end
end
