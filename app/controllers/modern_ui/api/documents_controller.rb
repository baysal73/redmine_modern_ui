# frozen_string_literal: true

module ModernUi
  module Api
    # Document management on top of the DMSF plugin (redmine_dmsf): browse folders and
    # files per project, upload (a file with an existing name becomes a new version), create/rename folders and
    # move things to the trash (restorable). Downloads and previews stay with DMSF's own routes, so access
    # logging, notifications and storage work exactly as before. Every permission is DMSF's own; without the
    # plugin all endpoints answer 404.
    class DocumentsController < BaseController
      before_action :require_dmsf
      before_action :load_project, except: %i[projects show_file destroy_file restore_file update_folder destroy_folder restore_folder]

      LIST_MAX = 500

      # GET /app/api/documents/projects
      def projects
        list = Project.visible.active.allowed_to(User.current, :view_dmsf_folders).sorted.to_a
        render json: { projects: list.map { |p| { id: p.id, identifier: p.identifier, name: p.name } } }
      end

      # GET /app/api/documents?project=ID&folder=ID
      def index
        folder = params[:folder].present? ? find_folder(params[:folder], @project) : nil
        folders = DmsfFolder.visible.where(project_id: @project.id, dmsf_folder_id: folder&.id).includes(:user).sort_by { |f| f.title.to_s.downcase }
        files_scope = DmsfFile.visible.where(project_id: @project.id, dmsf_folder_id: folder&.id)
        total = files_scope.count
        files = User.current.allowed_to?(:view_dmsf_files, @project) ? files_scope.includes(:locks, dmsf_file_revisions: :user).limit(LIST_MAX).to_a : []
        files = files.sort_by { |f| f.name.to_s.downcase }
        folder_locked = folder ? folder.locked? : false
        render json: {
          project: { id: @project.id, identifier: @project.identifier, name: @project.name },
          folder: folder && { id: folder.id, title: folder.title, parent_id: folder.dmsf_folder_id },
          path: folder ? folder.dmsf_path.map { |f| { id: f.id, title: f.title } } : [],
          folders: folders.select { |f| DmsfFolder.permissions?(f) }.map { |f| folder_json(f) },
          files: files.map { |f| file_json(f) },
          truncated: total > LIST_MAX,
          can: abilities(folder, folder_locked)
        }
      end

      # GET /app/api/documents/files/:id  (with all versions)
      def show_file
        file = find_file(params[:id])
        revisions = file.dmsf_file_revisions.reject { |r| r.deleted != DmsfFileRevision::STATUS_ACTIVE }
        render json: { file: file_json(file, detail: true).merge(
          path: file.dmsf_folder ? file.dmsf_folder.dmsf_path.map { |f| { id: f.id, title: f.title } } : [],
          project: { id: file.project.id, identifier: file.project.identifier, name: file.project.name },
          revisions: revisions.map { |r| revision_json(file, r) },
          can_delete: file_deletable?(file)
        ) }
      end

      # POST /app/api/documents/folders  { project, folder_id?, title, description? }
      def create_folder
        parent = params[:folder_id].present? ? find_folder(params[:folder_id], @project) : nil
        return render_json_error(403, l(:modern_ui_error_forbidden)) unless User.current.allowed_to?(:folder_manipulation, @project)
        return render_json_error(423, l(:error_folder_is_locked)) if parent&.locked?

        folder = DmsfFolder.new(project: @project, user: User.current, dmsf_folder_id: parent&.id,
                                title: params[:title].to_s.scrub.strip, description: params[:description].to_s.scrub.strip)
        if folder.save
          render json: { folder: folder_json(folder) }, status: :created
        else
          render_json_error 422, folder.errors.full_messages.to_sentence
        end
      end

      # PATCH /app/api/documents/folders/:id  { title, description? }
      def update_folder
        folder = find_folder(params[:id])
        return render_json_error(403, l(:modern_ui_error_forbidden)) unless User.current.allowed_to?(:folder_manipulation, folder.project)
        return render_json_error(423, l(:error_folder_is_locked)) if folder.locked?

        folder.title = params[:title].to_s.scrub.strip if params.key?(:title)
        folder.description = params[:description].to_s.scrub.strip if params.key?(:description)
        if folder.save
          render json: { folder: folder_json(folder) }
        else
          render_json_error 422, folder.errors.full_messages.to_sentence
        end
      end

      # DELETE /app/api/documents/folders/:id (moves it to DMSF's trash)
      def destroy_folder
        folder = find_folder(params[:id])
        return render_json_error(403, l(:modern_ui_error_forbidden)) unless User.current.allowed_to?(:folder_manipulation, folder.project)

        if folder.delete(commit: false)
          render json: { ok: true }
        else
          render_json_error 422, folder.errors.full_messages.to_sentence.presence || l(:modern_ui_error_forbidden)
        end
      end

      def restore_folder
        folder = DmsfFolder.deleted.find(params[:id])
        return render_json_error(403, l(:modern_ui_error_forbidden)) unless User.current.allowed_to?(:folder_manipulation, folder.project) && DmsfFolder.permissions?(folder)

        folder.restore ? render(json: { ok: true }) : render_json_error(422, folder.errors.full_messages.to_sentence)
      end

      # POST /app/api/documents/files  { project, folder_id?, uploads: [{ token }] }
      # Same two-step flow as everywhere else: the browser first uploads the bytes to /app/api/uploads.
      def create_files
        folder = params[:folder_id].present? ? find_folder(params[:folder_id], @project) : nil
        unless User.current.allowed_to?(:file_manipulation, @project) && DmsfFolder.permissions?(folder)
          return render_json_error(403, l(:modern_ui_error_forbidden))
        end
        return render_json_error(423, l(:error_folder_is_locked)) if folder&.locked?

        committed = build_commits(folder)
        return render_json_error(422, l(:modern_ui_error_upload_missing)) if committed.empty?

        files, failed = DmsfUploadHelper.commit_files_internal(committed, @project, folder)
        render json: { done: files.size, files: files.map { |f| { id: f.id, name: f.name } },
                       failed: failed.map { |f| { name: f.try(:name).to_s, error: failure_message(f) } } },
               status: failed.empty? ? :created : :ok
      end

      # DELETE /app/api/documents/files/:id (moves it to DMSF's trash)
      def destroy_file
        file = find_file(params[:id])
        return render_json_error(403, l(:modern_ui_error_forbidden)) unless file_deletable?(file)

        if file.delete(commit: false)
          render json: { ok: true }
        else
          render_json_error 422, file.errors.full_messages.to_sentence.presence || l(:error_file_is_locked)
        end
      end

      def restore_file
        file = DmsfFile.deleted.find(params[:id])
        allowed = User.current.allowed_to?(:file_delete, file.project) && DmsfFolder.permissions?(file.dmsf_folder, file: true)
        return render_json_error(403, l(:modern_ui_error_forbidden)) unless allowed

        file.restore ? render(json: { ok: true }) : render_json_error(422, file.errors.full_messages.to_sentence)
      end

      private

      def require_dmsf
        render_json_error(404, l(:modern_ui_error_not_found)) unless defined?(::DmsfFile) && defined?(::DmsfFolder)
      end

      def load_project
        @project = find_visible_project(params[:project])
        raise ActiveRecord::RecordNotFound unless User.current.allowed_to?(:view_dmsf_folders, @project)
      end

      def find_folder(id, project = nil)
        scope = DmsfFolder.visible
        scope = scope.where(project_id: project.id) if project
        folder = scope.find(id)
        raise ActiveRecord::RecordNotFound unless DmsfFolder.permissions?(folder)

        folder
      end

      def find_file(id)
        file = DmsfFile.visible.includes(:locks, dmsf_file_revisions: :user).find(id)
        allowed = User.current.allowed_to?(:view_dmsf_files, file.project) && DmsfFolder.permissions?(file.dmsf_folder, file: true)
        raise ActiveRecord::RecordNotFound unless allowed

        file
      end

      def file_deletable?(file)
        User.current.allowed_to?(:file_delete, file.project)
      end

      def abilities(folder, folder_locked)
        base = DmsfFolder.permissions?(folder) && !folder_locked
        { upload: base && User.current.allowed_to?(:file_manipulation, @project),
          folder: base && User.current.allowed_to?(:folder_manipulation, @project),
          delete_file: User.current.allowed_to?(:file_delete, @project),
          delete_folder: User.current.allowed_to?(:folder_manipulation, @project) }
      end

      def root
        Redmine::Utils.relative_url_root
      end

      def folder_json(folder)
        { id: folder.id, title: folder.title, description: folder.description.to_s, locked: folder.locked?,
          updated_at: folder.updated_at&.iso8601, author: folder.user&.name,
          files: DmsfFile.visible.where(dmsf_folder_id: folder.id).count,
          folders: DmsfFolder.visible.where(dmsf_folder_id: folder.id).count }
      end

      # DMSF only sends the raw file (instead of a preview page) when the revision is named
      def download_path(file, rev)
        "#{root}/dmsf/files/#{file.id}/view?download=#{rev.id}&disposition=attachment"
      end

      def latest_revision(file)
        file.dmsf_file_revisions.find { |r| r.deleted == DmsfFileRevision::STATUS_ACTIVE }
      end

      def file_json(file, detail: false)
        rev = latest_revision(file)
        locked = file.locks.any? { |lock| !lock.expired? }
        out = { id: file.id, name: rev&.name.to_s, title: rev&.title.to_s, size: rev&.size.to_i, version: rev&.version.to_s,
                updated_at: (rev&.updated_at || file.updated_at)&.iso8601, author: rev&.user&.name, locked: locked,
                download_url: rev ? download_path(file, rev) : nil, view_url: "#{root}/dmsf/files/#{file.id}/view",
                classic_url: "#{root}/dmsf/files/#{file.id}" }
        out[:description] = rev&.description.to_s if detail
        out[:comment] = rev&.comment.to_s if detail
        out
      end

      def revision_json(file, rev)
        { id: rev.id, name: rev.name, version: rev.version, size: rev.size.to_i, author: rev.user&.name,
          created_at: rev.created_at&.iso8601, comment: rev.comment.to_s, description: rev.description.to_s,
          download_url: download_path(file, rev) }
      end

      # Only the user's own, unattached uploads can be committed (like for issues)
      def own_upload(token)
        a = token.present? ? Attachment.find_by_token(token.to_s) : nil
        a if a.present? && a.container_id.nil? && a.author_id == User.current.id
      end

      def build_commits(folder)
        uploads = Array(params[:uploads]).first(20).filter_map do |u|
          u.respond_to?(:permit) ? own_upload(u[:token]) : nil
        end
        uploads.each_with_index.to_h do |a, i|
          existing = DmsfFile.visible.find_file_by_name(@project, folder, a.filename)
          [i.to_s, { name: a.filename, title: File.basename(a.filename, '.*'), token: a.token, size: a.filesize,
                     mime_type: a.content_type.presence || 'application/octet-stream' }.merge(versions_for(existing)).with_indifferent_access]
        end
      end

      # New file: 1 (or 0.0 when the installation prefers that); existing file: the next version of its last one
      def versions_for(file)
        rev = file&.last_revision
        unless rev
          return RedmineDmsf.empty_minor_version_by_default? ? { version_major: 1 } : { version_major: 0, version_minor: 0 }
        end

        major = rev.major_version
        minor = rev.minor_version
        patch = rev.patch_version
        if patch
          patch = DmsfUploadHelper.increase_version(patch)
        elsif minor
          minor = DmsfUploadHelper.increase_version(minor)
        else
          major = DmsfUploadHelper.increase_version(major)
        end
        { version_major: major, version_minor: minor, version_patch: patch }.compact
      end

      def failure_message(record)
        msg = record.errors.full_messages.to_sentence if record.respond_to?(:errors)
        return msg if msg.present?

        record.respond_to?(:locked_for_user?) && record.locked_for_user? ? l(:error_file_is_locked) : l(:modern_ui_error_document_failed)
      end
    end
  end
end
