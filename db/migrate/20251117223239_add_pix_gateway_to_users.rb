class AddPixGatewayToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :pix_gateway, :string, null: false, default: "witetec"
  end
end
