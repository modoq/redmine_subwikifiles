#!/usr/bin/env ruby
# Quick test to check if plugin classes load

puts "Testing RedmineSubwikifiles class loading..."

begin
  require '/usr/src/redmine/plugins/redmine_subwikifiles/lib/redmine_subwikifiles/frontmatter_parser'
  puts "✓ FrontmatterParser loaded"
  
  # Test parsing
  test_md = "---\nparent: Test\n---\n\n# Content"
  result = RedmineSubwikifiles::FrontmatterParser.parse(test_md)
  puts "✓ FrontmatterParser.parse works: #{result[:metadata]}"
  
  require '/usr/src/redmine/plugins/redmine_subwikifiles/lib/redmine_subwikifiles/file_storage'
  puts "✓ FileStorage loaded"
  
rescue => e
  puts "✗ ERROR: #{e.message}"
  puts e.backtrace.first(10)
end
