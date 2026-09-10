# config/initializers/qdrant.rb
require 'qdrant'

QDRANT            = Qdrant::Client.new(url: ENV.fetch("QDRANT_URL", "http://localhost:6333"))
QDRANT_COLLECTION = ENV.fetch("QDRANT_COLLECTION", "drive_documents_axsens")
VECTOR_SIZE       = 1024   # mistral-embed = 1024 dimensions

# Créer la collection seulement si elle n'existe pas
begin
  existing = QDRANT.collections.list
  names    = existing.dig(:result, :collections)&.map { |c| c[:name] } || []

  if names.include?(QDRANT_COLLECTION)
    Rails.logger.info "Collection '#{QDRANT_COLLECTION}' déjà existante — OK"
  else
    QDRANT.collections.create(
      collection_name: QDRANT_COLLECTION,
      vectors: { size: VECTOR_SIZE, distance: "Cosine" }
    )
    Rails.logger.info "Collection '#{QDRANT_COLLECTION}' créée"
  end
rescue => e
  Rails.logger.error "Qdrant non disponible : #{e.message}"
end