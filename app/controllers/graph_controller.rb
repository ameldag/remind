class GraphController < ApplicationController
  def index
    points = QdrantService.all_points(limit: 300)
    @projected = points.empty? ? [] : EmbeddingProjector.project(points)
  end
end


#return json like this:
# [{
#     "id": "51c97ac1-3bd4-4afa-9bc0-efd1bf33af67",
#     "label": "Fiche ProWhy 2024.pdf",
#     "x": 0.22511182501506113,
#     "y": 0.22511182501506113
# }, {
#     "id": "555596a1-20c9-4e0a-a7df-67b86ecb2df7",
#     "label": "Sujet_MiniProjet_DIW3 Out of the Box.docx",
#     "x": -0.4105283884391979,
#     "y": -0.41052838843919787
# }, {
#     "id": "a70c880f-49a2-472f-a686-d89034898002",
#     "label": "Fiche ProWhy 2024.pdf",
#     "x": 0.18541656342413676,
#     "y": 0.18541656342413673
# }]