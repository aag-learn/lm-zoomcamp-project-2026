class Chunk < ApplicationRecord
  belongs_to :ansible_module

  has_neighbors :embedding

  def self.search(query)
    tsquery = sanitize_sql_array([ "plainto_tsquery('english', ?)", query ])

    where("search_text @@ #{tsquery}")
      .order(Arel.sql("ts_rank(search_text, #{tsquery}) DESC"))
  end
end
