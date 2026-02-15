module RedmineSubwikifiles
  # Patch for WikiContent model. 
  # Handles writing wiki content to the filesystem and creating Git commits on every save.
  module WikiContentPatch
    extend ActiveSupport::Concern

    included do
      Rails.logger.info "RedmineSubwikifiles: WikiContentPatch included in #{self.name}"
      before_save :write_to_md_file_with_frontmatter
      after_find :load_from_md_file_with_frontmatter
    end

    def write_to_md_file_with_frontmatter
      return unless plugin_enabled?
      return if Thread.current[:redmine_subwikifiles_syncing]
      
      storage = RedmineSubwikifiles::FileStorage.new(page.project)
      
      # Build frontmatter metadata
      metadata = build_frontmatter_metadata
      
      # Combine metadata + content
      full_content = RedmineSubwikifiles::FrontmatterParser.build(metadata, text)
      
      # Write to file (just page title, no hierarchy in filename)
      storage.write(page.title, full_content)
      
      # Sync attachments to FS
      if defined?(AttachmentHandler)
        AttachmentHandler.new(page).sync_to_fs
      end
      
      # Git commit
      if defined?(RedmineSubwikifiles::GitBackend)
        RedmineSubwikifiles::GitBackend.new(page.project).commit(
          page.title,
          author: User.current,
          message: I18n.t('redmine_subwikifiles.git_commit_message', page_title: page.title)
        )
      end
    rescue => e
      Rails.logger.error "RedmineSubwikifiles: Error writing MD file: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
    
    def load_from_md_file_with_frontmatter
      return unless plugin_enabled?
      return if Thread.current[:redmine_subwikifiles_syncing]
      
      storage = RedmineSubwikifiles::FileStorage.new(page.project)
      file_data = storage.read(page.title)
      
      return unless file_data
      
      file_content, file_mtime = file_data
      
      # Parse frontmatter
      parsed = RedmineSubwikifiles::FrontmatterParser.parse(file_content)
      content_only = parsed[:content]
      metadata = parsed[:metadata]
      
      # Conflict strategy handling
      strategy = Setting.plugin_redmine_subwikifiles['conflict_strategy'] || 'file_wins'
      
      # If file is newer than DB record
      if file_mtime > updated_on
        if strategy == 'file_wins' || strategy == 'manual'
          # Only update if content changed to avoid unnecessary versions
          if self.text != content_only
            self.text = content_only
            
            # Get author from git
            git_author = nil
            begin
               # We need absolute path for GitBackend or relative? 
               # GitBackend expects project.
               # We don't have file_path here easily, need to resolve it.
               # Storage.read returns data, not path.
               # But we can reconstruct path or ask storage.
               # Let's ask storage for path.
               file_path = storage.file_path(page.title)
               
               if file_path && File.exist?(file_path)
                 backend = RedmineSubwikifiles::GitBackend.new(page.project)
                 git_author = backend.last_commit_author(file_path)
               end
            rescue => e
               Rails.logger.warn "RedmineSubwikifiles: Could not get git author: #{e.message}"
            end
            
            author_text = git_author ? " (Author: #{git_author})" : ""
            
            # Prevent loop
            Thread.current[:redmine_subwikifiles_syncing] = true
            begin
              # Save with a specific comment to indicate it came from FS
              self.comments = "Updated from filesystem#{author_text}"
              self.save!
              Rails.logger.info "RedmineSubwikifiles: Updated WikiPage #{page.title} from filesystem."
              
              # Set flag for controller to see
              Thread.current[:redmine_subwikifiles_just_updated] = true
            ensure
              Thread.current[:redmine_subwikifiles_syncing] = false
            end
            
            # Sync attachments from FS
            if defined?(AttachmentHandler) && page
              AttachmentHandler.new(page).sync_from_fs
            end
          end
          
          # Sync parent relationship from frontmatter (even if content didn't change)
          sync_parent_from_metadata(metadata)
          
        elsif strategy == 'manual'
          Rails.logger.info "RedmineSubwikifiles: File is newer but strategy is manual. DB: #{updated_on}, File: #{file_mtime}"
        end
      end
    rescue => e
      Rails.logger.error "RedmineSubwikifiles: Error reading MD file: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end

    private

    def plugin_enabled?
      return true if Setting.plugin_redmine_subwikifiles['enabled']
      
      project = page.project
      return false unless project
      
      project.self_and_ancestors.any? do |p|
        p.module_enabled?(:redmine_subwikifiles)
      end
    end

    def build_frontmatter_metadata
      metadata = {}
      
      # Parent page
      if page.parent_id
        parent_page = WikiPage.find_by(id: page.parent_id)
        metadata['parent'] = parent_page.title if parent_page
      end
      
      # Add Wiki Page ID for robust rename handling
      metadata['id'] = page.id
      
      # Note: WikiPage doesn't have a 'position' attribute in Redmine 6
      # Order is determined by alphabetical sorting or explicit ordering in the UI
      
      # Creation date
      metadata['created'] = page.created_on.iso8601 if page.created_on
      
      # Updated date
      metadata['updated'] = updated_on.iso8601 if updated_on
      
      metadata.compact
    end
    
    def sync_parent_from_metadata(metadata)
      return unless metadata.is_a?(Hash)
      return unless metadata['parent']
      
      parent_title = metadata['parent']
      parent_page = page.wiki.pages.find_by(title: parent_title)
      
      if parent_page && page.parent_id != parent_page.id
        # Update parent relationship in Redmine
        Thread.current[:redmine_subwikifiles_syncing] = true
        begin
          page.parent_id = parent_page.id
          page.save!
          Rails.logger.info "RedmineSubwikifiles: Updated parent for '#{page.title}' to '#{parent_title}'"
        ensure
          Thread.current[:redmine_subwikifiles_syncing] = false
        end
      elsif metadata['parent'] && !parent_page
        Rails.logger.warn "RedmineSubwikifiles: Parent '#{parent_title}' not found for page '#{page.title}'"
      end
    end
  end
end
