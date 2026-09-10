require 'set'
class QdrantService

  # ── Indexer un document complet ───────────────────────
  def self.index_document(document, chunks, vectors)
    # Supprimer les anciens chunks de ce fichier
    delete_by_file_id(document.file_id)

    points = chunks.each_with_index.map do |chunk, i|
      {
        id:      SecureRandom.uuid,
        vector:  vectors[i],
        payload: {
          document_id:   document.id,
          file_id:       document.file_id,
          file_name:     document.file_name,
          drive_link:    document.drive_link,
          mime_type:     document.mime_type,
          modified_time: document.modified_time&.iso8601,
          chunk_index:   i,
          text:          chunk
        }
      }
    end

    QDRANT.points.upsert(
      collection_name: QDRANT_COLLECTION,
      points:          points
    )
    
    Rails.logger.info "#{points.size} chunks indexés pour #{document.file_name}"
    points.size
  end

  # ── Rechercher ────────────────────────────────────────
  def self.search(query, top_k: 5, score_threshold: 0.3)
    query_vec = EmbeddingService.embed([query]).first
    return [] unless query_vec

    raw = QDRANT.points.search(
      collection_name: QDRANT_COLLECTION,
      vector:          query_vec,
      limit:           top_k,
      with_payload:    true,
      score_threshold: score_threshold
    )
    
    # Extraire les points selon la structure retournée
    points = case raw
             when Array then raw.last   # ["result", [...]] → prend le dernier élément
             when Hash  then raw["result"] || raw[:result] || []
             else []
             end
    
    seen = Set.new
    points.filter_map do |r|
      # r est maintenant un Hash avec des clés string
      payload = r["payload"] || {}
      file_id = payload["file_id"]
    
      next if file_id.nil? || seen.include?(file_id)
      seen.add(file_id)
    
      {
        score:      r["score"]&.round(3),
        file_name:  payload["file_name"],
        drive_link: payload["drive_link"],
        excerpt:    payload["text"]&.first(300),
        file_id:    file_id
      }
    end
  end

  # Récupérer tous les points 
  def self.all_points(limit: 500)
    raw = QDRANT.points.scroll(
      collection_name: QDRANT_COLLECTION,
      limit: limit,
      with_payload: true,
      with_vector: true
    )
    
    points = case raw
    when Array then raw.last   # ["result", [...]] → prend le dernier élément
    when Hash  then raw["result"] || raw[:result] || []
    else []
    end
  
    r = points[:points] || points["points"] || []
  
    r.map do |p|
      {
        id: p[:id] || p["id"],
        vector: p[:vector] || p["vector"],
        payload: p[:payload] || p["payload"]
      }
    end
    
  end
  
  # ── Supprimer les chunks d'un fichier ─────────────────
  def self.delete_by_file_id(file_id)
    QDRANT.points.delete(
      collection_name: QDRANT_COLLECTION,
      filter: {
        must: [{ key: "file_id", match: { value: file_id } }]
      }
    )
  end

  # ── Stats de la collection ────────────────────────────
  def self.stats
    info = QDRANT.collections.get(collection_name: QDRANT_COLLECTION)
    {
      total_vectors:  info.dig(:result, :points_count),
      collection:    QDRANT_COLLECTION
    }
  end

end