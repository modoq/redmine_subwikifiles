
# Script to create a test project with nested wiki pages
# Run with: rails runner create_test_project.rb

project_identifier = 'nested-wiki-test'
project_name = 'Nested Wiki Test Project'

# 1. Create Project
project = Project.find_by(identifier: project_identifier)
if project
  puts "Project '#{project_name}' already exists. Using existing project."
else
  project = Project.new(
    name: project_name,
    identifier: project_identifier,
    description: 'Project for testing nested wiki pages and file sync.',
    is_public: true
  )
  if project.save
    puts "Created project '#{project_name}'."
  else
    puts "Failed to create project: #{project.errors.full_messages.join(', ')}"
    exit 1
  end
end

# 2. Enable Modules
modules = ['wiki', 'redmine_subwikifiles']
modules.each do |mod|
  unless project.module_enabled?(mod)
    project.enabled_module_names += [mod]
    puts "Enabled module '#{mod}'."
  end
end
project.save

# 3. Create Wiki
unless project.wiki
  project.create_wiki(start_page: 'Wiki')
  puts "Created Wiki for project."
end

# 4. Create Pages
user = User.current || User.first || User.anonymous

# Helper to create/update page
def create_page(wiki, title, content, parent = nil, user)
  page = wiki.pages.find_or_initialize_by(title: title)
  page.parent = parent
  
  if page.new_record?
    page.content = WikiContent.new(page: page, text: content, author: user, comments: "Initial creation")
    if page.save
      puts "Created page '#{title}' (ID: #{page.id})."
    else
      puts "Failed to create page '#{title}': #{page.errors.full_messages.join(', ')}"
    end
  else
    puts "Page '#{title}' already exists."
  end
  page
end

# Root Page
home_content = <<~MD
# Welcome to the Nested Wiki Test

This is the main page of the wiki.

## Features to test
- File sync
- Rename handling
- Nested pages
MD
home_page = create_page(project.wiki, 'Wiki', home_content, nil, user)

# Level 1
l1_content = <<~MD
# Level 1 Page

This is a sub-page of the main wiki page.

It contains some **bold text** and *italic text*.

- List item 1
- List item 2
MD
l1_page = create_page(project.wiki, 'Level_1', l1_content, home_page, user)

# Level 2 (Nested under Level 1)
l2_content = <<~MD
# Level 2 Page (Deeply Nested)

This page is nested under Level 1.

```ruby
def hello_world
  puts "Hello from nested page!"
end
```

Table example:
| Header A | Header B |
| :--- | :--- |
| Cell 1 | Cell 2 |
MD
l2_page = create_page(project.wiki, 'Level_2', l2_content, l1_page, user)

# Level 1 Sibling
sibling_content = <<~MD
# Sibling Page

This is another page at Level 1, sibling to 'Level 1'.
MD
sibling_page = create_page(project.wiki, 'Sibling_Page', sibling_content, home_page, user)

puts "Test data creation complete!"
puts "Project URL: http://localhost:3000/projects/#{project_identifier}/wiki"
