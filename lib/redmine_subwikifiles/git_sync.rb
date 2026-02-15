module RedmineSubwikifiles
  # Orchestrates the synchronization process from the filesystem to the Redmine database.
  # Detects changes in the Git repository and updates corresponding WikiPages.
  class GitSync
    def initialize(project)
      @project = project
      @backend = GitBackend.new(project)
      @storage = FileStorage.new(project)
    end
    
    # Sync filesystem changes to Redmine
    def sync_from_filesystem
      Rails.logger.info "RedmineSubwikifiles: DEBUG: sync_from_filesystem START"
      
      # Stage all changes first so git can detect renames
      @backend.run_git('add', '-A')
      
      changes = @backend.detect_changes
      Rails.logger.info "RedmineSubwikifiles: DEBUG: Detected changes: #{changes.inspect}"
      
      # Process in order: delete, rename, modify, add
      # This prevents conflicts if a page was deleted and recreated
      
      changes[:deleted].each do |file|
        Rails.logger.info "RedmineSubwikifiles: DEBUG: File #{file} deleted from filesystem. Keeping wiki page."
        # delete_page_in_redmine(file) # DISABLED: Active check handles this
      end
      
      changes[:renamed].each do |old_file, new_file|
        rename_page_in_redmine(old_file, new_file)
      end
      
      changes[:modified].each do |file|
        Rails.logger.info "RedmineSubwikifiles: DEBUG: Processing modified for #{file}"
        update_page_content(file)
      end
      
      changes[:added].each do |file|
        create_page_in_redmine(file)
      end
      
      # Commit the sync (add all changes)
      @backend.run_git('add', '-A') if changes.values.any?(&:any?)
      @backend.run_git('commit', '-m', 'Synced from filesystem', '--allow-empty') rescue nil
      
      Rails.logger.info "RedmineSubwikifiles: Synced #{changes.values.flatten.size} changes from filesystem"
    rescue => e
      Rails.logger.error "RedmineSubwikifiles: Sync from filesystem failed: #{e.message}"
    end
    
    private
    
    def delete_page_in_redmine(file)
      return unless file.end_with?('.md')
      
      title = file_to_title(file)
      page = find_page_by_title(title)
      
      if page
        page.destroy
        Rails.logger.info "RedmineSubwikifiles: Deleted page '#{title}' (file deleted)"
      end
    end
    
    def rename_page_in_redmine(old_file, new_file)
      return unless old_file.end_with?('.md') && new_file.end_with?('.md')
      
      old_title = file_to_title(old_file)
      new_title = file_to_title(new_file)
      
      page = find_page_by_title(old_title)
      
      if page
        # Prevent triggering our own rename hook
        Thread.current[:redmine_subwikifiles_syncing] = true
        page.update(title: new_title)
        Thread.current[:redmine_subwikifiles_syncing] = false
        
        Rails.logger.info "RedmineSubwikifiles: Renamed page '#{old_title}' to '#{new_title}' (file renamed)"
      end
    end
    
    def update_page_content(file)
      return unless file.end_with?('.md')
      
      title = file_to_title(file)
      page = find_page_by_title(title)
      
      if page && page.content
        file_path = @storage.file_path(title)
        new_content = File.read(file_path, encoding: 'UTF-8')
        
        # Prevent triggering our own save hook
        Thread.current[:redmine_subwikifiles_syncing] = true
        page.content.text = new_content
        page.content.save
        Thread.current[:redmine_subwikifiles_syncing] = false
        
        Rails.logger.info "RedmineSubwikifiles: Updated page '#{title}' (file modified)"
      end
    end
    
    def create_page_in_redmine(file)
      return unless file.end_with?('.md')
      
      title = file_to_title(file)
      
      # Check if page already exists
      return if find_page_by_title(title)
      
      # Create wiki if it doesn't exist
      unless @project.wiki
        @project.create_wiki
      end
      
      file_path = @storage.file_path(title)
      content_text = File.read(file_path, encoding: 'UTF-8')
      
      # Check for frontmatter
      begin
        parsed = FrontmatterParser.parse(content_text)
        unless parsed[:metadata].present?
          Rails.logger.info "RedmineSubwikifiles: Skipping creation of page '#{title}': No frontmatter found"
          return
        end
        # Use content without frontmatter if needed, but WikiContent usually stores full text?
        # Standard Redmine stores ONLY content in `text` column.
        # But Subwikifiles seems to rely on file being the source of truth, so we should store the full content?
        # Wait, WikiImporter stores `content` which comes from parser.
        # But here we are just creating a page from a file that *already exists*.
        # Let's see what WikiContent expects.
        # If we store full text (including frontmatter) in DB, Redmine might show it.
        # Subwikifiles usually separates them.
        # However, for now, let's stick to the existing behavior of reading the whole file,
        # just adding the check.
      rescue => e
        Rails.logger.error "RedmineSubwikifiles: Failed to parse frontmatter for '#{title}': #{e.message}"
        return
      end
      
      # Create the page
      page = WikiPage.new(wiki: @project.wiki, title: title)
      content = WikiContent.new(
        page: page,
        text: content_text,
        author: User.current || User.anonymous
      )
      page.content = content
      
      Thread.current[:redmine_subwikifiles_syncing] = true
      if page.save
        Rails.logger.info "RedmineSubwikifiles: Successfully created/synced page '#{title}'"
      else
        Rails.logger.error "RedmineSubwikifiles: Failed to save page '#{title}': #{page.errors.full_messages.join(', ')}"
        if page.content && page.content.errors.any?
          Rails.logger.error "RedmineSubwikifiles: Content errors: #{page.content.errors.full_messages.join(', ')}"
        end
      end
      Thread.current[:redmine_subwikifiles_syncing] = false
      
      Rails.logger.info "RedmineSubwikifiles: Created page '#{title}' (new file)"
    end
    
    def file_to_title(file)
      # Remove .md extension and convert path separators to hierarchy
      # e.g., "Parent/Child.md" -> "Parent/Child"
      file.sub(/\.md$/, '').gsub('_', ' ')
    end
    
    def find_page_by_title(title)
      return nil unless @project.wiki
      
      # Handle hierarchical titles
      parts = title.split('/')
      
      if parts.size == 1
        # Top-level page
        @project.wiki.pages.find_by(title: title)
      else
        # Nested page - need to match by full path
        # This is tricky because Redmine doesn't store full paths
        # We need to find by the last part and check ancestors
        page_title = parts.last
        @project.wiki.pages.where(title: page_title).find do |page|
          full_title = ([page.ancestors.map(&:title)] + [page.title]).flatten.join('/')
          full_title == title
        end
      end
    end
  end
end
