module Spree
  class ProductUploadWorker
    include ::Sidekiq::Worker

    def perform(product_upload_id)
      p= ProductUpload.find(product_upload_id)
      p.import!
    end
  end
end
