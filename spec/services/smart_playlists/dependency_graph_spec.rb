# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmartPlaylists::DependencyGraph do
  let(:user) { create(:user) }

  def playlist
    create(:playlist, :with_spotify, user: user)
  end

  def chain(source, target)
    create(:smart_playlist, target_playlist: target, source_playlists: [source])
  end

  describe "#reaches?" do
    it "is true for a playlist and itself" do
      only = playlist

      expect(described_class.new(user).reaches?(only.id, only.id)).to be(true)
    end

    it "follows a single hop" do
      source = playlist
      target = playlist
      chain(source, target)

      expect(described_class.new(user).reaches?(source.id, target.id)).to be(true)
      expect(described_class.new(user).reaches?(target.id, source.id)).to be(false)
    end

    it "follows a chain of hops" do
      first = playlist
      second = playlist
      third = playlist
      chain(first, second)
      chain(second, third)

      expect(described_class.new(user).reaches?(first.id, third.id)).to be(true)
    end

    it "ignores another user's smart playlists" do
      source = playlist
      target = playlist
      chain(source, target)

      expect(described_class.new(create(:user)).reaches?(source.id, target.id)).to be(false)
    end

    it "drops the excluded smart playlist's own edges" do
      source = playlist
      target = playlist
      smart_playlist = chain(source, target)

      expect(described_class.new(user, excluding: smart_playlist.id).reaches?(source.id, target.id)).to be(false)
    end
  end
end
