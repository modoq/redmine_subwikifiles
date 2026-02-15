module RedmineSubwikifiles
  # Manages the physical storage of wiki files on the filesystem.
  # Handles path calculation (including nested subprojects), reading, and writing.
  class FileStorage
    attr_reader :project_path
    
    def initialize(project)
      @project = project
      @project_identifier = project.identifier
      # Fetch base path from settings, default to /var/lib/redmine/wiki_files if not set
      @base_dir = Setting.plugin_redmine_subwikifiles['base_path'] || '/var/lib/redmine/wiki_files'
      
      # Build path recursively for nested subprojects (e.g., top/_projects/sub1/_projects/sub2/)
      @project_path = build_project_path(project)
    end
    
    private
    
    # Build the complete path for a project, supporting nested subprojects
    # Example: top/_projects/sub1/_projects/sub2/
    def build_project_path(project)
      if project.parent
        # Recursively build parent path, then add _projects/identifier
        parent_path = build_project_path(project.parent)
        File.join(parent_path, '_projects', project.identifier)
      else
        # Top-level project: use direct path
        File.join(@base_dir, project.identifier)
      end
    end
    
    public

    def file_exists?(title)
      !resolve_existing_path(title).nil?
    end

    def read(title)
      path = resolve_existing_path(title)
      return nil unless path
      
      content = File.read(path, encoding: 'UTF-8')
      mtime = File.mtime(path)
      [content, mtime]
    rescue => e
      Rails.logger.error "RedmineSubwikifiles: Failed to read file for #{title}: #{e.message}"
      nil
    end

    def write(title, content)
      # Write to existing path if available, else default to sanitized
      path = resolve_existing_path(title) || file_path(title)
      
      # Ensure project directory exists
      FileUtils.mkdir_p(@project_path) unless File.directory?(@project_path)

      File.write(path, content, encoding: 'UTF-8')
    rescue => e
      Rails.logger.error "RedmineSubwikifiles: Failed to write file for #{title}: #{e.message}"
    end

    # Returns the default path for a new file (sanitized)
    def file_path(title)
      sanitized = sanitize_filename(title)
      File.join(@project_path, "#{sanitized}.md")
    end
    
    private
    
    # Try to find an existing file matching the title variants
    def resolve_existing_path(title)
      # Variants to check
      variants = [
        sanitize_filename(title),         # Standard (underscores)
        title,                            # As-is (e.g. spaces)
        title.gsub(' ', '-'),             # Hyphens
        title.gsub(/[^\w\s\-]/, ''),      # Minimal sanitization
        sanitize_filename(title).downcase, # Lowercase underscore
        title.downcase.gsub(' ', '-')      # Lowercase hyphen
      ].uniq
      
      variants.each do |v|
        path = File.join(@project_path, "#{v}.md")
        Rails.logger.info "RedmineSubwikifiles: Checking existence of #{path}"
        return path if File.exist?(path)
      end
      
      Rails.logger.info "RedmineSubwikifiles: Resolution failed for title '#{title}'. Checked: #{variants.map { |v| File.join(@project_path, "#{v}.md") }.join(', ')}"
      nil
    end
    
    private
    
    def sanitize_filename(title)
      # Replace spaces with underscores, remove special chars
      # Keep only alphanumeric, underscores, and hyphens
      title.gsub(' ', '_').gsub(/[^\w\-]/, '')
    end
  end
end
