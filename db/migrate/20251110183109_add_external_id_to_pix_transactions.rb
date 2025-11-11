class AddExternalIdToPixTransactions < ActiveRecord::Migration[7.1]
  def change
    add_column :pix_transactions, :external_id, :string
    add_index  :pix_transactions, :external_id, unique: true
  end
end
