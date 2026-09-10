# app/services/embedding_service.rb
require 'net/http'
require 'json'

class EmbeddingService
  CHUNK_SIZE    = 500
  CHUNK_OVERLAP = 50

  def self.chunk_text(text)
    words  = text.split(/\s+/)
    chunks = []
    i      = 0
    while i < words.length
      chunk = words[i, CHUNK_SIZE].join(' ')
      chunks << chunk unless chunk.strip.empty?
      i += CHUNK_SIZE - CHUNK_OVERLAP
    end
    chunks
  end

  def self.embed(texts)
    uri  = URI("https://api.mistral.ai/v1/embeddings")
    req  = Net::HTTP::Post.new(uri, {
      "Content-Type"  => "application/json",
      "Authorization" => "Bearer #{ENV['MISTRAL_API_KEY']}"
    })
    req.body = {
      model: "mistral-embed",   # 1024 dimensions, gratuit
      input: Array(texts)
    }.to_json

    res  = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 60) do |http|
      http.request(req)
    end

    JSON.parse(res.body)["data"].map { |d| d["embedding"] }
  rescue => e
    Rails.logger.error "Erreur embedding Mistral : #{e.message}"
    []
  end
end