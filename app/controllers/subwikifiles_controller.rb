# Handles advanced file operations like folder assignment, orphan file importing, and attachment synchronization.
class SubwikifilesController < ApplicationController
  before_action :find_project
  before_action :authorize, except: [:fix_frontmatter, :attach_file, :restore_file]
  
  # Displays a list of unassigned folders to the user for potential subproject creation.
  def folder_prompt
    @scanner = RedmineSubwikifiles::FolderScanner.new(@project)
    @all_unassigned = @scanner.scan_all_folders
    
    if @all_unassigned.empty?
      flash[:notice] = l('redmine_subwikifiles.no_unassigned_folders')
      redirect_to project_wiki_path(@project)
    else
      # Pass the first unassigned folder to the dialog for immediate action
      @folder = @all_unassigned.first
    end
  end
  
  # Processes the user's choice for an unassigned folder (either create a subproject or move to quarantine).
  def assign_folder
    folder_path = params[:folder_path]
    folder_name = params[:folder_name]
    action_type = params[:action_type] # 'subproject' or 'quarantine'
    parent_project_id = params[:parent_project_id]
    misplaced = params[:misplaced] == 'true'
    
    parent_project = parent_project_id ? Project.find(parent_project_id) : @project
    
    case action_type
    when 'subproject'
      create_subproject(folder_path, folder_name, parent_project, misplaced)
    when 'quarantine'
      quarantine_folder(folder_path, folder_name)
    else
      flash[:error] = l('redmine_subwikifiles.invalid_action')
      redirect_to project_subwikifiles_folder_prompt_path(@project)
      return
    end
  end
  
  # Imports orphan files as wiki pages. 
  # This is triggered by the "Fix" buttons in the warning flash message.
  def fix_frontmatter
    # Permission check
    unless User.current.allowed_to?(:edit_wiki_pages, @project)
      render json: { error: "Permission denied" }, status: :forbidden
      return
    end
    
    # Get file names and optional parent page from params
    file_names = params[:files] || []
    parent_page_id = params[:page_id] # Can be page title or ID
    
    if file_names.empty?
      render json: { error: "No files specified" }, status: :bad_request
      return
    end
    
    # Find parent page if specified
    parent_page_title = nil
    if parent_page_id.present? && @project.wiki
      Rails.logger.info "RedmineSubwikifiles: fix_frontmatter - page_id param: #{parent_page_id}"
      parent_page = @project.wiki.pages.find_by(id: parent_page_id) || 
                    @project.wiki.pages.find_by(title: parent_page_id)
      
      if parent_page
        parent_page_title = parent_page.title
        Rails.logger.info "RedmineSubwikifiles: fix_frontmatter - Parent page found: #{parent_page_title} (ID: #{parent_page.id})"
      else
        Rails.logger.warn "RedmineSubwikifiles: fix_frontmatter - Parent page NOT found for: #{parent_page_id}"
      end
    else
      Rails.logger.info "RedmineSubwikifiles: fix_frontmatter - No page_id param provided"
    end
    
    # Build file paths and read content
    storage = RedmineSubwikifiles::FileStorage.new(@project)
    
    # Prepare orphan data for import
    orphan_data = file_names.map do |name|
      file_path = File.join(storage.send(:project_path), "#{name}.md")
      
      # Read file content
      unless File.exist?(file_path)
        Rails.logger.warn "RedmineSubwikifiles: File not found: #{file_path}"
        next nil
      end
      
      raw_content = File.read(file_path)
      
      # Parse frontmatter
      metadata = {}
      content = raw_content
      
      if raw_content =~ /\A---\s*\n(.*?)\n---\s*\n(.*)\z/m
        frontmatter_text = $1
        content = $2.strip
        
        # Redmine requires non-empty content
        content = "(empty content)" if content.blank?
        
        # Simple YAML parsing for frontmatter
        frontmatter_text.each_line do |line|
          if line =~ /^(\w+):\s*(.+)$/
            metadata[$1] = $2.strip
          end
        end
      end
      
      # Set parent page if specified and not already set in frontmatter
      if parent_page_title.present? && !metadata['parent']
        metadata['parent'] = parent_page_title
        Rails.logger.info "RedmineSubwikifiles: fix_frontmatter - Assigned parent '#{parent_page_title}' to '#{name}'"
      end
      
      
      # Ensure content is not empty (Redmine requires it)
      content = "(empty content)" if content.blank?
      
      {
        filename: name,
        path: file_path,
        content: content,
        metadata: metadata,
        valid: true
      }
    end.compact
    
    if orphan_data.empty?
      render json: { error: "No valid files to import" }, status: :bad_request
      return
    end
    
    # Import all files as wiki pages
    Rails.logger.info "RedmineSubwikifiles: Importing #{orphan_data.length} orphan files via fix_frontmatter"
    importer = RedmineSubwikifiles::WikiImporter.new(@project)
    import_result = importer.import_files(orphan_data)
    
    # Return results
    render json: {
      fixed: import_result[:imported],
      failed: import_result[:skipped].map { |s| { file: s[:file], error: s[:errors].join(', ') } }
    }
  end
  
  # Import a file as an attachment
  def attach_file
    unless User.current.allowed_to?(:edit_wiki_pages, @project)
      render json: { error: "Permission denied" }, status: :forbidden
      return
    end
    
    file_name = params[:file]
    if file_name.blank?
      render json: { error: "No file specified" }, status: :bad_request
      return
    end
    
    storage = RedmineSubwikifiles::FileStorage.new(@project)
    file_path = File.join(storage.send(:project_path), file_name)
    
    unless File.exist?(file_path)
      render json: { error: "File not found on disk: #{file_name}" }, status: :not_found
      return
    end
    
    # Identify container (current wiki page if possible, otherwise project)
    container = nil
    if params[:page_id].present? && @project.wiki
       container = @project.wiki.pages.find_by(id: params[:page_id]) || @project.wiki.pages.find_by(title: params[:page_id])
    end
    container ||= @project.wiki || @project
    
    # Create attachment
    attachment = Attachment.new
    attachment.file = File.open(file_path)
    attachment.author = User.current
    attachment.container = container
    attachment.filename = file_name
    
    if attachment.save
      Rails.logger.info "RedmineSubwikifiles: Attached file '#{file_name}' to #{container.class.name} #{container.id}"
      
      # Move file to _attachments folder to "hide" it from orphans list
      begin
        attachments_dir = File.join(storage.send(:project_path), '_attachments')
        FileUtils.mkdir_p(attachments_dir)
        
        target_path = File.join(attachments_dir, file_name)
        
        # Handle duplicate names in target
        if File.exist?(target_path)
          timestamp = Time.now.strftime('%Y%m%d%H%M%S')
          target_path = File.join(attachments_dir, "#{File.basename(file_name, '.*')}_#{timestamp}#{File.extname(file_name)}")
        end
        
        FileUtils.mv(file_path, target_path)
        Rails.logger.info "RedmineSubwikifiles: Moved '#{file_name}' to '#{target_path}'"
      rescue => e
        Rails.logger.error "RedmineSubwikifiles: Failed to move attached file: #{e.message}"
        # Trigger Git commit for deletion/move?
        # GitSync handles changes on next sync. 
        # But if we move it, "detect_changes" will see "Deleted" at root and "Added" (if ignored? no).
        # We want _attachments to be tracked?
        # If specific folders are ignored by GitBackend? 
        # But if we just move it on disk, next sync will pick it up or ignore it depending on Git logic.
        # But for now, just filesystem move.
      end
      
      render json: { success: true, file: file_name, container: container.class.name }
    else
      render json: { error: attachment.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end

  end

  # Restore a missing file from wiki content
  def restore_file
    unless User.current.allowed_to?(:edit_wiki_pages, @project)
      render_403
      return
    end

    title = params[:title]
    page = @project.wiki.pages.find_by(title: title)
    
    if page && page.content
      page.content.write_to_md_file_with_frontmatter
      flash[:notice] = I18n.t('redmine_subwikifiles.notices.file_restored', file: "#{title}.md")
    else
      flash[:error] = I18n.t('redmine_subwikifiles.errors.page_not_found', page: title)
    end
    
    redirect_back(fallback_location: project_wiki_path(@project, title))
  end
  
  private
  
  def find_project
    @project = Project.find(params[:project_id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end
  
  def create_subproject(folder_path, folder_name, parent_project, misplaced)
    # Sanitize folder name to valid identifier
    identifier = folder_name.downcase.gsub(/[^a-z0-9\-]/, '-')
    
    subproject = Project.new(
      name: folder_name,
      identifier: identifier,
      parent: parent_project
    )
    
    if subproject.save
      # Enable wiki and subwikifiles modules
      subproject.enabled_module_names = ['wiki', 'redmine_subwikifiles']
      
      # Validating identifier and moving folder to match
      # Flattened structure: parent/identifier/
      
      # Get parent project path
      parent_storage = RedmineSubwikifiles::FileStorage.new(parent_project)
      parent_path = parent_storage.send(:project_path)
      
      # Target path using identifier
      target_path = File.join(parent_path, identifier)
      
      # Move/Rename folder if path or name is different
      if folder_path != target_path
        # Ensure target doesn't exist
        if File.exist?(target_path)
           Rails.logger.warn "RedmineSubwikifiles: Target folder #{target_path} already exists!"
           # Fallback: keep original folder name if possible or error?
           # logic continues...
        else
           FileUtils.mv(folder_path, target_path)
           Rails.logger.info "RedmineSubwikifiles: Moved/Renamed folder: #{folder_path} -> #{target_path}"
        end
      end
      
      # Initialize Git repo
      begin
        RedmineSubwikifiles::GitBackend.new(subproject)
        Rails.logger.info "RedmineSubwikifiles: Initialized Git repo for #{subproject.identifier}"
      rescue => e
        Rails.logger.error "RedmineSubwikifiles: Failed to init Git: #{e.message}"
      end
      
      flash[:notice] = l('redmine_subwikifiles.subproject_created', name: folder_name)
      redirect_to project_path(subproject)
    else
      flash[:error] = subproject.errors.full_messages.join(', ')
      redirect_to project_subwikifiles_folder_prompt_path(@project)
    end
  end
  
  def quarantine_folder(folder_path, folder_name)
    base_path = Setting.plugin_redmine_subwikifiles['base_path'] || '/var/lib/redmine/wiki_files'
    quarantine_base = File.join(base_path, 'Quarantine')
    
    # Create Quarantine directory if needed
    FileUtils.mkdir_p(quarantine_base)
    
    # Create timestamped quarantine folder
    timestamp = Time.now.strftime('%Y-%m-%d_%H%M%S')
    quarantine_folder = File.join(quarantine_base, "#{timestamp}_#{folder_name}")
    
    # Move folder to quarantine
    FileUtils.mv(folder_path, quarantine_folder)
    
    # Create README with metadata
    readme_path = File.join(quarantine_folder, 'QUARANTINE_INFO.txt')
    File.write(readme_path, <<~README)
      QUARANTINED FOLDER
      ==================
      
      Original Path: #{folder_path}
      Folder Name: #{folder_name}
      Quarantined: #{Time.now}
      User: #{User.current.login}
      Project: #{@project.name} (#{@project.identifier})
      
      This folder was moved to quarantine because it was not recognized
      as a subproject or wiki page directory.
    README
    
    Rails.logger.info "RedmineSubwikifiles: Quarantined #{folder_path} -> #{quarantine_folder}"
    
    flash[:notice] = l('redmine_subwikifiles.folder_quarantined', name: folder_name)
    redirect_to project_subwikifiles_folder_prompt_path(@project)
  end
  
end
