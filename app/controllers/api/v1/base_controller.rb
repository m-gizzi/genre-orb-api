# frozen_string_literal: true

module Api
  module V1
    class BaseController < ApplicationController
      include Pagy::Backend

      before_action :authenticate_user!

      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
      rescue_from ActionController::ParameterMissing, with: :render_bad_request
      rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid

      private

      def render_data(payload, meta: nil, status: :ok)
        body = { data: payload }
        body[:meta] = meta unless meta.nil?
        render json: body, status: status
      end

      def render_error(message, status:, code: nil)
        code ||= status.to_s
        errors = Array(message).map { |text| { code: code, message: text } }
        render json: { errors: errors }, status: status
      end

      def paginate(scope)
        pagy(scope)
      end

      def pagy_meta(pagy)
        {
          page: pagy.page,
          per_page: pagy.limit,
          total: pagy.count,
          total_pages: pagy.pages,
        }
      end

      def render_not_found
        render_error(I18n.t("api.errors.not_found"), status: :not_found)
      end

      def render_bad_request
        render_error(I18n.t("api.errors.bad_request"), status: :bad_request)
      end

      def render_record_invalid(exception)
        render_error(
          exception.record.errors.full_messages,
          status: :unprocessable_content,
          code: "validation_error",
        )
      end
    end
  end
end
