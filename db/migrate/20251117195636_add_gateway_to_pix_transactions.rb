class AddGatewayToPixTransactions < ActiveRecord::Migration[7.1]
  def change
    add_column :pix_transactions, :gateway, :integer, default: 0, null: false
    add_index  :pix_transactions, :gateway
  end
end
