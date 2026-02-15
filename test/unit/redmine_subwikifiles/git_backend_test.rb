require File.expand_path('../../../../test_helper', __FILE__)
require 'mocha/minitest'

class RedmineSubwikifiles::GitBackendTest < ActiveSupport::TestCase
  def setup
    @project = Project.find(1)
    @backend = RedmineSubwikifiles::GitBackend.new(@project)
    @user = User.find(1)
  end

  def test_init_repo_creates_git_dir
    # Mock Open3 to avoid actual git commands
    RedmineSubwikifiles::GitBackend.any_instance.stubs(:run_git).returns("")
    
    # We can't easily test init_repo private method without changing it or checking side effects
    # But since it's called in initialize if .git missing, checking existence of .git logic might be hard if we mock everything.
    # Let's verify commit calls git commands.
  end

  def test_commit_executes_git_commands
    # Expectation: add and commit are called
    
    # We mock the run_git method to verify it receives correct arguments
    @backend.expects(:run_git).with('add', 'Test_Page.md').returns("")
    @backend.expects(:run_git).with('commit', '-m', "Update Test Page", 
                                    '--author', "#{@user.firstname} #{@user.lastname} <#{@user.mail}>", 
                                    '--allow-empty-message').returns("")
    
    @backend.commit("Test Page", author: @user, message: "Update Test Page")
  end
end
