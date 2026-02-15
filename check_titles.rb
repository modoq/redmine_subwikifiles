project = Project.first
if project && project.wiki
  page = project.wiki.pages.first
  if page
    puts "Page Title in DB: '#{page.title}'"
    puts "Page Pretty Title: '#{page.pretty_title}'"
    puts "Does find_by(title: 'My Page') work? #{project.wiki.pages.find_by(title: page.pretty_title).inspect}"
    puts "Does find_by(title: 'My_Page') work? #{project.wiki.pages.find_by(title: page.title).inspect}"
  else
    puts "No wiki pages found."
  end
else
  puts "No project/wiki found."
end
