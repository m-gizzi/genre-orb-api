# frozen_string_literal: true

class TightenEnrichmentIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # Every source column holds one of four values, so Postgres will not choose an index
  # on it alone; it only costs write throughput on the upsert paths.
  SOURCE_INDEXES = { artist_genres: "index_artist_genres_on_source",
                     track_genres: "index_track_genres_on_source", }.freeze

  # Enrichment::Drip orders due rows `retry_after ASC NULLS FIRST`, which the default
  # NULLS LAST index cannot serve — every tick sorted the whole due set instead.
  STALEST_FIRST = { retry_after: "ASC NULLS FIRST" }.freeze

  def up
    SOURCE_INDEXES.each { |table, name| remove_index table, name: name, algorithm: :concurrently }

    # Redundant: the unique [artist_id, source] index already leads with artist_id.
    remove_index :artist_metadata_sources, name: "index_artist_metadata_sources_on_artist_id",
                                           algorithm: :concurrently

    add_index :artist_metadata_sources, %i[source retry_after], order: STALEST_FIRST,
                                                                name: "index_artist_metadata_sources_on_due",
                                                                algorithm: :concurrently
    remove_index :artist_metadata_sources, name: "index_artist_metadata_sources_on_source_and_retry_after",
                                           algorithm: :concurrently
  end

  def down
    add_index :artist_metadata_sources, %i[source retry_after],
              name: "index_artist_metadata_sources_on_source_and_retry_after", algorithm: :concurrently
    remove_index :artist_metadata_sources, name: "index_artist_metadata_sources_on_due", algorithm: :concurrently

    add_index :artist_metadata_sources, :artist_id, name: "index_artist_metadata_sources_on_artist_id",
                                                    algorithm: :concurrently

    SOURCE_INDEXES.each { |table, name| add_index table, :source, name: name, algorithm: :concurrently }
  end
end
