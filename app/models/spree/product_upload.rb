module Spree
  class ProductUpload < ActiveRecord::Base
    has_attached_file :csv_data, storage: :filesystem
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
      puts "Creating Product"
      c = self.config
      puts params.inspect

      if params[c[:delete]] == 'yes'
        v = Variant.where(sku: params[c[:variant_sku]])
        puts "Deleting #{params[c[:variant_sku]]}"
        if !v.blank?
          variant_is_master = v.first.is_master?
          if variant_is_master
            if v.first.product.variants.count > 0
              v.first.delete
              v.first.product.variants.first.update(:is_master => true)
            else
              v.first.product.delete
            end
          end
          v.each do |vr|
            vr.stock_items.each do |si|
              si.set_count_on_hand(0)  # set items to 0 if not available.
              si.update(backorderable: false)
            end
            vr.delete
          end
          return
        end
        return
      end
      return if !params[c[:price]] || params[c[:price]].empty?
      return if !params[c[:variant_sku]] || params[c[:variant_sku]].empty?
      puts "sku: #{params[c[:variant_sku]]}"

      stock_location = nil
      if params[c[:stock_location]]
        stock_location = Spree::StockLocation.where(admin_name: params[c[:stock_location]]).first
        Spree::StockLocation.create(admin_name: params[c[:stock_location]],name: params[c[:stock_location]]) if stock_location.nil?
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
        puts "Variant Exist for identifier: #{identifier}"
        return if params[c[:delete]] == 'yes'
        #return if params[c[:description]].blank?
        return if !params[c[:enabled]] || params[c[:enabled]].downcase == 'n' || params[c[:enabled]].downcase == 'false'
        product = Spree::Product.create(name: params[c[:name]],
                                        description: params[c[:description]] || '',
                                        shipping_category_id: shipping_category.id,
                                        price: params[c[:price]],
                                        sku: params[c[:variant_sku]],
                                       )
        if c[:skip_image].blank?
          image = URI.parse("#{c[:image_base_url]}/#{image_file_name}")
          if params[c[:images].first]
            begin
              Spree::Image.create({:attachment => image,
                                   :viewable => product
                                   })
            rescue
            end
          end
        end

        variant = product.master
      else
        product = nil
        variant = nil
        if params[c[:product_sku]].nil? && !Variant.where(sku: params[c[:variant_sku]]).first.try('is_master?')
          if params[c[:delete]] == 'yes'
            puts "Deleting #{params[c[:variant_sku]]}"
            Variant.where(sku: params[c[:variant_sku]]).each{|v| v.delete}
            return
          end
          #no identifier but variant matched and not a master, promote to product
          #return if params[c[:description]].blank?
          return if !params[c[:enabled]] || params[c[:enabled]].downcase == 'n' || params[c[:enabled]].downcase == 'false'
          Variant.where(sku: params[c[:variant_sku]]).first.try(:delete) # remove this variant.
          product = Spree::Product.create(name: params[c[:name]],
                                          description: params[c[:description]] || '',
                                          shipping_category_id: shipping_category.id,
                                          price: params[c[:price]],
                                          sku: params[c[:variant_sku]],
                                         )
          variant = product.master
        else
          puts "variant exist skip product creation"

          if params[c[:delete]] == 'yes'
            v = Variant.where(sku: params[c[:variant_sku]])
            puts "Deleting #{params[c[:variant_sku]]}"
            if !v.blank?
              variant_is_master = v.first.is_master?
              v.each{|v| v.delete}
              if variant_is_master
                if v.first.product.variants.count > 0
                  v.first.delete
                  v.first.product.variant.first.update(:master, true)
                else
                  v.first.product.delete
                end
              end
              return
            end
          end

          product = Variant.where(variant_query[:sku].matches("#{identifier}%")).first.product
          variant = nil
          v_search = product.variants_including_master.where(sku: params[c[:variant_sku]])
          if v_search.count > 0
            variant = v_search.first
          else
            variant = product.variants_including_master.create(sku: params[c[:variant_sku]])
          end
          variant.price = params[c[:price]]  if params[c[:price]] && !params[c[:price]].blank?
          product.price = params[c[:price]]  if params[c[:price]] && !params[c[:price]].blank? && product.variants.count == 1
          product.name = params[c[:name]] if params[c[:name]] && !params[c[:name]].blank?
          product.description = params[c[:description]] if params[c[:description]] && !params[c[:description]].blank?
        end
        puts "Starting Image Import (Skip?: #{!params[c[:skip_image]].blank?})"
        if params[c[:skip_image]].blank?
          image = URI.parse("#{c[:image_base_url]}/#{image_file_name}")
          if image_file_name
            puts "importing image #{c[:image_base_url]}/#{image_file_name}"
            begin
              image_handler = nil
              if variant.images.first && !variant.is_master?
                puts "Variant Image Exist, replacing"
                image_handler  = variant.images.first
                image_handler.attachment = image
                image_handler.save
              elsif variant.is_master? && variant.product.images.first
                puts "Product Image Exist, replacing"
                image_handler  = variant.product.images.first
                image_handler.attachment = image
                image_handler.save
              else
                if !variant.is_master?
                  puts "Creating Variant Image"
                  variant.images.create({:attachment => image})
                else
                  puts "Creating Master Image"
                  product.images.create({:attachment => image})
                end
              end
            rescue Exception => e
              puts "error saving image from #{c[:image_base_url]}/#{image_file_name}, #{e.message}"
            end
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
        variant.delete
        variant.stock_items.each do |si|
          si.set_count_on_hand(0)  # set items to 0 if not available.
        end
      elsif stock_location
        stock = variant.stock_items.where(stock_location_id: stock_location.id).first
        stock = variant.stock_items.first if stock.nil?
        stock.set_count_on_hand(params[c[:stock]]) if stock

        variant.save!
      else
        variant.save!
      end

      if !params[c[:enabled]] || params[c[:enabled]].downcase == 'n' || params[c[:enabled]].downcase == 'false'
        product.available_on = Date.today + 90.years
      else

        product.taxons = [taxon]
        if params[c[:available_on]]
          parsed_date = Date.strptime(params[c[:available_on]],'%d.%m.%y') rescue(Date.today - 1.day)
          product.available_on = parsed_date || Date.today - 1.day
        else
            product.available_on = Date.today - 1.day
        end
      end
      product.price = params[c[:price]] if product.price.blank? || product.variants.count == 1
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
