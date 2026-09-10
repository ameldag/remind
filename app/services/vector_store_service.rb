class VectorStoreService

  # ── Créer la collection (une seule fois) ──────────────
  CHUNK_SIZE    = 350   # ~512 tokens
  CHUNK_OVERLAP = 75

  # ── Créer la collection (une seule fois) ──────────────
  def self.create_collection
    QDRANT_CLIENT.collections.create(
      collection_name: COLLECTION_NAME,
      vectors: { size: VECTOR_SIZE, distance: "Cosine" }
    )
    puts "Collection créée"
  rescue => e
    puts "Collection déjà existante : #{e.message}"
  end

  # def self.create_collection
  #   QDRANT_CLIENT.collections.create(
  #     collection_name: COLLECTION_NAME,
  #     vectors: {
  #       size:     VECTOR_SIZE,
  #       distance: "Cosine"
  #     }
  #   )
  #   puts "Collection créée"

  # rescue => e
  #   puts "Collection déjà existante : #{e.message}"
  # end

  # ── Sauvegarder un document (avec chunking)  ───────────────────────────
  def self.save_document(document)
    chunks = chunk_text(document.content)
    puts "#{chunks.size} chunks générés pour doc ##{document.id}"

    points = chunks.map.with_index do |chunk, idx|
      embedding = generate_embedding(chunk[:text])

      {
        # ID unique : on encode doc_id + chunk_index dans un entier
        id:      (document.id * 10_000) + idx,
        vector:  embedding,
        payload: {
          document_id: document.id,
          chunk_index: idx,
          chunks_count: chunks.size,
          title:       document.title,
          file_name:   document.file_name,
          drive_link:  document.drive_link,
          created_at:  document.created_at.iso8601,
          user_id:     document.user_id
        }
      }
    end

    # Upsert par batch de 50 pour ne pas dépasser la limite Qdrant
    points.each_slice(50) do |batch|
      QDRANT_CLIENT.points.upsert(
        collection_name: COLLECTION_NAME,
        points:          batch
      )
    end

    puts "Document #{document.id} indexé en #{chunks.size} chunks"
  end

  # def self.save_document(document)
    
  #   # 1. Générer l'embedding
  #   embedding = generate_embedding(document.content)

  #   # 2. Sauvegarder dans Qdrant
  #   QDRANT_CLIENT.points.upsert(
  #     collection_name: COLLECTION_NAME,
  #     points: [
  #       {
  #         id:      document.id,        # ID de ton modèle Rails
  #         vector:  embedding,
  #         payload: {
  #           title:       document.title,
  #           content:     document.content[0..500],
  #           file_name:   document.file_name,
  #           drive_link:  document.drive_link,
  #           created_at:  document.created_at.iso8601,
  #           user_id:     document.user_id
  #         }
  #       }
  #     ]
  #   )
  #   puts "Document #{document.id} indexé"
  # end
  
  # ── Supprimer tous les chunks d'un document ───────────
  def self.delete_document(document_id)
    QDRANT_CLIENT.points.delete(
      collection_name: COLLECTION_NAME,
      points: {
        filter: {
          must: [{ key: "document_id", match: { value: document_id } }]
        }
      }
    )
    puts "Document #{document_id} supprimé"
  end

  # ── Rechercher ────────────────────────────────────────
  def self.search(query, top_k: 5, score_threshold: 0.3)
    query_vec = generate_embedding(query)

    raw = QDRANT_CLIENT.points.search(
      collection_name: COLLECTION_NAME,
      vector:          query_vec,
      limit:           top_k,
      with_payload:    true,
      score_threshold: score_threshold
    )

    # Extraire les points (la gem retourne ["result", [...]])
    points = raw.is_a?(Array) ? raw.last : (raw["result"] || [])

    # Dédupliquer par document (garder le chunk le plus pertinent)
    seen = {}
    points.each do |r|
      payload = r["payload"] || {}
      doc_id  = payload["document_id"]
      score   = r["score"].to_f

      next if seen[doc_id] && seen[doc_id][:score] >= score
      seen[doc_id] = { score: score, payload: payload }
    end

    seen.values
        .sort_by { |r| -r[:score] }
        .map do |r|
          p = r[:payload]
          {
            score:      r[:score].round(3),
            title:      p["title"],
            excerpt:    p["text"]&.first(300),
            file_name:  p["file_name"],
            drive_link: p["drive_link"],
            document_id: p["document_id"],
            chunk_index: p["chunk_index"]
          }
        end
  end
  # def self.search(query, top_k: 5)
  #   query_vec = generate_embedding(query)

  #   results = QDRANT_CLIENT.points.search(
  #     collection_name: COLLECTION_NAME,
  #     vector:          query_vec,
  #     limit:           top_k,
  #     with_payload:    true,
  #     score_threshold: 0.3
  #   )

  #   results.map do |r|
  #     {
  #       score:      r[:score],
  #       title:      r[:payload]["title"],
  #       content:    r[:payload]["content"],
  #       drive_link: r[:payload]["drive_link"],
  #       file_name:  r[:payload]["file_name"],
  #     }
  #   end
  # end

  private

  # ── Chunking par mots avec overlap ───────────────────
  def self.chunk_text(text)
    return [] if text.nil? || text.strip.empty?

    sentences = text.split(/(?<=[.!?])\s+/)   # split par phrases
    chunks    = []
    buffer    = []
    word_count = 0

    sentences.each do |sentence|
      words = sentence.split(/\s+/)

      if word_count + words.size > CHUNK_SIZE && buffer.any?
        chunks << { text: buffer.join(" "), word_count: word_count }

        # Overlap : garder les dernières phrases jusqu'à CHUNK_OVERLAP mots
        overlap_buf   = []
        overlap_words = 0
        buffer.reverse_each do |s|
          w = s.split(/\s+/).size
          break if overlap_words + w > CHUNK_OVERLAP
          overlap_buf.prepend(s)
          overlap_words += w
        end

        buffer     = overlap_buf
        word_count = overlap_words
      end

      buffer << sentence
      word_count += words.size
    end

    chunks << { text: buffer.join(" "), word_count: word_count } if buffer.any?
    chunks
  end

  # ── Générer un embedding via OpenAI ──────────────────
  def self.generate_embedding(text)
    raise "Missing OPENAI_API_KEY" if ENV["OPENAI_API_KEY"].nil?

    @client ||= OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])

    response = @client.embeddings(
      parameters: { model: "text-embedding-3-small", input: text }
    )
    response.dig("data", 0, "embedding")
  rescue Faraday::TooManyRequestsError
    sleep(2)
    retry
  end

  # ── Générer un embedding via OpenAI ──────────────────
  # def self.generate_embedding(text)
  #   key = ENV["OPENAI_API_KEY"]
  #   raise "Missing OPENAI_API_KEY" if key.nil?
  
  #   @client ||= OpenAI::Client.new(access_token: key)

  #   response = @client.embeddings(
  #     parameters: {
  #       model: "text-embedding-3-small",
  #       input: text
  #     }
  #   )
  #   response.dig("data", 0, "embedding")
  # rescue Faraday::TooManyRequestsError
  #   sleep(2)
  #   retry
  # end

end