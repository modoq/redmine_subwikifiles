
file_path = "/Users/smischke/Desktop/Development/redmine/plugins_aktiv/redmine_subwikifiles/Space_Test.md"
File.open(file_path, 'r+') do |f|
  puts "Locking #{file_path}..."
  f.flock(File::LOCK_EX)
  puts "Locked. Sleeping for 30 seconds..."
  sleep 30
end
puts "Done."
