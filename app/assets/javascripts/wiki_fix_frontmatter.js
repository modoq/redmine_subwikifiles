// Auto-fix frontmatter button for wiki index
(function () {
    'use strict';

    // Run on DOM ready
    document.addEventListener('DOMContentLoaded', function () {
        // Only run on wiki index pages
        if (!document.querySelector('body.controller-wiki.action-index')) {
            return;
        }

        // Check if there's a warning flash with invalid files data
        const flashWarning = document.querySelector('.flash.warning');
        if (!flashWarning) {
            return;
        }

        // Get invalid files data from data attribute (set by controller)
        const invalidFilesAttr = flashWarning.getAttribute('data-invalid-files');
        if (!invalidFilesAttr) {
            return;
        }

        try {
            const invalidFiles = JSON.parse(invalidFilesAttr);
            if (!invalidFiles || invalidFiles.length === 0) {
                return;
            }

            // Create fix button
            const fixButton = document.createElement('button');
            fixButton.textContent = 'Add Frontmatter';
            fixButton.className = 'fix-frontmatter-btn';
            fixButton.style.marginLeft = '10px';
            fixButton.style.padding = '5px 10px';
            fixButton.style.cursor = 'pointer';

            fixButton.addEventListener('click', function (e) {
                e.preventDefault();

                if (!confirm(`Add frontmatter to ${invalidFiles.length} file(s)?`)) {
                    return;
                }

                // Disable button
                fixButton.disabled = true;
                fixButton.textContent = 'Fixing...';
                fixButton.style.cursor = 'wait';

                // Get project ID from URL
                const pathParts = window.location.pathname.split('/');
                const projectIndex = pathParts.indexOf('projects');
                const projectId = projectIndex >= 0 ? pathParts[projectIndex + 1] : null;

                if (!projectId) {
                    alert('Could not determine project ID');
                    fixButton.disabled = false;
                    fixButton.textContent = 'Add Frontmatter';
                    fixButton.style.cursor = 'pointer';
                    return;
                }

                // Get CSRF token
                const csrfToken = document.querySelector('meta[name="csrf-token"]');
                if (!csrfToken) {
                    alert('CSRF token not found');
                    fixButton.disabled = false;
                    fixButton.textContent = 'Add Frontmatter';
                    fixButton.style.cursor = 'pointer';
                    return;
                }

                // Send AJAX request
                fetch(`/projects/${projectId}/subwikifiles/fix_frontmatter`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-CSRF-Token': csrfToken.content
                    },
                    body: JSON.stringify({ files: invalidFiles })
                })
                    .then(response => response.json())
                    .then(data => {
                        if (data.fixed && data.fixed.length > 0) {
                            alert(`Fixed ${data.fixed.length} file(s): ${data.fixed.join(', ')}\\n\\nPage will reload to import the fixed files.`);
                            location.reload();
                        } else if (data.failed && data.failed.length > 0) {
                            const failedList = data.failed.map(f => `${f.file}: ${f.error}`).join('\\n');
                            alert(`Failed to fix files:\\n${failedList}`);
                            fixButton.disabled = false;
                            fixButton.textContent = 'Add Frontmatter';
                            fixButton.style.cursor = 'pointer';
                        } else {
                            alert('No files were fixed.');
                            fixButton.disabled = false;
                            fixButton.textContent = 'Add Frontmatter';
                            fixButton.style.cursor = 'pointer';
                        }
                    })
                    .catch(error => {
                        console.error('Fix frontmatter error:', error);
                        alert('Error: ' + error.message);
                        fixButton.disabled = false;
                        fixButton.textContent = 'Add Frontmatter';
                        fixButton.style.cursor = 'pointer';
                    });
            });

            // Append button to flash message
            flashWarning.appendChild(fixButton);

        } catch (e) {
            console.error('Error parsing invalid files data:', e);
        }
    });
})();
