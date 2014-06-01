module Spree
  module Admin
    class ProductUploadsController < ResourceController
      helper 'spree/products'

      def index
        respond_with(@collection) do |format|
          format.html
        end
      end

    end
  end
end
