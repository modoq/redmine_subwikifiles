module RedmineSubwikifiles
  # Scans for unassigned folders within a project's base directory.
  # Unassigned folders are those that do not yet have a corresponding Redmine subproject.
  class FolderScanner
    attr_reader :project
    
    def initialize(project)
      @project = project
      # Use FileStorage to retrieve the correct project path (supporting nesting)
      require File.expand_path('../file_storage', __FILE__)
      @project_path = FileStorage.new(project).project_path
    end
    
    # Scans for child directories in the project root that are not active subprojects.
    # @return [Array<Hash>] An array of folder detail hashes.
    def scan_all_folders
      return [] unless Dir.exist?(@project_path)
      
      unassigned = []
      
      Dir.foreach(@project_path) do |entry|
        next if entry.start_with?('.')
        next if entry.end_with?('.md')
        
        full_path = File.join(@project_path, entry)
        next unless Dir.exist?(full_path)
        
        # Check if this folder corresponds to a subproject
        if subproject_exists?(entry)
          # It's an assigned subproject folder.
          # We skip it.
        else
          # It's an unassigned folder
          unassigned << {
            path: full_path,
            name: entry,
            parent_project: @project,
            misplaced: false, # Direct child is valid
            relative_path: entry,
            depth: 0
          }
        end
      end
      
      unassigned
    end
    
    # Legacy method for backward compatibility
    def unassigned_folders
      scan_all_folders.map { |f| f[:name] }
    end
    
    private
    
    def subproject_exists?(folder_name)
      # Sanitize folder name to potential identifier for loose matching?
      # Or strict matching?
      # Since we enforce renaming on creation, strict matching against identifier is best.
      
      @project.children.active.any? { |child| child.identifier == folder_name }
    end
  end
end
