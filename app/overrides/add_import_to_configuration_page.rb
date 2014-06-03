Deface::Override.new(:virtual_path => "spree/admin/shared/_configuration_menu",
                     :name => "add_product_uploader_link_configuration_menu",
                     :insert_bottom => "[data-hook='admin_configurations_sidebar_menu']",
                     :text => %q{<%= configurations_sidebar_menu_item "Import Products", spree.admin_product_uploads_url %>},
                     :disabled => false)
