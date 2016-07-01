if File.exist?(Rails.root.join('config','spree_products_uploader.yml'))
  SPREE_PRODUCTS_UPLOADER_CONFIG = YAML.load(File.open(Rails.root.join('config','spree_products_uploader.yml')))
  SPREE_PRODUCTS_UPLOADER_CONFIG.symbolize_keys!
else
  SPREE_PRODUCTS_UPLOADER_CONFIG ={:delimiter=>",",
 :quote_char=>"\"",
 :product_sku=>"Product SKU",
 :variant_sku=>"Variant SKU",
 :name=>"Name",
 :description=>"Description",
 :price=>"Price",
 :taxon_parent=>"Taxonomy",
 :taxons=>["Taxon 1", "Taxon 2"],
 :product_preferences=>{"unit_of_mesure"=>"uom"},
 :variant_option_types=>{"model"=>"model", "size"=>"Size"},
 :image_base_url=>"http://myimagehost.com/product_images",
 :images=>["image_file_name"],
 :shipping_category=>"Shipping Category",
 :available_on=>"ITEM FROM DATE",
 :stock=>"Stock Count",
 :stock_location=>"Warehouse Code",
 :enabled=> "enabled",
 :delete=> "delete",
 :image_file_is_sku_jpg=> true,
 :skip_image=> "skip_image"
  }

end
