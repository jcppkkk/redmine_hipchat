class HipchatApiV2Changes < ActiveRecord::Migration
  def change
    rename_column :projects, :hipchat_from, :hipchat_endpoint if column_exists?(:projects, :hipchat_from) && !column_exists?(:projects, :hipchat_endpoint)
    add_column :projects, :hipchat_endpoint, :string, :default => "", :null => false if !column_exists?(:projects, :hipchat_endpoint)
  end
end
