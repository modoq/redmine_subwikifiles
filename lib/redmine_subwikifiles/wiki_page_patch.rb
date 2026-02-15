module RedmineSubwikifiles
  # Patch for WikiPage model.
  # Handles filesystem renames and deletions when a wiki page is updated or destroyed in Redmine.
  module WikiPagePatch
    extend ActiveSupport::Concern

    included do
      Rails.logger.info "RedmineSubwikifiles: WikiPagePatch included in #{self.name}"
      before_save :handle_title_change
      after_save :update_frontmatter_on_parent_change
      before_destroy :delete_file
    end

    def handle_title_change
      return unless plugin_enabled?
      return unless title_changed? && persisted?
      
      # Get old and new titles with full hierarchy
      old_full_title = get_full_title_from(title_was)
      new_full_title = get_full_title_from(title)
      
      storage = RedmineSubwikifiles::FileStorage.new(project)
      old_path = storage.file_path(old_full_title)
      new_path = storage.file_path(new_full_title)
      
      # Rename file if it exists
      if File.exist?(old_path)
        # Ensure target directory exists
        FileUtils.mkdir_p(File.dirname(new_path))
        
        # Move the file
        FileUtils.mv(old_path, new_path)
        Rails.logger.info "RedmineSubwikifiles: Renamed #{old_path} to #{new_path}"
        
        # Handle Git rename
        if defined?(RedmineSubwikifiles::GitBackend)
          begin
            RedmineSubwikifiles::GitBackend.new(project).rename(
              title_was,
              title,
              author: User.current,
              message: "Renamed: #{title_was} → #{title}"
            )
          rescue => e
            Rails.logger.warn "RedmineSubwikifiles: Git rename failed: #{e.message}"
          end
        end
      end
    rescue => e
      Rails.logger.error "RedmineSubwikifiles: Error renaming file: #{e.message}"
    end
    
    def update_frontmatter_on_parent_change
      return unless plugin_enabled?
      # If parent_id changed, trigger content save to update frontmatter
      if saved_change_to_parent_id? && content
        content.save
      end
    rescue => e
      Rails.logger.error "RedmineSubwikifiles: Error updating frontmatter: #{e.message}"
    end
    
    def delete_file
      return unless plugin_enabled?
      
      full_title = get_full_title_from(title)
      storage = RedmineSubwikifiles::FileStorage.new(project)
      file_path = storage.file_path(full_title)
      
      # Delete file if it exists
      if File.exist?(file_path)
        File.delete(file_path)
        Rails.logger.info "RedmineSubwikifiles: Deleted #{file_path}"
        
        # Handle Git deletion
        if defined?(RedmineSubwikifiles::GitBackend)
          begin
            RedmineSubwikifiles::GitBackend.new(project).delete(
              title,
              author: User.current,
              message: "Deleted: #{title}"
            )
          rescue => e
            Rails.logger.warn "RedmineSubwikifiles: Git delete failed: #{e.message}"
          end
        end
      end
    rescue => e
      Rails.logger.error "RedmineSubwikifiles: Error deleting file: #{e.message}"
    end
    
    private
    
    def plugin_enabled?
      return false unless project
      
      # Check if globally enabled OR enabled for this project (or ancestors)
      return true if Setting.plugin_redmine_subwikifiles['enabled']
      
      project.self_and_ancestors.any? do |p|
        p.module_enabled?(:redmine_subwikifiles)
      end
    end
    
    def get_full_title_from(title_value)
      # With flat structure, we just use the title directly
      title_value
    end
  end
end
