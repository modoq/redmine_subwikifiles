class SubwikifilesSettingsController < ApplicationController
  layout 'admin'
  menu_item :plugins

  before_action :require_admin

  def index
    # This might be used for a custom settings page if needed
    # Currently settings are handled via the standard plugin settings
    redirect_to plugin_settings_path(:redmine_subwikifiles)
  end
end
