class AddDeliveryTypeToUser < ActiveRecord::Migration
  def change
    add_column :users, :delivery_type, :string
    add_column :users, :previous_delivery_type, :string
  end
end
