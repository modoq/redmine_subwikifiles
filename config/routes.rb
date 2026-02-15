get 'projects/:project_id/subwikifiles/folder_prompt', to: 'subwikifiles#folder_prompt', as: 'project_subwikifiles_folder_prompt'
post 'projects/:project_id/subwikifiles/assign_folder', to: 'subwikifiles#assign_folder', as: 'project_subwikifiles_assign_folder'
post 'projects/:project_id/subwikifiles/fix_frontmatter', to: 'subwikifiles#fix_frontmatter', as: 'project_subwikifiles_fix_frontmatter'
post 'projects/:project_id/subwikifiles/attach_file', to: 'subwikifiles#attach_file', as: 'project_subwikifiles_attach_file'

post 'projects/:project_id/subwikifiles/restore_file', to: 'subwikifiles#restore_file', as: 'project_subwikifiles_restore_file'
