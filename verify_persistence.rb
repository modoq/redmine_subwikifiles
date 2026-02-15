p = WikiPage.find_by(title: 'PersistenceTest')
unless p
  wiki = Wiki.first
  p = WikiPage.new(wiki: wiki, title: 'PersistenceTest')
  p.save!
  c = WikiContent.new(page: p, text: 'Initial content')
  c.save!
end

puts "Initial Version: #{p.content.version}"
puts "Initial Text: #{p.content.text}"

# Simulate file update
file_path = "/var/lib/redmine/wiki_files/#{p.project.identifier}/PersistenceTest.md"
puts "Modifying file at #{file_path}"
sleep 2 # Ensure mtime difference
File.write(file_path, "Updated content from filesystem")
# Ensure mtime is updated
FileUtils.touch(file_path)

sleep 2

# Reload to trigger after_find
# We need to find the content again to trigger the callback on the content model
# WikiPage.find might not trigger content load immediately unless joined or accessed?
# Actually `after_find` is on `WikiContent`. So we need to load `WikiContent`.
c = WikiContent.find_by(page_id: p.id)

puts "New Version: #{c.version}"
puts "New Text: #{c.text}"

if c.text == "Updated from filesystem" && c.version > 1
  puts "SUCCESS: Content updated and version increased."
else
  puts "FAILURE: Content or version not updated."
end
