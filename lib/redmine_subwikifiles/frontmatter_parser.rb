module RedmineSubwikifiles
  # Handles parsing and building of YAML frontmatter blocks within Markdown content.
  class FrontmatterParser
    # Parse markdown text with YAML frontmatter
    # Returns: { metadata: Hash, content: String }
    def self.parse(markdown_text)
      return { metadata: {}, content: markdown_text || '' } if markdown_text.nil? || markdown_text.empty?
      return { metadata: {}, content: markdown_text } unless markdown_text.start_with?('---')
      
      # Split by frontmatter delimiters
      parts = markdown_text.split(/^---\s*$/m, 3)
      
      if parts.size >= 3 && parts[0].strip.empty?
        # Valid frontmatter structure: empty, yaml, content
        begin
          metadata = YAML.safe_load(parts[1]) || {}
          content = parts[2].lstrip # Remove leading whitespace after frontmatter
          
          { metadata: metadata, content: content }
        rescue Psych::SyntaxError => e
          Rails.logger.error "RedmineSubwikifiles: Frontmatter YAML parse error: #{e.message}"
          # Return raw content without frontmatter on parse error
          { metadata: {}, content: markdown_text }
        end
      else
        # Not valid frontmatter structure
        { metadata: {}, content: markdown_text }
      end
    end
    
    # Build markdown with frontmatter
    # Returns: String with frontmatter + content
    def self.build(metadata, content)
      return content if metadata.nil? || metadata.empty?
      
      # Clean metadata: remove nil/empty values
      clean_metadata = metadata.compact.reject { |_k, v| v.to_s.strip.empty? }
      
      return content if clean_metadata.empty?
      
      yaml_str = clean_metadata.to_yaml.sub(/^---\n/, '') # Remove YAML document separator
      "---\n#{yaml_str}---\n\n#{content}"
    end
    
    # Update specific metadata keys in existing markdown
    # Returns: String with updated frontmatter + original content
    def self.update_metadata(markdown_text, new_metadata)
      parsed = parse(markdown_text)
      merged_metadata = parsed[:metadata].merge(new_metadata)
      build(merged_metadata, parsed[:content])
    end
    
    # Extract metadata value by key
    def self.get_metadata(markdown_text, key)
      parsed = parse(markdown_text)
      parsed[:metadata][key]
    end
    
    # Remove frontmatter, return only content
    def self.strip_frontmatter(markdown_text)
      parsed = parse(markdown_text)
      parsed[:content]
    end
  end
end
