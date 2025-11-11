class AddFeeAmountToPixTransactions < ActiveRecord::Migration[7.1]
  def change
    add_column :pix_transactions, :fee_amount, :integer, default: 0, null: false
  end
end
