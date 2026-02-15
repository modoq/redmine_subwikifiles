module RedmineSubwikifiles
  # Responsible for adding minimal YAML frontmatter to Markdown files that are missing it.
  class FrontmatterFixer
    attr_reader :project
    
    def initialize(project)
      @project = project
    end
    
    # Add minimal frontmatter to a single file
    # 
    # @param file_path [String] Absolute path to the file to fix
    # @return [Hash] { success: Boolean, error: String }
    def fix_file(file_path)
      # Check file exists
      return { success: false, error: "File not found" } unless File.exist?(file_path)
      
      # Read current content
      content = File.read(file_path)
      
      # Don't fix if frontmatter already exists
      if content.start_with?('---')
        return { success: false, error: "Frontmatter already exists" }
      end
      
      # Check file is not locked
      if FileLockChecker.locked?(file_path)
        return { success: false, error: "File is locked" }
      end
      
      # Add minimal frontmatter (empty YAML section)
      fixed_content = "---\n---\n\n#{content}"
      
      begin
        # Write to file
        File.write(file_path, fixed_content)
        
        # Commit to git if enabled
        if @project && GitBackend.enabled?(@project)
          git = GitBackend.new(@project)
          git.commit_file(
            File.basename(file_path),
            "Auto-fix: Added frontmatter to #{File.basename(file_path)}",
            User.current
          )
        end
        
        { success: true }
      rescue => e
        { success: false, error: e.message }
      end
    end
    
    # Fix multiple files at once
    # 
    # @param file_paths [Array<String>] Array of absolute file paths
    # @return [Hash] { fixed: Array<String>, failed: Array<Hash> }
    def fix_files(file_paths)
      results = { fixed: [], failed: [] }
      
      file_paths.each do |path|
        result = fix_file(path)
        filename = File.basename(path, '.md')
        
        if result[:success]
          results[:fixed] << filename
          Rails.logger.info "RedmineSubwikifiles: Auto-fixed frontmatter for #{filename}"
        else
          results[:failed] << { file: filename, error: result[:error] }
          Rails.logger.warn "RedmineSubwikifiles: Failed to fix #{filename}: #{result[:error]}"
        end
      end
      
      results
    end
  end
end
