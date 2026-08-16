# frozen_string_literal: true

require "rails_helper"

RSpec.describe Genres::RuleUsage do
  let(:user) { create(:user) }

  def smart_playlist_naming(*conditions, enabled: true)
    create(
      :smart_playlist,
      target_playlist: create(:playlist, :with_spotify, user: user),
      source_playlists: [create(:playlist, user: user)],
      is_enabled: enabled,
      rules: { "match" => "all", "rules" => conditions },
    )
  end

  def genre_condition(operator, value)
    { "field" => "genre", "operator" => operator, "value" => value }
  end

  def filtered(value)
    described_class.new(user).apply(Genre.all, value).map(&:name)
  end

  before do
    create(:genre, name: "metal")
    create(:genre, name: "death metal")
    create(:genre, name: "seen live")
  end

  describe "with no smart playlists at all" do
    it "reports nothing used" do
      expect(filtered("used")).to be_empty
    end

    it "reports everything unused" do
      expect(filtered("unused")).to contain_exactly("metal", "death metal", "seen live")
    end
  end

  describe "an exact rule" do
    before { smart_playlist_naming(genre_condition("equals", "metal")) }

    it "counts the genre it names as used" do
      expect(filtered("used")).to contain_exactly("metal")
    end

    it "leaves everything else unused" do
      expect(filtered("unused")).to contain_exactly("death metal", "seen live")
    end
  end

  # `genre contains "metal"` really does reach `death metal`, so calling it unused would
  # send a user off to block a genre their rules depend on.
  describe "a contains rule" do
    before { smart_playlist_naming(genre_condition("contains", "metal")) }

    it "counts every genre the pattern reaches" do
      expect(filtered("used")).to contain_exactly("metal", "death metal")
    end

    it "leaves the genres it cannot reach unused" do
      expect(filtered("unused")).to contain_exactly("seen live")
    end
  end

  describe "operators that name no genre" do
    before { smart_playlist_naming(genre_condition("is_set", nil)) }

    it "does not make anything used" do
      expect(filtered("used")).to be_empty
    end
  end

  # A disabled smart playlist still names the genre and can be switched back on, so calling
  # its genres unused would be a trap.
  describe "a disabled smart playlist" do
    before { smart_playlist_naming(genre_condition("equals", "metal"), enabled: false) }

    it "still counts its genres as used" do
      expect(filtered("used")).to contain_exactly("metal")
    end
  end

  describe "scoping" do
    it "ignores another user's rules" do
      other = create(:user)
      create(
        :smart_playlist,
        target_playlist: create(:playlist, :with_spotify, user: other),
        source_playlists: [create(:playlist, user: other)],
        rules: { "match" => "all", "rules" => [genre_condition("equals", "metal")] },
      )

      expect(filtered("used")).to be_empty
    end

    it "collects across several smart playlists" do
      smart_playlist_naming(genre_condition("equals", "metal"))
      smart_playlist_naming(genre_condition("equals", "seen live"))

      expect(filtered("used")).to contain_exactly("metal", "seen live")
    end
  end

  describe "an unrecognised value" do
    before { smart_playlist_naming(genre_condition("equals", "metal")) }

    it "leaves the relation alone" do
      expect(filtered(nil)).to contain_exactly("metal", "death metal", "seen live")
      expect(filtered("nonsense")).to contain_exactly("metal", "death metal", "seen live")
    end
  end
end
