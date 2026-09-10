class SearchController < ApplicationController

  # GET /api/search?q=contrat+client
  def index
    query = params[:q].to_s.strip
    return render json: { error: 'Query vide' }, status: 400 if query.blank?

    results = QdrantService.search(query, top_k: params[:limit] || 5)
    stats   = QdrantService.stats

    render json: {
      query: query,
      total: results.size,
      stats: stats,
      results: results
    }
  end

  # GET /api/search/stats
  def stats
    render json: {
      qdrant: QdrantService.stats,
      documents: {
        total: Document.count,
        indexed: Document.indexed.count,
        pending: Document.pending.count,
        last_sync: Document.maximum(:indexed_at)
      }
    }
  end

  # POST /api/search/sync — forcer une sync manuelle
  def sync
    DriveSyncJob.perform_later
    render json: { message: 'Sync lancée en arrière-plan' }
  end

end
