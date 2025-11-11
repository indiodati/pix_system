class AddWitetecIdToPixTransactions < ActiveRecord::Migration[7.1]
  def change
    add_column :pix_transactions, :witetec_id, :string
    add_index  :pix_transactions, :witetec_id
  end
end
