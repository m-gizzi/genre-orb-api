# frozen_string_literal: true

module GenreOverridable
  extend ActiveSupport::Concern

  ACTIONS = { hidden: 0, added: 1 }.freeze

  included do
    belongs_to :genre

    enum :action, ACTIONS, validate: true
  end
end
