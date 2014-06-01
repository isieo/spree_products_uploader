class CreateSpreeProductUploads < ActiveRecord::Migration
  def change
    create_table :spree_product_uploads do |t|
      t.text :message
      t.boolean :success
      t.string :csv_data_file_name

      t.timestamps
    end
  end
end
