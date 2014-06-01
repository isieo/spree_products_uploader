module Spree
  class ProductUpload < ActiveRecord::Base
    has_attached_file :csv_data

    def config
      {
        delimiter: "\t",
        product_sku: "WEB IDENTIFIER SKU",
        variant_sku: "Item No.",
        description: "Item Description",
        taxon_parent: "Categories",
        price: "Retail Price",
        taxons: ["Item Group Name 1","WEB PRODUCT GROUP 1","WEB PRODUCT GROUP 2"],
        product_preferences: [{unit_of_mesure: "Sales UoM"}],
        variant_option_types: {model: "WEB ITEM MODEL",size: "WEB ITEM SIZE"},
        image_base_url: "http://localhost/spree_product_images",
        images: ["WEB PHOTO"],
        shipping_category: "WEB Shipping Category",
        available_on: "WEB ITEM FROM DATE",
      }
    end

    def import!
      require 'csv'
      #begin
        Spree::Product.transaction do
          self.config[:variant_option_types].each do|k,v|
            next if k.blank?
            OptionType.find_or_create_by(name: k, presentation: k.to_s.humanize)
          end

          ::CSV.foreach(self.csv_data_file_name,headers: true, col_sep: self.config[:delimiter]) do |row|
            create_product(row)
          end
        end
  #    rescue Exception => exp
    #    error_message = "An error occurred during import. (#{exp.message})\n#{exp.backtrace.join('\n')}"
    #    self.message = error_message
  #      raise error_message
    #  end
    end

    def create_product(params)
      c = self.config
      return if !params[c[:variant_sku]] || params[c[:variant_sku]].empty?
      puts "sku: #{params[c[:variant_sku]]}"
      variant_query = Arel::Table.new(:spree_variants)
      product = nil
      variant = nil
      taxonomy = Spree::Taxonomy.where(name: c[:taxon_parent]).first
      master_taxon = taxonomy.taxons.where(parent_id: nil).first
      parent_taxon = master_taxon
      taxon = nil
      c[:taxons].each do |t|
        next if !params[t] || params[t].blank?
        taxon = parent_taxon.children.find_or_create_by(name: params[t],taxonomy_id: taxonomy.id)
        parent_taxon = taxon
      end
      shipping_category = ShippingCategory.where(name: (c[:shipping_category] || "Default")).first
      shipping_category = ShippingCategory.first if shipping_category.nil?

      identifier = params[c[:product_sku]] || params[c[:variant_sku]].split('-').try(:first)

      if !Variant.where(variant_query[:sku].matches("#{identifier}%")).exists?
        product = Spree::Product.create(name: params[c[:description]],
                                        shipping_category_id: shipping_category.id,
                                        price: params[c[:price]],
                                        sku: params[c[:variant_sku]],
                                       )
        image = fetch_remote_image("#{c[:image_base_url]}/#{params[c[:images].first]}")
        if image != false
          begin
            product.images.create({:attachment => image,
                                      :viewable => product,
                                      :position => 0
                                      })
          rescue
          end
        end

        variant = product.master
      else
        #variant exist skip product creation
        product = Variant.where(variant_query[:sku].matches("#{identifier}%")).first.product
        variant = product.variants.find_or_create_by(sku: params[c[:variant_sku]])
        variant.price = params[c[:price]]  if params[c[:price]] && !params[c[:price]].blank?
        product.name = params[c[:description]] if params[c[:description]] && !params[c[:description]].blank?
        image = fetch_remote_image("#{c[:image_base_url]}/#{params[c[:images].first]}")
        if image != false
          begin
            variant.images.create({:attachment => image,
                                      :viewable => variant,
                                      :position => 0
                                      })
          rescue
          end
        end
      end

      option_values = []
      self.config[:variant_option_types].each do|k,v|
        next if k.blank? || params[v].blank?
        option_type = OptionType.find_or_create_by(name: k, presentation: k.to_s.humanize)
        option_values << option_type.option_values.find_or_create_by(name: params[v], presentation: params[v].humanize)
      end
      variant.option_values = option_values
      variant.save!
      product.taxons = [taxon]
      product.available_on = Date.strptime(params[c[:available_on]],'%d.%m.%y') || Date.today - 1.day
      product.price = params[c[:price]] if product.price.blank?
      product.save!
    end

    def fetch_remote_image(filename)
      begin
        open(filename)
      rescue OpenURI::HTTPError => error
        return false
      rescue
        return false
      end
    end

  end
end
