# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::SmartPlaylists" do
  let(:user) { create(:user) }
  let(:create_url) { "#{Spotify::Client::BASE_URL}/users/spotify_user_1/playlists" }

  def connect_spotify(owner = user)
    create(:service_connection, user: owner, service_user_id: "spotify_user_1",
                                access_token: "test_token", token_expires_at: 1.hour.from_now,)
  end

  describe "GET /api/v1/smart_playlists/schema" do
    it "returns 401 when not authenticated" do
      get "/api/v1/smart_playlists/schema"
      expect(response).to have_http_status(:unauthorized)
    end

    context "when authenticated" do
      before { sign_in user }

      it "returns the rule catalog rather than resolving as a show" do
        get "/api/v1/smart_playlists/schema"

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["data"]).to include(
          "max_depth" => Rules::FieldCatalog::MAX_DEPTH,
          "max_nodes" => Rules::FieldCatalog::MAX_NODES,
          "max_string_length" => Rules::FieldCatalog::MAX_STRING_LENGTH,
          "max_list_size" => Rules::FieldCatalog::MAX_LIST_SIZE,
          "match_types" => %w[all any],
        )
      end

      it "describes each field's operators" do
        get "/api/v1/smart_playlists/schema"

        fields = response.parsed_body.dig("data", "fields")
        genre = fields.find { |field| field["key"] == "genre" }

        expect(fields.pluck("key")).to match_array(Rules::FieldCatalog.field_keys)
        expect(genre["suggest"]).to eq("genres")
        expect(genre["operators"]).to include("key" => "in", "label" => "is any of")
      end

      it "carries the value constraints the builder's inputs mirror" do
        get "/api/v1/smart_playlists/schema"

        fields = response.parsed_body.dig("data", "fields")
        popularity = fields.find { |field| field["key"] == "popularity" }

        expect(popularity["constraints"]).to eq("min" => 0, "max" => 100)
      end

      it "asks clients to revalidate rather than trust a cached catalog" do
        get "/api/v1/smart_playlists/schema"

        expect(response.headers["Cache-Control"]).to include("must-revalidate", "private")
        expect(response.headers["ETag"]).to be_present
      end

      it "answers 304 without a body when the client already has this catalog" do
        get "/api/v1/smart_playlists/schema"
        etag = response.headers["ETag"]

        sign_in user
        get "/api/v1/smart_playlists/schema", headers: { "If-None-Match" => etag }

        expect(response).to have_http_status(:not_modified)
        expect(response.body).to be_empty
      end

      it "answers 200 when the catalog has moved on since the client's copy" do
        get "/api/v1/smart_playlists/schema", headers: { "If-None-Match" => 'W/"stale"' }

        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "GET /api/v1/smart_playlists" do
    context "when not authenticated" do
      it "returns 401 unauthorized" do
        get "/api/v1/smart_playlists"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when authenticated" do
      before { sign_in user }

      it "returns only the user's smart playlists in a data/meta envelope" do
        mine = create(:smart_playlist, user: user)
        create(:smart_playlist)

        get "/api/v1/smart_playlists"

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["data"].pluck("id")).to contain_exactly(mine.id)
        expect(response.parsed_body["meta"]).to include("total" => 1)
      end

      it "names each smart playlist after its target playlist" do
        create(:smart_playlist, user: user, target_playlist: create(:playlist, :with_spotify, user: user,
                                                                                              name: "Metal Mix",),)

        get "/api/v1/smart_playlists"

        expect(response.parsed_body["data"].first).to include(
          "name" => "Metal Mix",
          "is_ready" => false,
          "is_enabled" => false,
          "source_count" => 1,
        )
      end

      it "sorts by target playlist name" do
        create(:smart_playlist, user: user, target_playlist: create(:playlist, :with_spotify, user: user,
                                                                                              name: "Zebra",),)
        create(:smart_playlist, user: user, target_playlist: create(:playlist, :with_spotify, user: user,
                                                                                              name: "Alpha",),)

        get "/api/v1/smart_playlists", params: { sort: "name", order: "asc" }

        expect(response.parsed_body["data"].pluck("name")).to eq(%w[Alpha Zebra])
      end

      it "sorts by when each was last pushed, newest first" do
        target = ->(name) { create(:playlist, :with_spotify, user: user, name: name) }
        create(:smart_playlist, :with_rules, target_playlist: target.call("Older"), last_pushed_at: 2.days.ago)
        create(:smart_playlist, :with_rules, target_playlist: target.call("Newer"), last_pushed_at: 1.hour.ago)

        get "/api/v1/smart_playlists", params: { sort: "last_pushed_at", order: "desc" }

        expect(response.parsed_body["data"].pluck("name")).to eq(%w[Newer Older])
      end

      it "puts a never-pushed smart playlist last when sorting by last pushed" do
        target = ->(name) { create(:playlist, :with_spotify, user: user, name: name) }
        create(:smart_playlist, :with_rules, target_playlist: target.call("Never"))
        create(:smart_playlist, :with_rules, target_playlist: target.call("Pushed"), last_pushed_at: 1.hour.ago)

        get "/api/v1/smart_playlists", params: { sort: "last_pushed_at", order: "desc" }

        expect(response.parsed_body["data"].pluck("name")).to eq(%w[Pushed Never])
      end

      it "filters by target playlist name" do
        create(:smart_playlist, user: user, target_playlist: create(:playlist, :with_spotify, user: user,
                                                                                              name: "Metal Mix",),)
        create(:smart_playlist, user: user, target_playlist: create(:playlist, :with_spotify, user: user,
                                                                                              name: "Jazz",),)

        get "/api/v1/smart_playlists", params: { search: "metal" }

        expect(response.parsed_body["data"].pluck("name")).to eq(["Metal Mix"])
      end
    end
  end

  describe "GET /api/v1/smart_playlists/:id" do
    before { sign_in user }

    it "returns the smart playlist with its source playlists" do
      smart_playlist = create(:smart_playlist, user: user)
      source = smart_playlist.source_playlists.first

      get "/api/v1/smart_playlists/#{smart_playlist.id}"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]["source_playlists"].pluck("id")).to contain_exactly(source.id)
      expect(response.parsed_body["data"]["target_playlist"]["id"]).to eq(smart_playlist.target_playlist_id)
    end

    it "names the playlists the rules refer to by id" do
      excluded = create(:playlist, :with_spotify, user: user, name: "Already Heard")
      smart_playlist = create(:smart_playlist, :playlist_rule, user: user, excluded_playlist: excluded)

      get "/api/v1/smart_playlists/#{smart_playlist.id}"

      expect(response.parsed_body["data"]["rule_playlists"])
        .to contain_exactly(hash_including("id" => excluded.id, "name" => "Already Heard"))
    end

    it "reports that a referenced playlist has nothing to match on yet" do
      excluded = create(:playlist, :with_spotify, user: user)
      smart_playlist = create(:smart_playlist, :playlist_rule, user: user, excluded_playlist: excluded)

      get "/api/v1/smart_playlists/#{smart_playlist.id}"

      expect(response.parsed_body["data"]["rule_playlists"].first)
        .to include("sync_enabled" => false, "track_count" => 0)
    end

    it "reports the tracks a synced reference holds" do
      excluded = create(:playlist, :with_spotify, :sync_enabled, :holding, user: user, tracks: [create(:track)])
      smart_playlist = create(:smart_playlist, :playlist_rule, user: user, excluded_playlist: excluded)

      get "/api/v1/smart_playlists/#{smart_playlist.id}"

      expect(response.parsed_body["data"]["rule_playlists"].first)
        .to include("sync_enabled" => true, "track_count" => 1)
    end

    it "returns 404 for another user's smart playlist" do
      get "/api/v1/smart_playlists/#{create(:smart_playlist).id}"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/smart_playlists" do
    let(:source) { create(:playlist, :with_spotify, user: user) }

    context "when not authenticated" do
      it "returns 401 unauthorized" do
        post "/api/v1/smart_playlists", params: { smart_playlist: { target_playlist_id: 1 } }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when converting an existing playlist" do
      let(:target) { create(:playlist, :with_spotify, user: user) }

      before { sign_in user }

      it "creates a draft smart playlist and returns 201" do
        post "/api/v1/smart_playlists",
             params: { smart_playlist: { target_playlist_id: target.id, source_playlist_ids: [source.id] } }

        expect(response).to have_http_status(:created)
        expect(response.parsed_body["data"]).to include("is_enabled" => false, "is_ready" => false)
        expect(response.parsed_body["data"]["source_playlists"].pluck("id")).to contain_exactly(source.id)
        expect(target.reload.sync_enabled).to be(true)
      end

      it "returns 404 for another user's target playlist" do
        post "/api/v1/smart_playlists",
             params: { smart_playlist: { target_playlist_id: create(:playlist).id,
                                         source_playlist_ids: [source.id], } }

        expect(response).to have_http_status(:not_found)
      end

      it "returns 422 when the target already has a smart playlist" do
        create(:smart_playlist, target_playlist: target)

        post "/api/v1/smart_playlists",
             params: { smart_playlist: { target_playlist_id: target.id, source_playlist_ids: [source.id] } }

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "returns 422 when no sources are given" do
        post "/api/v1/smart_playlists",
             params: { smart_playlist: { target_playlist_id: target.id, source_playlist_ids: [] } }

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "returns 422 when no target is given" do
        post "/api/v1/smart_playlists", params: { smart_playlist: { source_playlist_ids: [source.id] } }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["errors"].first["message"]).to eq("A target playlist is required")
      end
    end

    context "when creating a new playlist and smart playlist together" do
      before do
        connect_spotify
        sign_in user
      end

      let(:payload) do
        {
          smart_playlist: {
            target_playlist_attributes: { name: "Metal Mix", description: "Heavy" },
            source_playlist_ids: [source.id],
          },
        }
      end

      it "creates the playlist on Spotify and returns 201" do
        stub_request(:post, create_url)
          .to_return(status: 201, body: { "id" => "spotify_new_1" }.to_json,
                     headers: { "Content-Type" => "application/json" },)

        post "/api/v1/smart_playlists", params: payload

        expect(response).to have_http_status(:created)
        expect(response.parsed_body.dig("data", "target_playlist", "spotify_id")).to eq("spotify_new_1")
        expect(response.parsed_body.dig("data", "name")).to eq("Metal Mix")
      end

      it "returns 502 and creates nothing when Spotify fails" do
        stub_request(:post, create_url).to_return(status: 500, body: "")

        post "/api/v1/smart_playlists", params: payload

        expect(response).to have_http_status(:bad_gateway)
        expect(SmartPlaylist.count).to eq(0)
        expect(Playlist.where(name: "Metal Mix")).to be_empty
      end
    end

    context "when creating a new playlist without Spotify connected" do
      before { sign_in user }

      let(:payload) do
        {
          smart_playlist: {
            target_playlist_attributes: { name: "Metal Mix" },
            source_playlist_ids: [source.id],
          },
        }
      end

      it "returns 422 and creates nothing" do
        post "/api/v1/smart_playlists", params: payload

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["errors"].first["code"]).to eq("spotify_not_connected")
        expect(SmartPlaylist.count).to eq(0)
        expect(Playlist.where(name: "Metal Mix")).to be_empty
      end
    end
  end

  describe "PATCH /api/v1/smart_playlists/:id" do
    let(:smart_playlist) { create(:smart_playlist, user: user) }

    before { sign_in user }

    it "updates the rules" do
      rules = { "match" => "all", "rules" => [{ "field" => "genre", "operator" => "equals", "value" => "metal" }] }

      patch "/api/v1/smart_playlists/#{smart_playlist.id}", params: { smart_playlist: { rules: rules } }

      expect(response).to have_http_status(:ok)
      expect(smart_playlist.reload.rules).to eq(rules)
      expect(response.parsed_body.dig("data", "is_ready")).to be(true)
    end

    it "replaces the source playlists" do
      replacement = create(:playlist, :with_spotify, user: user)

      patch "/api/v1/smart_playlists/#{smart_playlist.id}",
            params: { smart_playlist: { source_playlist_ids: [replacement.id] } }

      expect(response).to have_http_status(:ok)
      expect(smart_playlist.reload.source_playlists).to contain_exactly(replacement)
    end

    it "returns 422 when enabling a smart playlist that has no rules" do
      patch "/api/v1/smart_playlists/#{smart_playlist.id}", params: { smart_playlist: { is_enabled: true } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(smart_playlist.reload.is_enabled).to be(false)
    end

    it "enables a smart playlist that has rules" do
      smart_playlist = create(:smart_playlist, :with_rules, user: user)

      patch "/api/v1/smart_playlists/#{smart_playlist.id}", params: { smart_playlist: { is_enabled: true } }

      expect(response).to have_http_status(:ok)
      expect(smart_playlist.reload.is_enabled).to be(true)
    end

    it "returns 422 when clearing every source and keeps the existing sources" do
      sources = smart_playlist.source_playlists.to_a

      patch "/api/v1/smart_playlists/#{smart_playlist.id}", params: { smart_playlist: { source_playlist_ids: [] } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(smart_playlist.reload.source_playlists).to match_array(sources)
    end

    it "rolls back a source change when another attribute is rejected" do
      replacement = create(:playlist, :with_spotify, user: user)
      sources = smart_playlist.source_playlists.to_a

      patch "/api/v1/smart_playlists/#{smart_playlist.id}",
            params: { smart_playlist: { source_playlist_ids: [replacement.id], is_enabled: true } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(smart_playlist.reload.source_playlists).to match_array(sources)
    end

    it "leaves the smart playlist alone when no attributes are given" do
      sources = smart_playlist.source_playlists.to_a

      patch "/api/v1/smart_playlists/#{smart_playlist.id}"

      expect(response).to have_http_status(:ok)
      expect(smart_playlist.reload.source_playlists).to match_array(sources)
    end

    it "returns 422 when every source id belongs to another user and keeps the existing sources" do
      sources = smart_playlist.source_playlists.to_a

      patch "/api/v1/smart_playlists/#{smart_playlist.id}",
            params: { smart_playlist: { source_playlist_ids: [create(:playlist).id] } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(smart_playlist.reload.source_playlists).to match_array(sources)
    end

    it "drops source ids belonging to another user and keeps the caller's own" do
      mine = create(:playlist, :with_spotify, user: user)

      patch "/api/v1/smart_playlists/#{smart_playlist.id}",
            params: { smart_playlist: { source_playlist_ids: [mine.id, create(:playlist).id] } }

      expect(response).to have_http_status(:ok)
      expect(smart_playlist.reload.source_playlists).to contain_exactly(mine)
    end

    it "saves a rule that excludes another of the caller's playlists" do
      excluded = create(:playlist, :with_spotify, user: user)
      rules = { "match" => "all",
                "rules" => [{ "field" => "playlist", "operator" => "not_in", "value" => [excluded.id] }], }

      patch "/api/v1/smart_playlists/#{smart_playlist.id}", params: { smart_playlist: { rules: rules } }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"]["rule_playlists"].pluck("id")).to contain_exactly(excluded.id)
    end

    it "returns 422 for a playlist id that arrived as text rather than a number" do
      excluded = create(:playlist, :with_spotify, user: user)
      rules = { "match" => "all",
                "rules" => [{ "field" => "playlist", "operator" => "not_in", "value" => [excluded.id.to_s] }], }

      patch "/api/v1/smart_playlists/#{smart_playlist.id}", params: { smart_playlist: { rules: rules } }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"].first["message"]).to include("must refer to a playlist")
    end

    it "returns 422 for a rule naming another user's playlist" do
      rules = { "match" => "all",
                "rules" => [{ "field" => "playlist", "operator" => "not_in", "value" => [create(:playlist).id] }], }
      original = smart_playlist.rules

      patch "/api/v1/smart_playlists/#{smart_playlist.id}", params: { smart_playlist: { rules: rules } }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(smart_playlist.reload.rules).to eq(original)
    end

    it "returns 422 for rules the query builder does not support" do
      rules = { "match" => "all", "rules" => [{ "field" => "bpm", "operator" => "equals", "value" => "120" }] }
      original = smart_playlist.rules

      patch "/api/v1/smart_playlists/#{smart_playlist.id}", params: { smart_playlist: { rules: rules } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(smart_playlist.reload.rules).to eq(original)
    end

    it "accepts a nested rule set with list and relative values" do
      rules = {
        "match" => "all",
        "rules" => [
          { "field" => "artist", "operator" => "in", "value" => %w[Gojira Meshuggah] },
          { "field" => "date_added", "operator" => "in_the_last",
            "value" => { "count" => 30, "unit" => "days" }, },
          { "match" => "any", "not" => true,
            "rules" => [{ "field" => "year", "operator" => "between", "value" => [2020, 2024] }], },
        ],
      }

      patch "/api/v1/smart_playlists/#{smart_playlist.id}",
            params: { smart_playlist: { rules: rules } }, as: :json

      expect(response).to have_http_status(:ok)
      expect(smart_playlist.reload.rules).to eq(rules)
    end

    it "returns 422 for an operator the field does not support" do
      rules = { "match" => "all",
                "rules" => [{ "field" => "genre", "operator" => "greater_than", "value" => "rock" }], }

      patch "/api/v1/smart_playlists/#{smart_playlist.id}",
            params: { smart_playlist: { rules: rules } }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"].pluck("message").join)
        .to include('does not support the operator "greater_than"')
    end

    it "refuses to store keys outside the schema rather than round-tripping them" do
      original = smart_playlist.rules
      rules = { "match" => "all", "rules" => [
        { "field" => "genre", "operator" => "equals", "value" => "rock", "junk" => "x" * 500 },
      ], }

      patch "/api/v1/smart_playlists/#{smart_playlist.id}",
            params: { smart_playlist: { rules: rules } }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"].pluck("message").join)
        .to include('has unexpected keys: "junk"')
      expect(smart_playlist.reload.rules).to eq(original)
    end

    it "returns 422 for an oversized rule set" do
      condition = { "field" => "genre", "operator" => "equals", "value" => "rock" }
      rules = { "match" => "all",
                "rules" => Array.new(Rules::FieldCatalog::MAX_NODES + 1) { condition }, }

      patch "/api/v1/smart_playlists/#{smart_playlist.id}", params: { smart_playlist: { rules: rules } }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 naming the rule that failed" do
      rules = { "match" => "all",
                "rules" => [
                  { "field" => "genre", "operator" => "equals", "value" => "rock" },
                  { "field" => "year", "operator" => "greater_than", "value" => "banana" },
                ], }

      patch "/api/v1/smart_playlists/#{smart_playlist.id}",
            params: { smart_playlist: { rules: rules } }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"].pluck("message"))
        .to contain_exactly("Rules must be a whole number at rule 2")
    end

    it "returns every failing rule, not just the first" do
      rules = { "match" => "all",
                "rules" => [
                  { "field" => "year", "operator" => "greater_than", "value" => "banana" },
                  { "field" => "popularity", "operator" => "equals", "value" => 500 },
                ], }

      patch "/api/v1/smart_playlists/#{smart_playlist.id}",
            params: { smart_playlist: { rules: rules } }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"].pluck("message")).to contain_exactly(
        "Rules must be a whole number at rule 1",
        "Rules must be between 0 and 100 at rule 2",
      )
    end

    it "returns 400 when smart_playlist is not an object" do
      patch "/api/v1/smart_playlists/#{smart_playlist.id}", params: { smart_playlist: "oops" }

      expect(response).to have_http_status(:bad_request)
    end

    it "returns 400 when source_playlist_ids is not a list of ids" do
      patch "/api/v1/smart_playlists/#{smart_playlist.id}",
            params: { smart_playlist: { source_playlist_ids: { "0" => "1" } } }

      expect(response).to have_http_status(:bad_request)
    end

    it "returns 404 for another user's smart playlist" do
      patch "/api/v1/smart_playlists/#{create(:smart_playlist).id}",
            params: { smart_playlist: { is_enabled: false } }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/smart_playlists/:id" do
    before { sign_in user }

    it "removes the smart playlist but keeps the target playlist" do
      smart_playlist = create(:smart_playlist, user: user)
      target = smart_playlist.target_playlist

      delete "/api/v1/smart_playlists/#{smart_playlist.id}"

      expect(response).to have_http_status(:no_content)
      expect(SmartPlaylist.exists?(smart_playlist.id)).to be(false)
      expect(target.reload).to be_persisted
    end

    it "frees the target playlist's sync toggle" do
      smart_playlist = create(:smart_playlist, user: user)
      target = smart_playlist.target_playlist

      delete "/api/v1/smart_playlists/#{smart_playlist.id}"

      expect(target.reload.update(sync_enabled: false)).to be(true)
    end

    it "returns 404 for another user's smart playlist" do
      delete "/api/v1/smart_playlists/#{create(:smart_playlist).id}"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/smart_playlists/:id/evaluate" do
    let(:metal) { create(:track, :with_genres, genre_names: ["metal"], title: "Flying Whales") }
    let(:rock) { create(:track, :with_genres, genre_names: ["rock"], title: "Paranoid") }
    let(:source) { create(:playlist, :holding, user: user, tracks: [metal, rock]) }
    let(:metal_rules) do
      { "match" => "all",
        "rules" => [{ "field" => "genre", "operator" => "equals", "value" => "metal" }], }
    end
    let(:rock_rules) do
      { "match" => "all",
        "rules" => [{ "field" => "genre", "operator" => "equals", "value" => "rock" }], }
    end
    let(:smart_playlist) do
      create(:smart_playlist, target_playlist: create(:playlist, :with_spotify, user: user),
                              source_playlists: [source], rules: metal_rules,)
    end

    def evaluate(id, rules: nil, query: "")
      if rules
        post "/api/v1/smart_playlists/#{id}/evaluate#{query}",
             params: { smart_playlist: { rules: rules } }, as: :json
      else
        post "/api/v1/smart_playlists/#{id}/evaluate#{query}"
      end
    end

    it "returns 401 when not authenticated" do
      evaluate(smart_playlist.id)

      expect(response).to have_http_status(:unauthorized)
    end

    context "when authenticated" do
      before { sign_in user }

      it "returns the tracks matching the saved rules" do
        evaluate(smart_playlist.id)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["data"].pluck("title")).to eq(["Flying Whales"])
      end

      it "reports the match count as meta.total and the pool as source_track_count" do
        evaluate(smart_playlist.id)

        expect(response.parsed_body["meta"]).to include("total" => 1, "source_track_count" => 2)
      end

      it "records the run and says so via meta.evaluated_at" do
        evaluate(smart_playlist.id)

        expect(response.parsed_body["meta"]["evaluated_at"]).to be_present
        expect(smart_playlist.reload.match_count).to eq(1)
        expect(smart_playlist.last_evaluated_at).to be_within(5.seconds).of(Time.current)
      end

      it "evaluates a submitted draft instead of the saved rules" do
        evaluate(smart_playlist.id, rules: rock_rules)

        expect(response.parsed_body["data"].pluck("title")).to eq(["Paranoid"])
      end

      it "does not persist a submitted draft" do
        expect { evaluate(smart_playlist.id, rules: rock_rules) }
          .not_to(change { smart_playlist.reload.rules })
      end

      it "does not record a draft, which describes rules the record does not hold" do
        evaluate(smart_playlist.id, rules: rock_rules)

        expect(response.parsed_body["meta"]["evaluated_at"]).to be_nil
        expect(smart_playlist.reload.last_evaluated_at).to be_nil
        expect(smart_playlist.match_count).to eq(0)
      end

      it "records a draft that happens to be the saved rules" do
        evaluate(smart_playlist.id, rules: metal_rules)

        expect(response.parsed_body["meta"]["evaluated_at"]).to be_present
        expect(smart_playlist.reload.match_count).to eq(1)
      end

      it "returns the whole pool for an empty rule set, and records nothing" do
        draft = create(:smart_playlist, source_playlists: [source],
                                        target_playlist: create(:playlist, :with_spotify, user: user),)

        evaluate(draft.id)

        expect(response.parsed_body["meta"]).to include("total" => 2, "evaluated_at" => nil)
        expect(draft.reload.last_evaluated_at).to be_nil
      end

      it "does not touch the target playlist's track set" do
        target = smart_playlist.target_playlist

        expect { evaluate(smart_playlist.id) }.not_to(change { target.reload.current_version_id })
      end

      it "writes no PlaylistVersion" do
        id = smart_playlist.id

        expect { evaluate(id) }.not_to change(PlaylistVersion, :count)
      end

      it "rejects an invalid draft with the validator's located message" do
        draft = { "match" => "all",
                  "rules" => [{ "match" => "all",
                                "rules" => [{ "field" => "nope", "operator" => "equals", "value" => "x" }], }], }

        evaluate(smart_playlist.id, rules: draft)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["errors"].first).to include("code" => "validation_error")
        expect(response.parsed_body["errors"].first["message"]).to include("at rule 1.1")
      end

      it "refuses to preview a draft naming another user's playlist" do
        draft = { "match" => "all",
                  "rules" => [{ "field" => "playlist", "operator" => "not_in",
                                "value" => [create(:playlist).id], }], }

        evaluate(smart_playlist.id, rules: draft)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["errors"].first["message"]).to include("not yours")
      end

      it "previews a draft that excludes one of the caller's own playlists" do
        excluded = create(:playlist, :holding, user: user, tracks: [metal])
        draft = { "match" => "all",
                  "rules" => [{ "field" => "playlist", "operator" => "not_in", "value" => [excluded.id] }], }

        evaluate(smart_playlist.id, rules: draft)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["data"].pluck("title")).to eq(["Paranoid"])
      end

      it "paginates, newest-added first" do
        older = create(:track, title: "Older")
        newer = create(:track, title: "Newer")
        paged = create(:smart_playlist,
                       target_playlist: create(:playlist, :with_spotify, user: user),
                       source_playlists: [create(:playlist, :holding, user: user,
                                                                      memberships: [[older, 10.days.ago],
                                                                                    [newer, 1.day.ago],],)],
                       rules: SmartPlaylist::EMPTY_RULES.deep_dup,)

        evaluate(paged.id, query: "?per_page=1")

        expect(response.parsed_body["data"].pluck("title")).to eq(["Newer"])
        expect(response.parsed_body["meta"]).to include("total" => 2, "total_pages" => 2, "per_page" => 1)
      end

      it "records on the first page only, so paging does not rewrite the count" do
        both_genres = { "match" => "all",
                        "rules" => [{ "field" => "genre", "operator" => "in", "value" => %w[metal rock] }], }
        paged = create(:smart_playlist,
                       target_playlist: create(:playlist, :with_spotify, user: user),
                       source_playlists: [create(:playlist, :holding, user: user, tracks: [metal, rock])],
                       rules: both_genres,)

        evaluate(paged.id, query: "?per_page=1&page=2")

        expect(response.parsed_body["meta"]).to include("page" => 2, "evaluated_at" => nil)
        expect(paged.reload.last_evaluated_at).to be_nil
        expect(paged.match_count).to eq(0)
      end

      it "returns 404 for another user's smart playlist" do
        other = create(:smart_playlist, :with_rules)

        evaluate(other.id)

        expect(response).to have_http_status(:not_found)
      end

      it "reports a rule set that is not an object as a validation error" do
        evaluate(smart_playlist.id, rules: "not a rule set")

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["errors"].first["message"])
          .to eq("Rules #{I18n.t("rules.errors.group_shape")}")
      end

      it "reports a rule set that is a list as a validation error" do
        evaluate(smart_playlist.id, rules: [{ "field" => "genre" }])

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "reports an empty rule set object as a validation error, not as the saved rules" do
        evaluate(smart_playlist.id, rules: {})

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["data"]).to be_nil
      end

      it "renders a validation error when evaluation hits the statement timeout" do
        allow(SmartPlaylists::QueryTimeout).to receive(:guard).and_raise(ActiveRecord::QueryCanceled)

        evaluate(smart_playlist.id)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["errors"].first).to include(
          "code" => "validation_error",
          "message" => I18n.t("api.smart_playlists.evaluation_timeout"),
        )
      end

      it "does not dress a timeout in another action up as an evaluation timeout" do
        allow(SmartPlaylists::Filter).to receive(:new).and_raise(ActiveRecord::QueryCanceled)

        expect { get "/api/v1/smart_playlists" }.to raise_error(ActiveRecord::QueryCanceled)
      end
    end
  end

  describe "POST /api/v1/smart_playlists/:id/push" do
    let(:target) { create(:playlist, :with_spotify, user: user) }
    let(:smart_playlist) { create(:smart_playlist, :with_rules, target_playlist: target) }

    it "returns 401 when not authenticated" do
      post "/api/v1/smart_playlists/#{smart_playlist.id}/push"
      expect(response).to have_http_status(:unauthorized)
    end

    context "when authenticated" do
      before { sign_in user }

      it "returns 404 for another user's smart playlist" do
        other = create(:smart_playlist, :with_rules)

        post "/api/v1/smart_playlists/#{other.id}/push"

        expect(response).to have_http_status(:not_found)
      end

      context "with Spotify connected" do
        before { connect_spotify }

        it "queues the push and returns the session" do
          post "/api/v1/smart_playlists/#{smart_playlist.id}/push"

          expect(response).to have_http_status(:accepted)
          expect(response.parsed_body["data"]["session"]).to include(
            "status" => "running",
            "smart_playlist_id" => smart_playlist.id,
            "smart_playlist_name" => target.name,
          )
        end

        it "enqueues the planner" do
          expect { post "/api/v1/smart_playlists/#{smart_playlist.id}/push" }
            .to have_enqueued_job(PushPlanJob)
        end

        it "refuses a smart playlist with no rules" do
          draft = create(:smart_playlist, target_playlist: create(:playlist, :with_spotify, user: user))

          post "/api/v1/smart_playlists/#{draft.id}/push"

          expect(response).to have_http_status(:unprocessable_content)
          expect(response.parsed_body["errors"].first["message"])
            .to eq(I18n.t("api.smart_playlists.push_not_ready"))
        end

        it "refuses a second concurrent push for the same smart playlist" do
          create(:push_session, :running, smart_playlist: smart_playlist)

          post "/api/v1/smart_playlists/#{smart_playlist.id}/push"

          expect(response).to have_http_status(:conflict)
          expect(response.parsed_body["errors"].first["message"])
            .to eq(I18n.t("api.smart_playlists.push_in_progress"))
        end

        it "allows a concurrent push for a different smart playlist" do
          create(:push_session, :running, smart_playlist: create(:smart_playlist, :with_rules, user: user))

          post "/api/v1/smart_playlists/#{smart_playlist.id}/push"

          expect(response).to have_http_status(:accepted)
        end
      end

      it "refuses when Spotify is not connected" do
        post "/api/v1/smart_playlists/#{smart_playlist.id}/push"

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["errors"].first["message"])
          .to eq(I18n.t("api.errors.spotify_not_connected"))
      end
    end
  end

  describe "GET /api/v1/smart_playlists/push_status" do
    it "returns 401 when not authenticated" do
      get "/api/v1/smart_playlists/push_status"
      expect(response).to have_http_status(:unauthorized)
    end

    context "when authenticated" do
      before { sign_in user }

      it "reports nothing in flight when the user has never pushed" do
        get "/api/v1/smart_playlists/push_status"

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["data"]).to include(
          "active_pushes" => [], "recent_pushes" => [], "rate_limited" => false,
        )
      end

      it "separates in-flight pushes from finished ones" do
        running = create(:push_session, :running, smart_playlist: create(:smart_playlist, :with_rules, user: user))
        done = create(:push_session, :completed, smart_playlist: create(:smart_playlist, :with_rules, user: user))

        get "/api/v1/smart_playlists/push_status"

        data = response.parsed_body["data"]
        expect(data["active_pushes"].pluck("id")).to eq([running.id])
        expect(data["recent_pushes"].pluck("id")).to eq([done.id])
      end

      it "reports several pushes running at once" do
        2.times { create(:push_session, :running, smart_playlist: create(:smart_playlist, :with_rules, user: user)) }

        get "/api/v1/smart_playlists/push_status"

        expect(response.parsed_body["data"]["active_pushes"].size).to eq(2)
      end

      it "still reports a finished push when many are in flight" do
        done = create(:push_session, :completed, smart_playlist: create(:smart_playlist, :with_rules, user: user))
        10.times { create(:push_session, :running, smart_playlist: create(:smart_playlist, :with_rules, user: user)) }

        get "/api/v1/smart_playlists/push_status"

        data = response.parsed_body["data"]
        expect(data["active_pushes"].size).to eq(10)
        expect(data["recent_pushes"].pluck("id")).to eq([done.id])
      end

      it "carries the progress and diff counts the banner renders" do
        session = create(:push_session, :with_batches, remove_batches: 1, add_batches: 1,
                                                       completed_remove_batches: 1, tracks_added: 7, tracks_removed: 2,
                                                       smart_playlist: create(:smart_playlist, :with_rules,
                                                                              user: user,),)

        get "/api/v1/smart_playlists/push_status"

        expect(response.parsed_body["data"]["active_pushes"].first).to include(
          "id" => session.id,
          "strategy" => "diff",
          "tracks_added" => 7,
          "tracks_removed" => 2,
          "sampled" => false,
          "progress" => { "total" => 2, "completed" => 1, "percent" => 50 },
        )
      end

      it "does not leak another user's pushes" do
        create(:push_session, :running)

        get "/api/v1/smart_playlists/push_status"

        expect(response.parsed_body["data"]["active_pushes"]).to be_empty
      end
    end
  end
end
