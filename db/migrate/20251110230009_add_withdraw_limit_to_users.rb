class AddWithdrawLimitToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :withdraw_limit, :decimal,
                precision: 10, scale: 2,
                default: 10_000.0, null: false
  end
end
