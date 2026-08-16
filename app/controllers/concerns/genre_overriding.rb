# frozen_string_literal: true

module GenreOverriding
  extend ActiveSupport::Concern

  included do
    include GenreLoading
  end

  def create
    genre = resolve_genre
    return render_unknown_genre unless genre

    writer.set(genre, override_params[:action])
    render_genres
  rescue ArgumentError
    render_error(I18n.t("api.genres.unknown_action"), status: :unprocessable_content, code: "validation_error")
  end

  def destroy
    writer.clear(Genre.find(params.expect(:id)))
    render_genres
  end

  private

  def writer
    @writer ||= Genres::OverrideWriter.new(current_user, subject)
  end

  def resolve_genre
    return Genre.find_by(id: override_params[:genre_id]) if override_params[:genre_id].present?

    name = Genre.normalize_name(override_params[:name])
    name.presence && Genre.find_or_create_by!(name: name)
  end

  def override_params
    @override_params ||= nested_params(:genre).permit(:genre_id, :name, :action)
  end

  def render_unknown_genre
    render_error(I18n.t("api.genres.unknown_genre"), status: :unprocessable_content, code: "validation_error")
  end
end
