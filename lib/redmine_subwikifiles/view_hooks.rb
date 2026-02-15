module RedmineSubwikifiles
  # Responsible for injecting JavaScript and CSS into Redmine views (layouts/base).
  # Handles the interactive "Fix" buttons for orphan files and displays file paths in the editor.
  class ViewHooks < Redmine::Hook::ViewListener
    Rails.logger.info "RedmineSubwikifiles: ViewHooks file loaded"
    
    def initialize
      super
      Rails.logger.info "RedmineSubwikifiles: ViewHooks initialized"
    end
    
    # Inject JS to handle "fix file" buttons and show file path in edit mode
    def view_layouts_base_html_head(context = {})
      Rails.logger.info "RedmineSubwikifiles: view_layouts_base_html_head called"
      
      controller = context[:controller]
      return '' unless controller
      
      # 1. Existing JS for 'fix file' buttons (orphans)
      js = build_js(controller)
      response = javascript_tag(js)
      
      # 2. Inject file path info if in Wiki Edit mode
      if controller.is_a?(WikiController) && controller.action_name == 'edit'
        file_path = controller.instance_variable_get(:@associated_file_path)
        if file_path
           # Calculate relative path
           # 1. Remove base path
           base_dir = Setting.plugin_redmine_subwikifiles['base_path'] || '/var/lib/redmine/wiki_files'
           relative_path = file_path.sub(base_dir, '')
           
           # 2. Cleanup internal structure artifacts (like /_projects/) to show logical path
           # E.g. /myproject/_projects/subproject/file.md -> /myproject/subproject/file.md
           relative_path = relative_path.gsub('/_projects/', '/')
           
           # Ensure it starts with /
           relative_path = "/#{relative_path}" unless relative_path.start_with?('/')
           
           safe_path = CGI.escapeHTML(relative_path)
           
           # Use simple <p> tag to match other form fields
           info_html = <<~HTML.strip.gsub("\n", "")
             <p id="subwikifiles_path_info">
               #{safe_path}
             </p>
           HTML
           
           path_js = <<~JS
             $(document).ready(function() {
               var infoHtml = '#{escape_javascript(info_html)}';
               var $info = $(infoHtml);
               
               var movePathInfo = function() {
                 if ($('#subwikifiles_path_info').length > 0) return; // Already present
                 
                 // Try to insert after comments field
                 // Selectors: #wiki_page_comments (standard), #content_comments (observed)
                 var commentField = $('#wiki_page_comments, #content_comments').first();
                 var target = commentField.closest('p');
                 
                 if (target.length) {
                   target.after($info);
                   console.log('RedmineSubwikifiles: Injected path info after comments');
                 } else {
                   // Fallback: prepend to attachments fields
                   // Selectors: #attachments_fields (standard), #new-attachments (observed)
                   var attachments = $('#attachments_fields, #new-attachments').first();
                   if (attachments.length) {
                      attachments.before($info);
                      console.log('RedmineSubwikifiles: Injected path info before attachments');
                   } else {
                      // Final fallback: append to form
                      var form = $('#wiki_form');
                      if (form.length) {
                        form.append($info);
                        console.log('RedmineSubwikifiles: Injected path info at end of form');
                      }
                   }
                 }
               };
               
               setTimeout(movePathInfo, 100);
             });
           JS
           
           response += javascript_tag(path_js)
        end
      end
      
      response
    end

    # Global hook for body bottom - apparently not reliable, so logic moved to head
    def view_layouts_base_body_bottom(context = {})
      # No-op now
    end

    private

    def build_js(controller)
      return '' unless controller
      return '' unless controller.class.name == 'WikiController'
      return '' unless ['index', 'show', 'edit'].include?(controller.action_name)
      
      pending_files_json = controller.instance_variable_get(:@pending_files_json)
      return '' unless pending_files_json.present?
      
      translations = {
        fix_wiki: I18n.t('redmine_subwikifiles.tooltips.fix_wiki'),
        fix_attachment: I18n.t('redmine_subwikifiles.tooltips.fix_attachment'),
        confirm_wiki: I18n.t('redmine_subwikifiles.confirmations.fix_wiki'),
        confirm_attachment: I18n.t('redmine_subwikifiles.confirmations.fix_attachment'),
        parent_info: I18n.t('redmine_subwikifiles.confirmations.parent_info'),
        fix_failed: I18n.t('redmine_subwikifiles.errors.fix_failed')
      }
      
      js_code = <<~JS
          (function() {
            var filesData = #{pending_files_json};
            var i18n = #{translations.to_json};
            
            // Inject CSS for the button
            var style = document.createElement('style');
            style.innerHTML = `
              .fix-file-btn {
                color: #33a;
                text-decoration: none;
                margin: 0 5px;
                font-weight: bold;
                font-size: 0.85em; /* 20% smaller */
                cursor: pointer;
                background-color: #f8f9fa;
                padding: 1px 6px; /* Reduced padding */
                border: 1px solid #ddd;
                border-radius: 3px;
                display: inline-block;
                transition: background-color 0.2s;
              }
              .fix-file-btn:hover {
                background-color: #e2e6ea;
                text-decoration: none;
                color: #229;
              }
            `;
            document.head.appendChild(style);
            
            function createFixButton(filename, type) {
              var btn = document.createElement('a');
              btn.href = 'javascript:void(0)'; // Prevent navigation
              btn.className = 'fix-file-btn';
              
              // Tooltip
              var tooltip = type === 'wiki' ? i18n.fix_wiki : i18n.fix_attachment;
              btn.title = tooltip;
              
              btn.addEventListener('click', function(e) {
                e.preventDefault();
                e.stopPropagation(); // Stop bubbling just in case
                console.log('Fix button clicked', filename, type);
                // alert('Debug: Button clicked for ' + filename); 
                
                if (btn.getAttribute('data-working')) return;
                
                var pathParts = location.pathname.split('/');
                var projectIndex = pathParts.indexOf('projects');
                var projectId = projectIndex >= 0 ? pathParts[projectIndex + 1] : null;
                
                var pageId = null;
                var wikiIndex = pathParts.indexOf('wiki');
                if (wikiIndex >= 0 && pathParts.length > wikiIndex + 1) {
                  pageId = pathParts[wikiIndex + 1];
                }
                
                var confirmMsg;
                if (type === 'wiki') {
                  confirmMsg = i18n.confirm_wiki.replace('%{file}', filename);
                  if (pageId) {
                     confirmMsg += "\\n" + i18n.parent_info.replace('%{parent}', decodeURIComponent(pageId));
                  }
                } else {
                  confirmMsg = i18n.confirm_attachment.replace('%{file}', filename);
                }
                
                if (!confirm(confirmMsg)) return;
                
                // Check if we're in edit mode
                var textarea = document.querySelector('textarea#content_text');
                var isEditMode = textarea && textarea.offsetParent !== null; // offsetParent check ensures it's visible
                var cursorPosition = isEditMode ? textarea.selectionStart : null;
                
                btn.setAttribute('data-working', 'true');
                btn.style.opacity = '0.5';
                btn.innerHTML = ' ...';
                
                if (type === 'attachment' && !pageId) {
                  if (wikiIndex >= 0 && pathParts.length > wikiIndex + 1) {
                     pageId = pathParts[wikiIndex + 1];
                  }
                }

                var url = type === 'wiki' ? 
                  '/projects/' + projectId + '/subwikifiles/fix_frontmatter' :
                  '/projects/' + projectId + '/subwikifiles/attach_file';
                  
                var body = type === 'wiki' ? 
                  JSON.stringify({ files: [filename], page_id: pageId }) :
                  JSON.stringify({ file: filename, page_id: pageId });
                
                var tokenMeta = document.querySelector('meta[name="csrf-token"]');
                var csrfToken = tokenMeta ? tokenMeta.content : null;

                console.log('RedmineSubwikifiles: Sending request to ' + url, body);
                fetch(url, {
                  method: 'POST',
                  headers: {
                    'Content-Type': 'application/json',
                    'X-CSRF-Token': csrfToken
                  },
                  body: body
                })
                .then(function(r) { 
                  console.log('RedmineSubwikifiles: Received response status ' + r.status);
                  return r.json(); 
                })
                .then(function(data) {
                  console.log('RedmineSubwikifiles: Response data', data);
                  if ((data.fixed && data.fixed.length > 0) || data.success) {
                    // If in edit mode, insert link at cursor
                    if (isEditMode) {
                      var link = '';
                      
                      if (type === 'wiki') {
                        // Wiki page link
                        link = '[[' + filename + ']]';
                      } else {
                        // Attachment link - check if it's an image
                        var imageExtensions = ['png', 'jpg', 'jpeg', 'gif', 'svg', 'bmp'];
                        var ext = filename.split('.').pop().toLowerCase();
                        
                        if (imageExtensions.indexOf(ext) >= 0) {
                          // Inline image (Markdown syntax)
                          link = '![](' + filename + ')';
                        } else {
                          // Regular attachment link
                          link = '[' + filename + '](attachment:' + filename + ')';
                        }
                      }
                      
                      var textBefore = textarea.value.substring(0, cursorPosition);
                      var textAfter = textarea.value.substring(cursorPosition);
                      textarea.value = textBefore + link + textAfter;
                      
                      // Move cursor after the inserted link
                      textarea.selectionStart = textarea.selectionEnd = cursorPosition + link.length;
                      textarea.focus();
                      
                      // Robust removal logic
                      var entry = btn.closest('.orphan-file-entry');
                      var flashWarning = btn.closest('.flash.warning');
                      
                      if (entry) {
                        // 1. Clean up adjacent commas and spaces
                        var parent = entry.parentNode;
                        var nodes = Array.from(parent.childNodes);
                        var index = nodes.indexOf(entry);
                        
                        // Check following node for comma
                        if (index < nodes.length - 1) {
                          var next = nodes[index + 1];
                          if (next.nodeType === 3 && /^\s*,/.test(next.nodeValue)) {
                            next.nodeValue = next.nodeValue.replace(/^\s*,\s*/, ' ');
                          }
                        } 
                        // If no next comma, check previous node for comma (if it was the last item)
                        else if (index > 0) {
                          var prev = nodes[index - 1];
                          if (prev.nodeType === 3 && /,\s*$/.test(prev.nodeValue)) {
                            prev.nodeValue = prev.nodeValue.replace(/\s*,\s*$/, ' ');
                          }
                        }
                        
                        // 2. Decrement the count in the flash message text
                        if (flashWarning) {
                          var walker = document.createTreeWalker(flashWarning, NodeFilter.SHOW_TEXT, null, false);
                          var textNode;
                          while (textNode = walker.nextNode()) {
                            // Look for "X files" or "X Dateien"
                            var match = textNode.nodeValue.match(/(\\d+)\s+(files|Datei(en)?)/i);
                            if (match) {
                              var count = parseInt(match[1]);
                              if (count > 0) {
                                textNode.nodeValue = textNode.nodeValue.replace(match[0], (count - 1) + ' ' + match[2]);
                              }
                              break;
                            }
                          }
                        }

                        // 3. Remove the entry span (contains filename, error, and button)
                        entry.remove();
                        
                        // 4. Check if flash should be removed (no more orphan entries)
                        if (flashWarning && !flashWarning.querySelector('.orphan-file-entry')) {
                          flashWarning.remove();
                        }
                      }
                    } else {
                      // View mode: remove entry without reload
                      var entry = btn.closest('.orphan-file-entry');
                      var flashWarning = btn.closest('.flash.warning');
                      
                      if (entry) {
                        entry.remove();
                      }
                      
                      if (flashWarning && !flashWarning.querySelector('.orphan-file-entry')) {
                        flashWarning.remove();
                      }
                    }
                  } else if (data.failed && data.failed.length > 0) {
                    var errorMsg = data.failed.map(function(f) { 
                        return f.file + ': ' + (f.error || 'Unknown error'); 
                    }).join('\\n');
                    alert(i18n.fix_failed + '\\n' + errorMsg);
                    
                    btn.removeAttribute('data-working');
                    btn.style.opacity = '1';
                    btn.innerHTML = ' ⏎'; // Return symbol
                  } else {
                    alert('Error: ' + (data.error || 'Unknown error'));
                    btn.removeAttribute('data-working');
                    btn.style.opacity = '1';
                    btn.innerHTML = ' ⏎'; // Return symbol
                  }
                })
                .catch(function(err) {
                  alert('Error: ' + err.message);
                  btn.removeAttribute('data-working');
                  btn.style.opacity = '1';
                  btn.innerHTML = ' ⏎'; // Return symbol
                });
              });
              
              return btn;
            }
            
            document.addEventListener('DOMContentLoaded', function() {
              var flashWarning = document.querySelector('.flash.warning');
              if (!flashWarning || !filesData || filesData.length === 0) return;
              
              // Prevent duplicate injection
              if (flashWarning.querySelector('.fix-file-btn')) return;

              filesData.forEach(function(fileInfo) {
                var filename = fileInfo.file;
                var safeId = fileInfo.id;
                var type = fileInfo.type; // 'wiki' or 'attachment'
                
                var btn = createFixButton(filename, type);
                
                // Find our wrapped span using safeId
                var selector = '.orphan-file-entry[data-file-id="' + safeId + '"]';
                var entry = flashWarning.querySelector(selector);
                
                if (entry) {
                   btn.innerHTML = ' ⏎'; // Return symbol
                   entry.appendChild(btn);
                } else {
                   // Fallback for cases where server-side wrapping might have missed something
                   console.log('RedmineSubwikifiles: Span for ' + filename + ' (' + safeId + ') not found. Falling back to text search.');
                   
                   var walker = document.createTreeWalker(flashWarning, NodeFilter.SHOW_TEXT, null, false);
                   var node;
                   while(node = walker.nextNode()) {
                     var text = node.nodeValue;
                     var index = text.indexOf(filename);
                     if (index >= 0) {
                        // Greedily look for following error message in parentheses: " (missing ...)"
                        var remainingText = text.substring(index + filename.length);
                        var errorMatch = remainingText.match(/^ \([^)]+\)/);
                        var wrapLength = filename.length + (errorMatch ? errorMatch[0].length : 0);
                        
                        var filenameNode = node.splitText(index);
                        var nextPart = filenameNode.splitText(wrapLength);
                        
                        var container = document.createElement('span');
                        container.className = 'orphan-file-entry';
                        if (safeId) container.setAttribute('data-file-id', safeId);
                        
                        container.appendChild(filenameNode);
                        container.appendChild(btn);
                        
                        node.parentNode.insertBefore(container, nextPart);
                        break;
                     }
                   }
                }
              });
            });
          })();
      JS
      
      js_code.html_safe
    end
    
    # Remove body hook as head is sufficient
    def view_layouts_base_body_bottom(context={})
      ''
    end
  end
end
