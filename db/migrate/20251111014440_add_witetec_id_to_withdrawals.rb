class AddWitetecIdToWithdrawals < ActiveRecord::Migration[7.0]
  def change
    add_column :withdrawals, :witetec_id, :string
    add_index  :withdrawals, :witetec_id
  end
end
