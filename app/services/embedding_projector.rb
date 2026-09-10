require "numo/narray"

class EmbeddingProjector
  def self.project(points)
    return [] if points.empty?

    vectors = points.map { |p| p[:vector] }.compact
    return [] if vectors.size < 2

    n   = vectors.size
    dim = vectors.first.size

    # 1. Centrer
    mean    = Array.new(dim, 0.0)
    vectors.each { |v| v.each_with_index { |x, i| mean[i] += x / n } }
    centered = vectors.map { |v| v.each_with_index.map { |x, i| x - mean[i] } }

    # 2. PCA simplifiée par projection aléatoire (Random Projection)
    # Équivalent rapide pour la visualisation 2D
    rng  = Random.new(42)
    proj = Array.new(2) { Array.new(dim) { rng.rand * 2 - 1 } }

    # Orthogonaliser les 2 vecteurs (Gram-Schmidt)
    proj[0] = normalize_vec(proj[0])
    proj[1] = gram_schmidt(proj[1], proj[0])

    coords = centered.map do |v|
      [dot(v, proj[0]), dot(v, proj[1])]
    end

    # 3. Normaliser entre -10 et 10 pour Sigma.js
    xs = coords.map { |c| c[0] }
    ys = coords.map { |c| c[1] }
    xs = scale(xs, -10, 10)
    ys = scale(ys, -10, 10)

    # 4. Dédupliquer par file_id
    seen = {}
    points.each_with_index.each_with_object([]) do |(p, i), result|
      file_id = p[:payload]["file_id"] || p[:payload][:file_id]
      next if seen[file_id]
      seen[file_id] = true

      result << {
        id:         file_id,
        label:      p[:payload]["file_name"]  || "Document",
        drive_link: p[:payload]["drive_link"],
        chunks:     count_chunks(points, file_id),
        x:          xs[i].round(4),
        y:          ys[i].round(4)
      }
    end
  end

  private

  def self.dot(a, b)
    a.zip(b).sum { |x, y| x * y }
  end

  def self.normalize_vec(v)
    norm = Math.sqrt(v.sum { |x| x**2 })
    norm < 1e-10 ? v : v.map { |x| x / norm }
  end

  def self.gram_schmidt(v, u)
    proj = dot(v, u)
    orthogonal = v.each_with_index.map { |x, i| x - proj * u[i] }
    normalize_vec(orthogonal)
  end

  def self.scale(arr, min_out, max_out)
    min_in = arr.min
    max_in = arr.max
    range  = (max_in - min_in).abs
    return arr.map { 0.0 } if range < 1e-10
    arr.map { |x| (x - min_in) / range * (max_out - min_out) + min_out }
  end

  def self.count_chunks(points, file_id)
    points.count { |p| (p[:payload]["file_id"] || p[:payload][:file_id]) == file_id }
  end
end