# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_03_031458) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "album_artists", force: :cascade do |t|
    t.bigint "album_id", null: false
    t.bigint "artist_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["album_id", "artist_id"], name: "index_album_artists_on_album_id_and_artist_id", unique: true
    t.index ["album_id"], name: "index_album_artists_on_album_id"
    t.index ["artist_id"], name: "index_album_artists_on_artist_id"
  end

  create_table "albums", force: :cascade do |t|
    t.string "artwork_url"
    t.datetime "created_at", null: false
    t.integer "release_year"
    t.string "spotify_id", null: false
    t.string "title", null: false
    t.integer "total_tracks"
    t.datetime "updated_at", null: false
    t.index ["release_year"], name: "index_albums_on_release_year"
    t.index ["spotify_id"], name: "index_albums_on_spotify_id", unique: true
    t.index ["title"], name: "index_albums_on_title"
  end

  create_table "artists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "image_url"
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.string "spotify_id", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_artists_on_name"
    t.index ["spotify_id"], name: "index_artists_on_spotify_id", unique: true
  end

  create_table "genres", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_genres_on_name", unique: true
  end

  create_table "playlist_tracks", force: :cascade do |t|
    t.datetime "added_at"
    t.datetime "created_at", null: false
    t.bigint "playlist_id", null: false
    t.integer "position", null: false
    t.bigint "track_id", null: false
    t.datetime "updated_at", null: false
    t.index ["added_at"], name: "index_playlist_tracks_on_added_at"
    t.index ["playlist_id", "position"], name: "index_playlist_tracks_on_playlist_id_and_position"
    t.index ["playlist_id", "track_id"], name: "index_playlist_tracks_on_playlist_id_and_track_id", unique: true
    t.index ["playlist_id"], name: "index_playlist_tracks_on_playlist_id"
    t.index ["track_id"], name: "index_playlist_tracks_on_track_id"
  end

  create_table "playlist_versions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "playlist_id", null: false
    t.integer "track_count", default: 0, null: false
    t.bigint "track_ids", default: [], array: true
    t.datetime "updated_at", null: false
    t.integer "version_number", null: false
    t.index ["playlist_id", "version_number"], name: "index_playlist_versions_on_playlist_id_and_version_number", unique: true
    t.index ["playlist_id"], name: "index_playlist_versions_on_playlist_id"
    t.index ["track_ids"], name: "index_playlist_versions_on_track_ids", using: :gin
  end

  create_table "playlists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_liked_songs", default: false, null: false
    t.boolean "is_public", default: false, null: false
    t.string "name", null: false
    t.string "snapshot_id"
    t.string "spotify_id"
    t.integer "track_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["snapshot_id"], name: "index_playlists_on_snapshot_id"
    t.index ["spotify_id"], name: "index_playlists_on_spotify_id", unique: true, where: "(spotify_id IS NOT NULL)"
    t.index ["user_id", "is_liked_songs"], name: "index_playlists_on_user_id_and_is_liked_songs"
    t.index ["user_id"], name: "index_playlists_on_user_id"
  end

  create_table "service_connections", force: :cascade do |t|
    t.text "access_token", null: false
    t.datetime "created_at", null: false
    t.jsonb "profile_data", default: {}
    t.text "refresh_token"
    t.integer "service_type", null: false
    t.string "service_user_id", null: false
    t.datetime "token_expires_at"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["service_type", "service_user_id"], name: "index_service_connections_on_service_type_and_service_user_id", unique: true
    t.index ["user_id", "service_type"], name: "index_service_connections_on_user_id_and_service_type", unique: true
    t.index ["user_id"], name: "index_service_connections_on_user_id"
  end

  create_table "smart_playlist_sources", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "playlist_id", null: false
    t.bigint "smart_playlist_id", null: false
    t.datetime "updated_at", null: false
    t.index ["playlist_id"], name: "index_smart_playlist_sources_on_playlist_id"
    t.index ["smart_playlist_id", "playlist_id"], name: "idx_smart_playlist_sources_unique", unique: true
    t.index ["smart_playlist_id"], name: "index_smart_playlist_sources_on_smart_playlist_id"
  end

  create_table "smart_playlists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_enabled", default: true, null: false
    t.datetime "last_evaluated_at"
    t.datetime "last_pushed_at"
    t.integer "match_count", default: 0, null: false
    t.string "name", null: false
    t.jsonb "rules", default: {}, null: false
    t.bigint "target_playlist_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["is_enabled"], name: "index_smart_playlists_on_is_enabled"
    t.index ["last_evaluated_at"], name: "index_smart_playlists_on_last_evaluated_at"
    t.index ["target_playlist_id"], name: "index_smart_playlists_on_target_playlist_id"
    t.index ["user_id", "name"], name: "index_smart_playlists_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_smart_playlists_on_user_id"
  end

  create_table "track_artists", force: :cascade do |t|
    t.bigint "artist_id", null: false
    t.datetime "created_at", null: false
    t.bigint "track_id", null: false
    t.datetime "updated_at", null: false
    t.index ["artist_id"], name: "index_track_artists_on_artist_id"
    t.index ["track_id", "artist_id"], name: "index_track_artists_on_track_id_and_artist_id", unique: true
    t.index ["track_id"], name: "index_track_artists_on_track_id"
  end

  create_table "track_genres", force: :cascade do |t|
    t.float "confidence", default: 1.0, null: false
    t.datetime "created_at", null: false
    t.bigint "genre_id", null: false
    t.bigint "track_id", null: false
    t.datetime "updated_at", null: false
    t.index ["confidence"], name: "index_track_genres_on_confidence"
    t.index ["genre_id"], name: "index_track_genres_on_genre_id"
    t.index ["track_id", "genre_id"], name: "index_track_genres_on_track_id_and_genre_id", unique: true
    t.index ["track_id"], name: "index_track_genres_on_track_id"
  end

  create_table "tracks", force: :cascade do |t|
    t.bigint "album_id", null: false
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.boolean "explicit", default: false, null: false
    t.jsonb "metadata_overrides", default: {}
    t.integer "popularity"
    t.string "preview_url"
    t.string "spotify_id", null: false
    t.string "title", null: false
    t.integer "track_number"
    t.datetime "updated_at", null: false
    t.index ["album_id"], name: "index_tracks_on_album_id"
    t.index ["explicit"], name: "index_tracks_on_explicit"
    t.index ["popularity"], name: "index_tracks_on_popularity"
    t.index ["spotify_id"], name: "index_tracks_on_spotify_id", unique: true
    t.index ["title"], name: "index_tracks_on_title"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "registration_source", default: 0, null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "album_artists", "albums"
  add_foreign_key "album_artists", "artists"
  add_foreign_key "playlist_tracks", "playlists"
  add_foreign_key "playlist_tracks", "tracks"
  add_foreign_key "playlist_versions", "playlists"
  add_foreign_key "playlists", "users"
  add_foreign_key "service_connections", "users"
  add_foreign_key "smart_playlist_sources", "playlists"
  add_foreign_key "smart_playlist_sources", "smart_playlists"
  add_foreign_key "smart_playlists", "playlists", column: "target_playlist_id"
  add_foreign_key "smart_playlists", "users"
  add_foreign_key "track_artists", "artists"
  add_foreign_key "track_artists", "tracks"
  add_foreign_key "track_genres", "genres"
  add_foreign_key "track_genres", "tracks"
  add_foreign_key "tracks", "albums"
end
