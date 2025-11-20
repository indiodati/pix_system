class RenameWitetecIdToGatewayId < ActiveRecord::Migration[7.1]
  def change
    rename_column :pix_transactions, :witetec_id, :gateway_id
    rename_column :payments,         :witetec_id, :gateway_id
    rename_column :cash_outs,        :witetec_id, :gateway_id
    rename_column :withdrawals,      :witetec_id, :gateway_id
  end
end
