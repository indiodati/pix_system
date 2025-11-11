class SetDefaultBalanceCentsOnUsers < ActiveRecord::Migration[7.1]
  def change
    change_column_default :users, :balance_cents, 0
  end
end
