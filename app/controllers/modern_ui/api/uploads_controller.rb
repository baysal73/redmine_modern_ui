# frozen_string_literal: true

module ModernUi
  module Api
    # POST /app/api/uploads  (multipart, field "file")
    # Stores the file as an unattached Redmine attachment and returns a token. The token is then sent with
    # issue create/update ("uploads"), exactly like Redmine's own two-step upload. Size and extension rules come
    # from Redmine's settings (Attachment validations).
    class UploadsController < BaseController
      def create
        file = params[:file]
        unless file.respond_to?(:original_filename) && file.respond_to?(:read)
          return render_json_error(422, l(:modern_ui_error_upload_missing))
        end

        attachment = Attachment.new(file: file)
        attachment.author = User.current
        if attachment.save
          render json: { upload: { token: attachment.token, filename: attachment.filename, filesize: attachment.filesize,
                                   content_type: attachment.content_type } }, status: :created
        else
          render_json_error(422, attachment.errors.full_messages.to_sentence)
        end
      end
    end
  end
end
