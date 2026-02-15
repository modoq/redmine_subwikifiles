module RedmineSubwikifiles
  # Handles various Redmine hooks, such as hiding project modules and detecting unassigned folders.
  class Hooks < Redmine::Hook::ViewListener
    # Hide the module checkbox in project settings if plugin is globally enabled
    def view_projects_form(context={})
      return '' unless context[:project]
      
      # Check if plugin is globally enabled
      if Setting.plugin_redmine_subwikifiles['enabled']
        # Inject CSS to hide the module checkbox for redmine_subwikifiles
        return <<-HTML.html_safe
          <style>
            /* Hide the entire label containing the redmine_subwikifiles module checkbox when globally enabled */
            label:has(input[name="project[enabled_module_names][]"][value="redmine_subwikifiles"]) {
              display: none;
            }
          </style>
        HTML
      end
      
      ''
    end
    
    # Check for unassigned folders when viewing wiki index
    def view_wiki_show_top(context={})
      project = context[:project]
      return '' unless project
      
      # Only check if user has permissions
      return '' unless User.current.allowed_to?(:manage_wiki, project)
      
      # Sync filesystem changes to Redmine first
      begin
        require File.expand_path('../git_sync', __FILE__)
        GitSync.new(project).sync_from_filesystem
      rescue => e
        Rails.logger.error "RedmineSubwikifiles: Sync failed: #{e.message}"
      end
      
      scanner = RedmineSubwikifiles::FolderScanner.new(project)
      unassigned = scanner.unassigned_folders
      
      if unassigned.any?
        count = unassigned.size
        folder_list = unassigned.first(3).join(', ')
        folder_list += ", ..." if unassigned.size > 3
        
        link = context[:controller].link_to(
          I18n.t('redmine_subwikifiles.assign_now'),
          context[:controller].project_subwikifiles_folder_prompt_path(project),
          class: 'icon icon-add'
        )
        
        message = I18n.t('redmine_subwikifiles.unassigned_folders_found', 
                        count: count, 
                        folders: folder_list)
        
        return <<-HTML.html_safe
          <div class="flash notice">
            #{message} #{link}
          </div>
        HTML
      end
      
      ''
    end
    
    # Hook triggered after a project is saved
    # Creates folder structure for subprojects directly in parent's directory
    def controller_projects_new_after_save(context={})
      project = context[:project]
      return unless project && project.parent
      
      # Only create folders if plugin is enabled for parent
      return unless project.parent.module_enabled?(:redmine_subwikifiles)
      
      # Use FileStorage to get the correct path
      require File.expand_path('../file_storage', __FILE__)
      storage = RedmineSubwikifiles::FileStorage.new(project)
      project_path = storage.project_path
      
      # Create subproject directory
      unless Dir.exist?(project_path)
        FileUtils.mkdir_p(project_path)
        Rails.logger.info "RedmineSubwikifiles: Created subproject folder #{project_path}"
      end
    rescue => e
      Rails.logger.error "RedmineSubwikifiles: Failed to create subproject folder: #{e.message}"
    end
  end
end
