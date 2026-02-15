# Redmine SubWikifiles - Technical Documentation

This documentation describes the internal workings, architecture, and critical points that must be considered during the development and maintenance of the **Redmine SubWikifiles** plugin.

## 1. Core Concept & Architecture

The plugin enables bidirectional synchronization between Redmine wiki pages and Markdown files (.md) on the filesystem.

### Storage Structure
- **Base Directory**: Configurable via plugin settings (default: `/var/lib/redmine/wiki_files`).
- **Project Isolation**: Each Redmine project gets its own subfolder, named after its identifier (e.g., `repro-ui/`).
- **Hierarchy**: The wiki page hierarchy is represented by the directory structure (parent pages are folders).
- **Filenames**: Filenames correspond to the "titleized" wiki titles (e.g., `Wiki_Page` -> `Wiki Page.md`).

## 2. Synchronization Logic

The plugin uses two main mechanisms (patches) to ensure synchronicity:

### A. Write-Back (Redmine -> Filesystem)
Using a patch on `WikiContent#before_save`, every change in the wiki editor is immediately written to the disk.
- **Frontmatter**: A YAML header containing metadata (`id`, `parent`, `created`, `updated`) is generated.
- **Git Commit**: After writing, a Git commit is automatically performed in the name of the current user.

### B. Sync-on-Load (Filesystem -> Redmine)
Using a patch on `WikiController#before_action` (for `show`, `edit`, `index`), changes from external editors are detected.
- **Timestamp Comparison**: If the file is newer than the database entry, the DB content is updated.
- **Normalization**: Filenames are normalized using `Wiki.titleize` to match Redmine's internal title system.

## 3. Metadata (Frontmatter)

Each MD file begins with a YAML block:
```yaml
---
parent: Main Page
id: 42
created: '2026-02-15T12:00:00Z'
updated: '2026-02-15T12:00:00Z'
---
```
- **Parent**: Defines the position in the wiki tree.
- **ID**: Used for robust detection during renames (planned/in preparation).

## 4. Critical Implementation Details (Developer Checklist)

When making changes to the plugin, the following points must be observed:

### 1. Title Normalization (`Wiki.titleize`)
Redmine is very specific with wiki titles (e.g., underscores become spaces). Every search for files or pages must run through `Wiki.titleize`; otherwise, duplicates or "dead" orphans will occur.

### 2. Avoiding Infinite Loops
To prevent a filesystem update from triggering a save hook and creating an infinite loop, the plugin uses:
- `Thread.current[:redmine_subwikifiles_syncing] = true`
Every automated change sets this flag to suppress recursive hook calls.

### 3. Orphan Detection (Unassigned Files)
Files without a corresponding wiki entry are reported as "orphans" in the UI.
- Clicking "Fix" creates the wiki page in the DB.
- **Important**: During this process, the original file might need to be deleted if Redmine normalizes the name (e.g., `Loop_Test.md` -> `Loop Test.md`) to avoid double detection.

### 4. Git Integration
The `GitBackend` service assumes that the base directory (or project subfolders) are Git repositories. Errors in the Git process are logged but do not interrupt the wiki saving process.

### 5. Permissions
Synchronization and UI elements (Fix buttons) are bound to the Redmine permission `:edit_wiki_pages`.

## 5. Special Cases

- **Attachments**: These are synchronized in a special `_attachments/` folder.
- **Restoration (Restore)**: If a file is missing on the filesystem but exists in the wiki, the UI offers a "Restore" function. This uses the `write_to_md_file_with_frontmatter` method to rewrite the file including all metadata (parent, ID, timestamps).
- **Renames**: When a wiki page is renamed in Redmine, the `WikiPagePatch` moves the file on the disk accordingly.

---
*Documentation created on Feb 15, 2026, by Antigravity.*
