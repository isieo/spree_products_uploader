module Spree
  class ProductUpload < ActiveRecord::Base
    has_attached_file :csv_data
    after_commit :start_import, :on => :create
    default_scope ->{order(id: :desc)}
    def config
      SPREE_PRODUCTS_UPLOADER_CONFIG
    end

    def import!
      require 'csv'
      begin
        Spree::Product.transaction do
          self.config[:variant_option_types].each do|k,v|
            next if k.blank?
            OptionType.find_or_create_by(name: k, presentation: k.to_s.humanize)
          end

          ::CSV.foreach(self.csv_data.path,headers: true, col_sep: self.config[:delimiter], quote_char: self.config[:quote_char]) do |row|
            create_product(row)
          end
        end
        self.success = true
        self.message = "Successfully uploaded"
        self.save
      rescue Exception => exp
        error_message = "An error occurred during import. (#{exp.message})\n#{exp.backtrace.join('\n')}"
        self.message = error_message
        self.save
      end
    end

    def create_product(params)
      c = self.config
      return if !params[c[:price]] || params[c[:price]].empty?
      return if !params[c[:variant_sku]] || params[c[:variant_sku]].empty?
      puts "sku: #{params[c[:variant_sku]]}"

      stock_location = nil
      if params[c[:stock_location]]
        stock_location = Spree::StockLocation.find_or_create_by(name: params[c[:stock_location]])
      else
        stock_location = Spree::StockLocation.find_or_create_by(name: "default")
      end

      variant_query = Arel::Table.new(:spree_variants)
      product = nil
      variant = nil
      taxonomy = Spree::Taxonomy.find_or_create_by(name: params[c[:taxon_parent]])
      master_taxon = taxonomy.taxons.where(parent_id: nil).first
      parent_taxon = master_taxon
      taxon = parent_taxon
      image_file_name = params[c[:images].first]
      if c[:image_file_is_sku_jpg] && image_file_name.blank?
        image_file_name = "#{params[c[:variant_sku]]}.jpg"
      end
      c[:taxons].each do |t|
        next if !params[t] || params[t].blank?
        taxon = parent_taxon.children.find_or_create_by(name: params[t],taxonomy_id: taxonomy.id)
        parent_taxon = taxon
      end
      shipping_category = ShippingCategory.where(name: (c[:shipping_category] || "Default")).first
      shipping_category = ShippingCategory.first if shipping_category.nil?

      identifier = params[c[:product_sku]] || params[c[:variant_sku]]

      if !Variant.where(variant_query[:sku].matches("#{identifier}%")).exists?
        return if !params[c[:enabled]] || params[c[:enabled]].downcase == 'n' || params[c[:enabled]].downcase == 'false'
        product = Spree::Product.create(name: params[c[:description]],
                                        shipping_category_id: shipping_category.id,
                                        price: params[c[:price]],
                                        sku: params[c[:variant_sku]],
                                       )
        image = URI.parse("#{c[:image_base_url]}/#{image_file_name}")
        if params[c[:images].first]
          begin
            Spree::Image.create({:attachment => image,
                                 :viewable => product
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
        image = URI.parse("#{c[:image_base_url]}/#{image_file_name}")
        if params[c[:images].first]
          begin
            if product.images.first && params['force_image']
              variant.images.first.attachment = image
            else
              variant.images = Spree::Image.create({:attachment => image,
                                      :viewable => variant
                                      })
            end
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

      if !params[c[:enabled]] || params[c[:enabled]].downcase == 'n' || params[c[:enabled]].downcase == 'false'
        variant.stock_items.each do |si|
          si.set_count_on_hand(0)  # set items to 0 if not available.
        end
      else
        stock = variant.stock_items.where(stock_location_id: stock_location.id).first
        stock.set_count_on_hand(params[c[:stock]])
      end

      variant.save!

      product.taxons = [taxon]
      if params[c[:available_on]]
        product.available_on = Date.strptime(params[c[:available_on]],'%d.%m.%y') || Date.today - 1.day
      else
          product.available_on = Date.today - 1.day
      end
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


    def start_import
      ProductUploadWorker.perform_async(self.id)
    end
  end
end
