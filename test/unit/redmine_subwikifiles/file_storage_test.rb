require File.expand_path('../../../../test_helper', __FILE__)

class RedmineSubwikifiles::FileStorageTest < ActiveSupport::TestCase
  def setup
    @project = Project.find(1) # Assuming project with ID 1 exists in test fixtures
    @storage = RedmineSubwikifiles::FileStorage.new(@project)
    @base_path = Setting.plugin_redmine_subwikifiles['base_path']
    @project_path = File.join(@base_path, @project.identifier)
  end

  def teardown
    # Clean up created files
    FileUtils.rm_rf(@project_path) if File.exist?(@project_path)
  end

  def test_write_creates_file
    title = "Test Page"
    content = "# Hello World"
    
    @storage.write(title, content)
    
    expected_path = File.join(@project_path, "Test_Page.md")
    assert File.exist?(expected_path)
    assert_equal content, File.read(expected_path)
  end

  def test_read_returns_content_and_mtime
    title = "Existing Page"
    content = "Some content"
    path = File.join(@project_path, "Existing_Page.md")
    
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    
    read_content, mtime = @storage.read(title)
    
    assert_equal content, read_content
    assert_not_nil mtime
  end

  def test_read_returns_nil_if_file_missing
    assert_nil @storage.read("Non Existent")
  end

  def test_file_path_sanitization
    title = "Page / with / slashes"
    # "Page / with / slashes" -> "Page_/_with_/_slashes.md" (spaces to _, keep /)
    # The implementation: title.gsub(' ', '_').gsub(/[^\w\/\-]/, '')
    # "Page_/_with_/_slashes"
    
    path = @storage.file_path(title)
    expected_suffix = "Page_/_with_/_slashes.md"
    assert_match /#{Regexp.escape(expected_suffix)}$/, path
  end
end
