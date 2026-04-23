;;; autoslip-roam.el --- Automatic folgezettel backlink generation for org-roam -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Blaine Mooers
;; Version: 3.0.0
;; Package-Requires: ((emacs "27.1") (org-roam "2.0"))
;; Keywords: org-mode, org-roam, zettelkasten, folgezettel
;; URL: https://github.com/MooersLab/autoslip-roam

;;; Commentary:

;; This package provides automatic backlink generation for org-roam notes
;; that use folgezettel indexing (e.g., 1.2a3c5d7a, 1.13aa, 1.2a15).
;;
;; When you create a new note with a folgezettel in its title, this package
;; will automatically:
;; 1. Parse the folgezettel to identify the parent note's address
;; 2. Search the org-roam database for the parent note
;; 3. Insert a backlink to the parent note under "** Parent Note" in the child
;; 4. Insert a forward link to the child note under "** Child Notes" in the parent
;;
;; When using `autoslip-roam-insert-next-child' to create a child note:
;; - The parent node is stored before capture begins
;; - After the capture is finalized, bidirectional links are automatically created
;; - The child note gets a link to the parent under "** Parent Note"
;; - The parent note gets a link to the new child under "** Child Notes"
;;
;; Additionally, when you manually insert a link to another org-roam note,
;; this package will automatically create a reciprocal link in the target
;; note (bidirectional cross-linking).  This behavior can be controlled via
;; the `autoslip-roam-auto-crosslink' customization variable.
;;
;; Example folgezettel hierarchy:
;;   1.          - First note in chain (root; trailing period is canonical)
;;   1.2         - Second subtopic of note 1.
;;   1.13        - Thirteenth subtopic of note 1.
;;   1.13a       - First letter-indexed child of 1.13
;;   1.13b       - Second letter-indexed child of 1.13
;;   1.13aa      - 27th letter-indexed child of 1.13 (after z comes aa)
;;   1.13a2      - Second numeric child of 1.13a
;;   1.13a2b     - Second letter-indexed child of 1.13a2
;;
;; Parent-child relationships:
;;   1.   is parent of: 1.1, 1.2, 1.13, ...
;;   1.13 is parent of: 1.13a, 1.13b, ..., 1.13z, 1.13aa, 1.13ab, ...
;;   1.13a is parent of: 1.13a1, 1.13a2, 1.13a3, ..., 1.13a99, ..., 1.13a201, ...
;;   1.13a2 is parent of: 1.13a2a, 1.13a2b, ..., 1.13a2z, 1.13a2aa, ...
;;
;; Titles written in the legacy form "1 Crystallography" (no trailing period)
;; are still accepted; they are canonicalized to "1." on extraction so that
;; every internally produced address carries the expected period.
;;
;; Installation:
;; 1. Place this file in your load-path
;; 2. Add to your init.el:
;;    (require 'autoslip-roam)
;;    (autoslip-roam-mode 1)

;;; Code:

(require 'cl-lib)
(require 'org-roam)
(require 'org-roam-db)

(defgroup autoslip-roam nil
  "Automatic folgezettel backlink generation for org-roam."
  :group 'org-roam
  :prefix "autoslip-roam-")

(defcustom autoslip-roam-parent-link-description "Parent note"
  "Description text for automatically generated parent links."
  :type 'string
  :group 'autoslip-roam)

(defcustom autoslip-roam-child-link-description nil
  "Description text for automatically generated child links.
If nil, use the child note's title."
  :type '(choice (const :tag "Use child title" nil)
                 (string :tag "Custom description"))
  :group 'autoslip-roam)

(defcustom autoslip-roam-backlink-heading "Parent Note"
  "Heading under which to insert parent backlinks in child notes.
If nil, insert at the beginning of the buffer after properties."
  :type '(choice (const :tag "No heading" nil)
                 (string :tag "Heading name"))
  :group 'autoslip-roam)

(defcustom autoslip-roam-forward-link-heading "Child Notes"
  "Heading under which to insert child forward links in parent notes.
If nil, insert at the end of the buffer."
  :type '(choice (const :tag "At end of buffer" nil)
                 (string :tag "Heading name"))
  :group 'autoslip-roam)

(defcustom autoslip-roam-regex
  "\\b\\([0-9]+\\(?:[.][0-9]+\\)*\\(?:[a-z]+\\(?:[0-9]+\\)?\\)*\\)\\(?:[^a-z0-9]\\|$\\)"
  "Regular expression to match folgezettel patterns.
Matches patterns like: 1, 1.2, 1.13, 1.2a, 1.2aa, 1.2a15, 1.2a3c5d7a
The pattern ensures complete matches by requiring non-alphanumeric or end of string after the pattern."
  :type 'regexp
  :group 'autoslip-roam)

(defcustom autoslip-roam-auto-crosslink t
  "Automatically create bidirectional links when inserting cross-links.
When non-nil, inserting a link to another org-roam note will automatically
insert a reciprocal link in the target note."
  :type 'boolean
  :group 'autoslip-roam)

(defcustom autoslip-roam-crosslink-heading "Cross References"
  "Heading under which to insert reciprocal cross-links.
If nil, insert at the end of the buffer."
  :type '(choice (const :tag "At end of buffer" nil)
                 (string :tag "Heading name"))
  :group 'autoslip-roam)

(defcustom autoslip-roam-sync-db-before-queries t
  "Sync org-roam database before queries in interactive functions.
When non-nil, interactive commands will sync the org-roam database before
querying for parent nodes or checking for duplicates.  This ensures the most
current data is available but may add a slight delay.
Recommended: t (enabled) for best reliability."
  :type 'boolean
  :group 'autoslip-roam)

(defcustom autoslip-roam-link-storage 'headings
  "How to store parent and child links in notes.

Possible values:

`headings'    (default) Write visible org headings (\"Parent Note\",
              \"Child Notes\") into the body of each note with links
              beneath them.  This keeps the hierarchy legible even if
              the org-roam database is lost and is the best choice for
              workflows that mirror the slip-box on paper.

`properties'  Store the parent node ID in a top-level property drawer
              under `autoslip-roam-parent-property' and the
              child node IDs under
              `autoslip-roam-children-property'.  This leaves
              the body of each file free of automatic link text,
              which reduces noise and shrinks the surface area for
              merge conflicts in a synced or version-controlled vault.

Switching between the two modes does not migrate existing notes;
use `autoslip-roam-convert-link-storage' to do that."
  :type '(choice (const :tag "Visible headings (default)" headings)
                 (const :tag "Property drawer (quiet)" properties))
  :group 'autoslip-roam)

(defcustom autoslip-roam-parent-property "FZ_PARENT"
  "Property-drawer key used to store the parent node ID.
Only consulted when `autoslip-roam-link-storage' is `properties'."
  :type 'string
  :group 'autoslip-roam)

(defcustom autoslip-roam-children-property "FZ_CHILDREN"
  "Property-drawer key used to store child node IDs.
Only consulted when `autoslip-roam-link-storage' is `properties'.
The value is a comma-separated list of org-roam node IDs."
  :type 'string
  :group 'autoslip-roam)

(defcustom autoslip-roam-chain-heading "Chain of Thought"
  "Heading inserted above the chain-of-thought outline in a note.
Set to nil to insert the chain at point without a heading."
  :type '(choice (const :tag "No heading" nil) string)
  :group 'autoslip-roam)

(defcustom autoslip-roam-chain-crosslink-heading "Cross-linked Chains of Thought"
  "Heading used when inserting cross-linked chains of thought in a note."
  :type '(choice (const :tag "No heading" nil) string)
  :group 'autoslip-roam)

(defcustom autoslip-roam-rename-files-on-reparent t
  "Whether to rename files on disk when reparenting a note.
When non-nil, `autoslip-roam-reparent' and
`autoslip-roam-reparent-subtree' substitute the old folgezettel
with the new one in each affected file name, preserving extension and
directory.  When nil, only the in-file title is rewritten and the file
keeps its original name.  The rename is skipped for any file whose
basename does not contain the old folgezettel."
  :type 'boolean
  :group 'autoslip-roam)

(defvar autoslip-roam--pending-parent-node nil
  "Stores the parent node when creating a child note via
`autoslip-roam-insert-next-child'.
This ensures the parent information is available when the capture hook fires.")

(defvar autoslip-roam--pending-child-title nil
  "Stores the full title of the child note being created.
Used to verify the correct note is being processed in the capture hook.")

(defun autoslip-roam--maybe-sync-db ()
  "Sync org-roam database if `autoslip-roam-sync-db-before-queries' is non-nil."
  (when autoslip-roam-sync-db-before-queries
    (org-roam-db-sync)))



(defun autoslip-roam--root-address-p (address)
  "Return non-nil if ADDRESS is a root, i.e. digits with an optional trailing period.
Both the canonical form \"1.\" and the legacy bare form \"1\" are accepted."
  (and (stringp address)
       (string-match-p "\\`[0-9]+\\.?\\'" address)))

(defun autoslip-roam--canonicalize-root (address)
  "Return ADDRESS with a trailing period if it is a bare-integer root.
Non-root addresses are returned unchanged.  The trailing period is the
canonical marker for a root note, matching the style used in numbered
outlines like \"1. Crystallography\"."
  (cond
   ((not (stringp address)) address)
   ((string-match-p "\\`[0-9]+\\'" address) (concat address "."))
   (t address)))

(defun autoslip-roam--parse-address (folgezettel)
  "Parse FOLGEZETTEL string and return the parent's address.

The pattern alternates between numbers and letters:
- Numbers after dots indicate subtopics
- Letters indicate alphabetic children
- Numbers after letters indicate numeric children

Root notes carry a trailing period (for example \"1.\").  The bare form
\"1\" is accepted for backward compatibility and treated as the same root.

Examples:
  1.2a3c5   -> 1.2a3c   (remove last number)
  1.13aa    -> 1.13     (remove all trailing letters)
  1.13a     -> 1.13     (remove all trailing letters)
  1.2a      -> 1.2      (remove all trailing letters)
  1.13      -> 1.       (remove the trailing dot-number, leaving canonical root)
  1.        -> nil      (no parent)
  1         -> nil      (no parent, legacy bare root)"
  (when (and folgezettel (string-match autoslip-roam-regex folgezettel))
    (let ((addr folgezettel))
      (cond
       ;; Ends with numbers after letters (e.g., "1.2a15" -> "1.2a")
       ((string-match "\\(.*[a-z]+\\)[0-9]+$" addr)
        (match-string 1 addr))
       ;; Ends with letters (e.g., "1.13aa" -> "1.13", "1.13a" -> "1.13")
       ;; Remove ALL trailing letters to get parent
       ((string-match "\\(.*?\\)[a-z]+$" addr)
        (match-string 1 addr))
       ;; Ends with numbers after a dot (e.g., "1.13" -> "1.")
       ;; Append the canonical trailing period to the captured root.
       ((string-match "\\(.*\\)[.][0-9]+$" addr)
        (concat (match-string 1 addr) "."))
       ;; Bare or canonical root (e.g., "1", "1.") -> no parent
       ((autoslip-roam--root-address-p addr)
        nil)
       (t nil)))))

(defun autoslip-roam--extract-from-title (title)
  "Extract folgezettel pattern from TITLE string.
Returns the folgezettel if found, nil otherwise.
Bare-integer roots (\"1\") are canonicalized to \"1.\" so that every
address returned carries the expected trailing period at root."
  (when (and title (string-match autoslip-roam-regex title))
    (autoslip-roam--canonicalize-root (match-string 1 title))))

(defun autoslip-roam--find-parent-node (parent-address)
  "Find org-roam node with PARENT-ADDRESS in its title.
Returns the node object if found, nil otherwise."
  (when parent-address
    (let ((nodes (org-roam-node-list)))
      (catch 'found
        (dolist (node nodes)
          (let* ((title (org-roam-node-title node))
                 (fz (autoslip-roam--extract-from-title title)))
            (when (and fz (string= fz parent-address))
              (throw 'found node))))
        nil))))

(defun autoslip-roam-diagnose-address (address)
  "Diagnose issues with finding a folgezettel ADDRESS.
Shows what nodes exist and what folgezettel patterns are extracted from them."
  (interactive "sEnter folgezettel address to diagnose: ")
  (let ((nodes (org-roam-node-list))
        (found-nodes '()))
    (message "Diagnosing address: %s" address)
    (message "Searching through %d nodes..." (length nodes))
    (dolist (node nodes)
      (let* ((title (org-roam-node-title node))
             (fz (autoslip-roam--extract-from-title title)))
        (when fz
          (push (cons fz title) found-nodes)
          (when (string= fz address)
            (message "FOUND MATCH: '%s' extracted from title '%s'" fz title)))))
    (message "---")
    (message "All folgezettel patterns found in vault:")
    (dolist (pair (reverse found-nodes))
      (message "  %s -> %s" (car pair) (cdr pair)))
    (message "---")
    (unless (assoc address found-nodes)
      (message "No node found with folgezettel '%s'" address))))

(defun autoslip-roam--index-exists-p (address)
  "Check if a folgezettel ADDRESS already exists in the vault.
Returns the node if found, nil otherwise."
  (when address
    (let ((nodes (org-roam-node-list)))
      (catch 'found
        (dolist (node nodes)
          (let* ((title (org-roam-node-title node))
                 (fz (autoslip-roam--extract-from-title title)))
            (when (and fz (string= fz address))
              (throw 'found node))))
        nil))))

(defun autoslip-roam-check-duplicate-index (address)
  "Check if ADDRESS is already used and warn the user if so.
Returns t if the address is available, nil if it's already used.
Shows a warning popup if the address is already in use."
  (interactive "sEnter folgezettel address to check: ")
  ;; Sync database when called interactively
  (when (called-interactively-p 'any)
    (autoslip-roam--maybe-sync-db))
  (let ((existing-node (autoslip-roam--index-exists-p address)))
    (if existing-node
        (progn
          (display-warning
           'autoslip-roam
           (format "Duplicate index detected!\n\nThe folgezettel address '%s' is already used by:\n\n  \"%s\"\n\nPlease choose a different address."
                   address
                   (org-roam-node-title existing-node))
           :warning)
          nil)
      (when (called-interactively-p 'any)
        (message "Address '%s' is available." address))
      t)))

(defun autoslip-roam--get-top-property (key)
  "Return the value of top-level property KEY, or nil if not set."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^:PROPERTIES:" nil t)
      (let ((end (save-excursion
                   (re-search-forward "^:END:" nil t))))
        (when (and end
                   (re-search-forward
                    (format "^:%s:[ \t]*\\(.*\\)$" (regexp-quote key))
                    end t))
          (let ((v (match-string 1)))
            (and v (not (string-empty-p v))
                 (replace-regexp-in-string "[ \t]+$" "" v))))))))

(defun autoslip-roam--set-top-property (key value)
  "Set the top-level property KEY to VALUE, creating the drawer if needed."
  (save-excursion
    (goto-char (point-min))
    (let ((has-drawer (save-excursion (re-search-forward "^:PROPERTIES:" nil t))))
      (unless has-drawer
        ;; Insert a drawer after leading #+keyword lines
        (while (and (not (eobp)) (looking-at "^#\\+"))
          (forward-line 1))
        (insert ":PROPERTIES:\n:END:\n")))
    (goto-char (point-min))
    (re-search-forward "^:PROPERTIES:" nil t)
    (let ((end (save-excursion (re-search-forward "^:END:" nil t))))
      (if (re-search-forward
           (format "^:%s:.*$" (regexp-quote key)) end t)
          (replace-match (format ":%s: %s" key value) t t)
        (goto-char end)
        (beginning-of-line)
        (insert (format ":%s: %s\n" key value))))))

(defun autoslip-roam--children-property-ids ()
  "Return the list of child IDs stored in the children property, or nil."
  (let ((raw (autoslip-roam--get-top-property
              autoslip-roam-children-property)))
    (when (and raw (not (string-empty-p raw)))
      (split-string raw "[, ]+" t "[ \t]+"))))

(defun autoslip-roam--set-children-property-ids (ids)
  "Write IDS (a list) into the children property as a comma-separated list."
  (if ids
      (autoslip-roam--set-top-property
       autoslip-roam-children-property
       (string-join (delete-dups (copy-sequence ids)) ","))
    (autoslip-roam--delete-top-property
     autoslip-roam-children-property)))

(defun autoslip-roam--delete-top-property (key)
  "Remove the top-level property KEY from the current buffer, if present."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^:PROPERTIES:" nil t)
      (let ((end (save-excursion (re-search-forward "^:END:" nil t))))
        (when (and end
                   (re-search-forward
                    (format "^:%s:.*$" (regexp-quote key)) end t))
          (let ((lb (line-beginning-position))
                (le (1+ (line-end-position))))
            (delete-region lb le)))))))

(defun autoslip-roam--insert-backlink-headings (parent-node)
  "Insert a visible-heading parent backlink to PARENT-NODE in the current buffer."
  (let* ((parent-id (org-roam-node-id parent-node))
         (parent-title (org-roam-node-title parent-node))
         (description (or autoslip-roam-parent-link-description parent-title)))
    (save-excursion
      (goto-char (point-min))
      ;; Skip past file-level properties
      (while (and (not (eobp))
                  (or (looking-at "^#\\+")
                      (looking-at "^:[A-Z]+:")
                      (looking-at "^$")))
        (forward-line 1))

      ;; If heading is specified, find or create it
      (if autoslip-roam-backlink-heading
          (progn
            (unless (re-search-forward
                     (concat "^\\*+ " (regexp-quote autoslip-roam-backlink-heading))
                     nil t)
              ;; Heading does not exist, create it
              (goto-char (point-max))
              (unless (bolp) (insert "\n"))
              (insert "\n* " autoslip-roam-backlink-heading "\n"))
            (end-of-line)
            (insert "\n"))
        ;; No heading, insert right after properties
        (unless (bolp) (insert "\n")))

      ;; Insert the backlink - use description only if non-empty
      (if (and description (not (string-empty-p description)))
          (insert (format "[[id:%s][%s]]\n" parent-id description))
        (insert (format "[[id:%s]]\n" parent-id))))))

(defun autoslip-roam--insert-backlink-properties (parent-node)
  "Record the parent link to PARENT-NODE in the top-level property drawer."
  (let ((parent-id (org-roam-node-id parent-node)))
    (save-excursion
      (autoslip-roam--set-top-property
       autoslip-roam-parent-property parent-id))))

(defun autoslip-roam--insert-backlink (parent-node)
  "Insert a backlink to PARENT-NODE in the current buffer.
Dispatches on `autoslip-roam-link-storage'."
  (pcase autoslip-roam-link-storage
    ('properties (autoslip-roam--insert-backlink-properties parent-node))
    (_           (autoslip-roam--insert-backlink-headings parent-node))))

(defun autoslip-roam--insert-forward-link-headings (child-node parent-file)
  "Append a Child Notes heading entry for CHILD-NODE into PARENT-FILE."
  (let* ((child-id (org-roam-node-id child-node))
         (child-title (org-roam-node-title child-node))
         (link-desc (or autoslip-roam-child-link-description child-title)))
    (with-current-buffer (find-file-noselect parent-file)
      (save-excursion
        (goto-char (point-max))

        ;; If heading is specified, find or create it
        (if autoslip-roam-forward-link-heading
            (progn
              (goto-char (point-min))
              (unless (re-search-forward
                       (concat "^\\*+ " (regexp-quote autoslip-roam-forward-link-heading))
                       nil t)
                ;; Heading does not exist, create it at end
                (goto-char (point-max))
                (unless (bolp) (insert "\n"))
                (insert "\n* " autoslip-roam-forward-link-heading "\n"))
              (end-of-line)
              (insert "\n"))
          ;; No heading, insert at end of buffer
          (goto-char (point-max))
          (unless (bolp) (insert "\n"))
          (insert "\n"))

        ;; Insert the forward link - use description only if non-empty
        (if (and link-desc (not (string-empty-p link-desc)))
            (insert (format "[[id:%s][%s]]\n" child-id link-desc))
          (insert (format "[[id:%s]]\n" child-id))))
      (save-buffer)
      ;; Update org-roam database for this file
      (org-roam-db-update-file parent-file))))

(defun autoslip-roam--insert-forward-link-properties (child-node parent-file)
  "Append CHILD-NODE's id to the children property in PARENT-FILE."
  (let ((child-id (org-roam-node-id child-node)))
    (with-current-buffer (find-file-noselect parent-file)
      (save-excursion
        (let* ((existing (autoslip-roam--children-property-ids))
               (merged (if (member child-id existing)
                           existing
                         (append existing (list child-id)))))
          (autoslip-roam--set-children-property-ids merged)))
      (save-buffer)
      (org-roam-db-update-file parent-file))))

(defun autoslip-roam--insert-forward-link (child-node parent-file)
  "Insert a forward link to CHILD-NODE in PARENT-FILE.
Dispatches on `autoslip-roam-link-storage'."
  (pcase autoslip-roam-link-storage
    ('properties (autoslip-roam--insert-forward-link-properties child-node parent-file))
    (_           (autoslip-roam--insert-forward-link-headings child-node parent-file))))

(defun autoslip-roam--insert-crosslink (target-node source-node target-file)
  "Insert a reciprocal cross-link to SOURCE-NODE in TARGET-FILE.
TARGET-NODE is the node receiving the reciprocal link.
SOURCE-NODE is the node that initiated the link."
  (let* ((source-id (org-roam-node-id source-node))
         (source-title (org-roam-node-title source-node)))
    (with-current-buffer (find-file-noselect target-file)
      (save-excursion
        ;; If heading is specified, find or create it
        (if autoslip-roam-crosslink-heading
            (progn
              (goto-char (point-min))
              (unless (re-search-forward
                       (concat "^\\*+ " (regexp-quote autoslip-roam-crosslink-heading))
                       nil t)
                ;; Heading does not exist, create it at end
                (goto-char (point-max))
                (unless (bolp) (insert "\n"))
                (insert "\n* " autoslip-roam-crosslink-heading "\n"))
              (end-of-line)
              (insert "\n"))
          ;; No heading, insert at end of buffer
          (goto-char (point-max))
          (unless (bolp) (insert "\n"))
          (insert "\n"))

        ;; Check if reciprocal link already exists
        (let ((link-pattern (concat "\\[\\[id:" source-id "\\]")))
          (unless (save-excursion
                    (goto-char (point-min))
                    (re-search-forward link-pattern nil t))
            ;; Insert the reciprocal link - use title only if non-empty
            (if (and source-title (not (string-empty-p source-title)))
                (insert (format "[[id:%s][%s]]\n" source-id source-title))
              (insert (format "[[id:%s]]\n" source-id))))))
      (save-buffer)
      ;; Update org-roam database for this file
      (org-roam-db-update-file target-file))))

(defun autoslip-roam--process-new-node ()
  "Process newly created org-roam node for folgezettel backlinks.
This function is called after a new node is created.
Creates bidirectional links:
- A link to the parent under '** Parent Note' in the child
- A link to the child under '** Child Notes' in the parent"
  (when-let* ((current-node (org-roam-node-at-point))
              (title (org-roam-node-title current-node))
              (folgezettel (autoslip-roam--extract-from-title title))
              (parent-addr (autoslip-roam--parse-address folgezettel)))
    ;; Use stored parent node if available and title matches, otherwise find it
    (let ((parent-node
           (if (and autoslip-roam--pending-parent-node
                    autoslip-roam--pending-child-title
                    (string= title autoslip-roam--pending-child-title))
               autoslip-roam--pending-parent-node
             (autoslip-roam--find-parent-node parent-addr))))
      (when parent-node
        ;; Insert backlink in current (child) note under "** Parent Note"
        (autoslip-roam--insert-backlink parent-node)
        (save-buffer)
        ;; Update org-roam database for current (child) file
        (when-let ((current-file (org-roam-node-file current-node)))
          (org-roam-db-update-file current-file))

        ;; Insert forward link in parent note under "** Child Notes"
        (when-let ((parent-file (org-roam-node-file parent-node)))
          (autoslip-roam--insert-forward-link current-node parent-file))

        (message "Created bidirectional links between '%s' and parent '%s'"
                 title (org-roam-node-title parent-node)))

      ;; Clear the pending variables
      (setq autoslip-roam--pending-parent-node nil)
      (setq autoslip-roam--pending-child-title nil))))

(defun autoslip-roam-add-backlink-to-parent ()
  "Manually add a backlink to the parent note based on folgezettel in title.
Also adds a forward link in the parent note.
Useful for existing notes or when automatic insertion fails."
  (interactive)
  ;; Sync database to ensure we have current data
  (autoslip-roam--maybe-sync-db)
  (let ((current-node (org-roam-node-at-point)))
    (if (not current-node)
        (message "No org-roam node found at point")
      (let ((title (org-roam-node-title current-node)))
        (if (not title)
            (message "Current node has no title")
          (let ((folgezettel (autoslip-roam--extract-from-title title)))
            (if (not folgezettel)
                (message "No folgezettel pattern found in title: %s" title)
              (let ((parent-addr (autoslip-roam--parse-address folgezettel)))
                (if (not parent-addr)
                    (message "Could not determine parent address for folgezettel: %s (this may be a root note with no parent)" folgezettel)
                  (let ((parent-node (autoslip-roam--find-parent-node parent-addr)))
                    (if (not parent-node)
                        (message "Could not find parent note with address '%s'. Make sure a note exists with this folgezettel in its title." parent-addr)
                      ;; Insert backlink in current note
                      (autoslip-roam--insert-backlink parent-node)
                      (save-buffer)
                      ;; Update org-roam database for current file
                      (when-let ((current-file (org-roam-node-file current-node)))
                        (org-roam-db-update-file current-file))
                      ;; Insert forward link in parent note (this will update parent's DB entry)
                      (when-let ((parent-file (org-roam-node-file parent-node)))
                        (autoslip-roam--insert-forward-link current-node parent-file))
                      (message "Inserted bidirectional links with parent note: %s"
                               (org-roam-node-title parent-node)))))))))))))

;;; Validation Functions

(defun autoslip-roam--validate-no-multiple-periods (address)
  "Check that ADDRESS contains at most one period (after the root number).
Returns nil if valid, or an error message string if invalid."
  (when (and address (stringp address))
    (let ((period-count (length (seq-filter (lambda (c) (= c ?.)) address))))
      (when (> period-count 1)
        (format "Invalid address '%s': Only one period is allowed after the root number. Found %d periods."
                address period-count)))))

(defun autoslip-roam--validate-no-invalid-characters (address)
  "Check that ADDRESS contains only valid characters
(digits, lowercase letters, single period).
Returns nil if valid, or an error message string if invalid."
  (when (and address (stringp address))
    (let ((invalid-chars '())
          (case-fold-search nil))  ; Ensure case-sensitive matching
      ;; Check for specific problematic characters for filenames
      (when (string-match-p "/" address)
        (push "/" invalid-chars))
      (when (string-match-p "\\\\" address)
        (push "\\" invalid-chars))
      (when (string-match-p "," address)
        (push "," invalid-chars))
      (when (string-match-p "!" address)
        (push "!" invalid-chars))
      (when (string-match-p "<" address)
        (push "<" invalid-chars))
      (when (string-match-p ">" address)
        (push ">" invalid-chars))
      (when (string-match-p ";" address)
        (push ";" invalid-chars))
      (when (string-match-p "&" address)
        (push "&" invalid-chars))
      (when (string-match-p "\\$" address)
        (push "$" invalid-chars))
      (when (string-match-p "\\*" address)
        (push "*" invalid-chars))
      (when (string-match-p "\\?" address)
        (push "?" invalid-chars))
      (when (string-match-p "{" address)
        (push "{" invalid-chars))
      (when (string-match-p "}" address)
        (push "}" invalid-chars))
      (when (string-match-p "`" address)
        (push "`" invalid-chars))
      (when (string-match-p "'" address)
        (push "'" invalid-chars))
      (when (string-match-p "\"" address)
        (push "\"" invalid-chars))
      ;; Check for any other invalid characters (not digit, lowercase letter, or period)
      ;; Use case-sensitive replacement
      (let ((cleaned (replace-regexp-in-string "[0-9a-z.]" "" address)))
        (when (> (length cleaned) 0)
          (dolist (char (string-to-list cleaned))
            (unless (member (char-to-string char) invalid-chars)
              (push (char-to-string char) invalid-chars)))))
      (when invalid-chars
        (format "Invalid address '%s': Contains invalid character(s): %s. Only digits (0-9), lowercase letters (a-z), and a single period are allowed."
                address (string-join (reverse invalid-chars) ", "))))))

(defun autoslip-roam--validate-alternation-pattern (address)
  "Check that ADDRESS follows the alternation pattern (numbers and letters must alternate).
After the initial number and optional .number, the pattern must alternate:
- Letter segments must follow number segments
- Number segments must follow letter segments
Note: Extended alphabet sequences like 'aa', 'ab', 'aaa'
    are valid as single letter segments.
Returns nil if valid, or an error message string if invalid."
  (when (and address (stringp address))
    ;; First, extract the part after the root (e.g., from "1.2abc3d" get "abc3d")
    (when (string-match "^[0-9]+\\(?:\\.[0-9]+\\)?\\(.*\\)$" address)
      (let ((suffix (match-string 1 address)))
        (when (> (length suffix) 0)
          ;; Parse the suffix into segments of contiguous letters or numbers
          (let ((segments '())
                (pos 0)
                (len (length suffix)))
            (while (< pos len)
              (cond
               ;; Letter sequence (including extended like aa, ab, aaa)
               ((string-match "\\`[a-z]+" (substring suffix pos))
                (let ((match (match-string 0 (substring suffix pos))))
                  (push (cons 'letters match) segments)
                  (setq pos (+ pos (length match)))))
               ;; Number sequence
               ((string-match "\\`[0-9]+" (substring suffix pos))
                (let ((match (match-string 0 (substring suffix pos))))
                  (push (cons 'numbers match) segments)
                  (setq pos (+ pos (length match)))))
               ;; Unexpected character (shouldn't happen if other validations pass)
               (t (setq pos len))))

            ;; Check alternation: letter segments and number segments should alternate
            ;; Valid: letters -> numbers -> letters -> numbers ...
            ;; Invalid: letters -> letters or numbers -> numbers
            (setq segments (reverse segments))
            (let ((prev-type nil)
                  (error-msg nil))
              (dolist (seg segments)
                (let ((seg-type (car seg))
                      (seg-value (cdr seg)))
                  (when (and prev-type (eq prev-type seg-type))
                    (setq error-msg
                          (if (eq seg-type 'numbers)
                              (format "Invalid address '%s': Number segment '%s' cannot directly follow another number segment. Use a letter between numeric segments (e.g., '1.2a3' not '1.23' for a child of '1.2')."
                                      address seg-value)
                            ;; This case shouldn't happen with proper parsing since
                            ;; consecutive letters are grouped together
                            (format "Invalid address '%s': Consecutive letter segments detected. This is an internal error."
                                    address))))
                  (setq prev-type seg-type)))
              error-msg)))))))

(defun autoslip-roam--validate-child-for-parent (parent-address child-suffix)
  "Validate that CHILD-SUFFIX is appropriate for PARENT-ADDRESS.
Returns nil if valid, or an error message string if invalid.

Rules:
- If parent ends with a number, child must start with a letter OR be .number
- If parent ends with a letter, child must start with a number"
  (when (and parent-address child-suffix
             (stringp parent-address) (stringp child-suffix)
             (> (length parent-address) 0) (> (length child-suffix) 0))
    (let ((parent-last-char (aref parent-address (1- (length parent-address))))
          (child-first-char (aref child-suffix 0)))
      (cond
       ;; Parent ends with a number
       ((and (>= parent-last-char ?0) (<= parent-last-char ?9))
        (cond
         ;; Child starts with a letter - valid
         ((and (>= child-first-char ?a) (<= child-first-char ?z))
          nil)
         ;; Child starts with a dot (numeric child) - valid
         ((= child-first-char ?.)
          nil)
         ;; Child starts with a number (without dot) - invalid
         ((and (>= child-first-char ?0) (<= child-first-char ?9))
          (format "Invalid child suffix '%s' for parent '%s': Parent ends with a number, so child must start with a letter (e.g., '%sa') or use a dot for numeric children (e.g., '%s.1')."
                  child-suffix parent-address parent-address parent-address))
         (t nil)))
       ;; Parent ends with a letter
       ((and (>= parent-last-char ?a) (<= parent-last-char ?z))
        (cond
         ;; Child starts with a number - valid
         ((and (>= child-first-char ?0) (<= child-first-char ?9))
          nil)
         ;; Child starts with a letter - invalid (can't add letter to letter-ending parent)
         ((and (>= child-first-char ?a) (<= child-first-char ?z))
          (format "Invalid child suffix '%s' for parent '%s': Parent ends with a letter, so child must start with a number (e.g., '%s1'). You cannot add a letter child to a letter-ending parent."
                  child-suffix parent-address parent-address))
         (t nil)))
       (t nil)))))

(defun autoslip-roam-validate-address (address)
  "Validate that ADDRESS follows proper folgezettel format.
Returns t if valid, nil otherwise.
Use `autoslip-roam-validate-address-full' for detailed error messages."
  (and address
       (stringp address)
       (not (autoslip-roam--validate-no-invalid-characters address))
       (not (autoslip-roam--validate-no-multiple-periods address))
       (not (autoslip-roam--validate-alternation-pattern address))
       (string-match-p "^[0-9]+\\(?:\\.[0-9]+\\)?\\(?:[a-z]+[0-9]*\\)*$" address)))

(defun autoslip-roam-validate-address-full (address)
  "Validate ADDRESS and return detailed error information.
Returns nil if valid, or a list of error message strings if invalid."
  (let ((errors '()))
    (unless (and address (stringp address))
      (push "Address must be a non-empty string." errors))
    (when (and address (stringp address))
      ;; Check for invalid characters
      (when-let ((err (autoslip-roam--validate-no-invalid-characters address)))
        (push err errors))
      ;; Check for multiple periods
      (when-let ((err (autoslip-roam--validate-no-multiple-periods address)))
        (push err errors))
      ;; Check alternation pattern
      (when-let ((err (autoslip-roam--validate-alternation-pattern address)))
        (push err errors))
      ;; Check basic structure (must start with a number)
      (unless (string-match-p "^[0-9]" address)
        (push (format "Invalid address '%s': Must start with a number." address) errors)))
    (reverse errors)))

(defun autoslip-roam-validate-new-child (parent-address child-address)
  "Validate that CHILD-ADDRESS is a valid child of PARENT-ADDRESS.
Returns nil if valid, or a list of error message strings if invalid."
  (let ((errors '()))
    ;; First validate both addresses individually
    (let ((parent-errors (autoslip-roam-validate-address-full parent-address))
          (child-errors (autoslip-roam-validate-address-full child-address)))
      (when parent-errors
        (push (format "Parent address errors: %s" (string-join parent-errors "; ")) errors))
      (when child-errors
        (push (format "Child address errors: %s" (string-join child-errors "; ")) errors)))

    ;; Then validate parent-child relationship
    (when (and (null errors)
               parent-address child-address
               (stringp parent-address) (stringp child-address))
      ;; Child must start with parent
      (unless (string-prefix-p parent-address child-address)
        (push (format "Child '%s' must start with parent address '%s'."
                      child-address parent-address) errors))
      ;; Validate the suffix
      (when (string-prefix-p parent-address child-address)
        (let ((suffix (substring child-address (length parent-address))))
          (when (= (length suffix) 0)
            (push "Child address cannot be identical to parent address." errors))
          (when (> (length suffix) 0)
            (when-let ((err (autoslip-roam--validate-child-for-parent
                            parent-address suffix)))
              (push err errors))))))
    (reverse errors)))

(defun autoslip-roam-report-validation-errors (address)
  "Interactively validate ADDRESS and display any errors.
Returns t if valid, nil if invalid."
  (interactive "sEnter folgezettel address to validate: ")
  (let ((errors (autoslip-roam-validate-address-full address)))
    (if errors
        (progn
          (message "Validation FAILED for '%s':\n%s"
                   address
                   (string-join errors "\n"))
          nil)
      (message "Validation PASSED: '%s' is a valid folgezettel address." address)
      t)))

(defun autoslip-roam--next-letter-sequence (current)
  "Return the next letter sequence after CURRENT.
Examples: a -> b, z -> aa, az -> ba, zz -> aaa"
  (let* ((chars (string-to-list current))
         (result (reverse chars))
         (carry t))
    (setq result
          (mapcar (lambda (c)
                    (if carry
                        (if (= c ?z)
                            (progn ?a)
                          (progn
                            (setq carry nil)
                            (1+ c)))
                      c))
                  result))
    (when carry
      (setq result (cons ?a result)))
    (concat (reverse result))))

(defun autoslip-roam-suggest-next-child (parent-address)
  "Suggest the next child address for PARENT-ADDRESS.
Returns a list of valid suggestions based on the parent's type.

Addressing rules:
- If parent is a root (e.g., '7.' or the legacy bare '7'):
  can ONLY add dot-number child (7.1)
- If parent has a dot with a subtopic (e.g., '7.1'):
  can ONLY add letter child (7.1a)
- If parent ends with a letter (e.g., '7.1a'):
  can ONLY add number child (7.1a1)

Returns nil with an error message if parent-address is invalid."
  (let ((errors (autoslip-roam-validate-address-full parent-address)))
    (if errors
        (progn
          (message "Cannot suggest children: %s" (string-join errors "; "))
          nil)
      (let* ((nodes (org-roam-node-list))
             (canonical-parent
              (autoslip-roam--canonicalize-root parent-address))
             (children (seq-filter
                        (lambda (node)
                          (when-let ((title (org-roam-node-title node))
                                     (fz (autoslip-roam--extract-from-title title)))
                            (and (string-prefix-p canonical-parent fz)
                                 (not (string= canonical-parent fz))
                                 (string= canonical-parent
                                         (autoslip-roam--parse-address fz)))))
                        nodes))
             (parent-ends-with-letter
              (and (> (length canonical-parent) 0)
                   (let ((last-char (aref canonical-parent (1- (length canonical-parent)))))
                     (and (>= last-char ?a) (<= last-char ?z)))))
             (parent-is-root (autoslip-roam--root-address-p canonical-parent))
             (parent-has-dot (and (not parent-is-root)
                                  (string-match-p "\\." canonical-parent)))
             (max-num-with-dot 0)
             (max-num-after-letter 0)
             (max-letter nil))

        ;; Analyze existing children
        (dolist (child children)
          (when-let* ((title (org-roam-node-title child))
                      (fz (autoslip-roam--extract-from-title title)))
            (cond
             ;; Numeric child under a canonical or bare root (e.g., "1.2" from "1." or "1")
             ((and parent-is-root
                   (string-match
                    (concat "^"
                            (regexp-quote
                             (if (string-suffix-p "." canonical-parent)
                                 (substring canonical-parent 0 -1)
                               canonical-parent))
                            "[.]\\([0-9]+\\)")
                    fz))
              (let ((num (string-to-number (match-string 1 fz))))
                (setq max-num-with-dot (max max-num-with-dot num))))

             ;; Numeric child after letter parent (e.g., "1a2" from parent "1a")
             ((and parent-ends-with-letter
                   (string-match (concat "^" (regexp-quote canonical-parent)
                                        "\\([0-9]+\\)")
                                fz))
              (let ((num (string-to-number (match-string 1 fz))))
                (setq max-num-after-letter (max max-num-after-letter num))))

             ;; Letter child (e.g., "1.2a" from "1.2")
             ((and (not parent-ends-with-letter)
                   parent-has-dot
                   (string-match (concat "^" (regexp-quote canonical-parent)
                                        "\\([a-z]+\\)")
                                fz))
              (let ((letters (match-string 1 fz)))
                (setq max-letter
                      (if (or (not max-letter)
                              (string< max-letter letters))
                          letters
                        max-letter)))))))

        ;; Generate suggestions based on parent type
        (cond
         ;; Parent ends with letter: can ONLY add number child (e.g., 1.2a -> 1.2a1)
         (parent-ends-with-letter
          (let ((numeric-suggestion
                 (concat canonical-parent (number-to-string (1+ max-num-after-letter)))))
            (list numeric-suggestion)))

         ;; Parent is a root: can ONLY add dot-number child
         ;; Canonical form already ends with ".", so just append the number.
         (parent-is-root
          (let ((numeric-suggestion
                 (concat canonical-parent
                         (unless (string-suffix-p "." canonical-parent) ".")
                         (number-to-string (1+ max-num-with-dot)))))
            (list numeric-suggestion)))

         ;; Parent already has a dot (e.g., 7.1): can ONLY add letter child
         ;; e.g., 7.1 -> 7.1a (NOT 7.1.1 which would have two dots)
         (parent-has-dot
          (let ((alphabetic-suggestion
                 (concat canonical-parent
                         (if max-letter
                             (autoslip-roam--next-letter-sequence max-letter)
                           "a"))))
            (list alphabetic-suggestion)))

         ;; Fallback (shouldn't reach here with valid addresses)
         (t nil))))))


(defun autoslip-roam-insert-next-child ()
  "Interactively create a new child note with suggested folgezettel.
Prompts for numeric or alphabetic suffix, validates the choice,
checks for duplicate indexes, prompts for a title, and creates the note.
Automatically creates bidirectional links between the new child and its parent:
- A link to the parent under '** Parent Note' in the child
- A link to the child under '** Child Notes' in the parent"
  (interactive)
  ;; Sync database to ensure we have current data
  (autoslip-roam--maybe-sync-db)
  (if-let* ((current-node (org-roam-node-at-point))
            (title (org-roam-node-title current-node))
            (current-fz (autoslip-roam--extract-from-title title)))
      (let ((suggestions (autoslip-roam-suggest-next-child current-fz)))
        (if (null suggestions)
            (message "Could not generate suggestions for '%s'.
Check if it's a valid address." current-fz)
          (let* ((choice (completing-read
                          (format "Choose next child address (parent: %s): " current-fz)
                          suggestions
                          nil nil nil nil (car suggestions)))
                 (errors (autoslip-roam-validate-new-child current-fz choice)))
            (cond
             ;; Validation errors
             (errors
              (message "Invalid child address '%s':\n%s" choice (string-join errors "\n"))
              (when (y-or-n-p "Would you like to try again with a valid address? ")
                (autoslip-roam-insert-next-child)))
             ;; Duplicate index
             ((not (autoslip-roam-check-duplicate-index choice))
              (when (y-or-n-p "Would you like to try again with a different address? ")
                (autoslip-roam-insert-next-child)))
             ;; Valid and available - prompt for title and create the note
             (t
              (let* ((note-title (read-string (format "Enter title for %s: " choice)))
                     (full-title (if (string-empty-p note-title)
                                     choice
                                   (concat choice " " note-title))))
                ;; Store parent node information for the capture hook
                (setq autoslip-roam--pending-parent-node current-node)
                (setq autoslip-roam--pending-child-title full-title)
                (org-roam-capture- :node (org-roam-node-create :title full-title))))))))
    (message "Current note does not have a valid folgezettel address in title: %s"
             (if (and (org-roam-node-at-point)
                      (org-roam-node-title (org-roam-node-at-point)))
                 (org-roam-node-title (org-roam-node-at-point))
               "(no node at point)"))))

(defun autoslip-roam--handle-crosslink-insertion (link &optional description)
  "Handle bidirectional link creation after inserting LINK with DESCRIPTION.
This function is called via advice after `org-insert-link'."
  (when (and autoslip-roam-auto-crosslink
             (org-roam-node-at-point)
             link
             (string-match "^id:\\(.+\\)$" link))
    (let* ((target-id (match-string 1 link))
           (target-node (org-roam-node-from-id target-id))
           (source-node (org-roam-node-at-point)))
      (when (and target-node source-node
                 (not (string= (org-roam-node-id source-node)
                              (org-roam-node-id target-node))))
        (let ((target-file (org-roam-node-file target-node)))
          (when target-file
            (autoslip-roam--insert-crosslink target-node source-node target-file)
            (message "Created reciprocal link in: %s"
                     (org-roam-node-title target-node))))))))

(defun autoslip-roam--org-insert-link-advice (orig-fun &rest args)
  "Advice function to wrap `org-insert-link' for bidirectional linking.
ORIG-FUN is the original `org-insert-link' function.
ARGS are the arguments passed to `org-insert-link'."
  (let ((result (apply orig-fun args)))
    ;; After inserting link, check if it is an org-roam ID link
    (save-excursion
      (when (and (org-in-regexp org-link-bracket-re 1)
                 (match-string 1))
        (let ((link-data (match-string 1)))
          (when (string-match "^id:\\(.+\\)$" link-data)
            (autoslip-roam--handle-crosslink-insertion
             link-data
             (match-string 2))))))
    result))

;;; ============================================================================
;;; Navigation: goto-parent and list-children
;;; ============================================================================

(defun autoslip-roam--children-nodes-of (parent-address)
  "Return the list of org-roam nodes whose direct parent is PARENT-ADDRESS.
PARENT-ADDRESS may be in canonical form (\"1.\") or in the legacy bare
form (\"1\"); both resolve to the same set of children."
  (when parent-address
    (let* ((canonical (autoslip-roam--canonicalize-root parent-address))
           (nodes (org-roam-node-list)))
      (seq-filter
       (lambda (node)
         (when-let* ((title (org-roam-node-title node))
                     (fz (autoslip-roam--extract-from-title title))
                     (p  (autoslip-roam--parse-address fz)))
           (string= p canonical)))
       nodes))))

(defun autoslip-roam--address-depth (address)
  "Return the hierarchical depth of ADDRESS.
A root (\"1.\" or the legacy bare \"1\") has depth 0; every extra segment adds one."
  (let ((depth 0)
        (cur address))
    (while (setq cur (autoslip-roam--parse-address cur))
      (setq depth (1+ depth)))
    depth))

(defun autoslip-roam--address-tokens (address)
  "Split ADDRESS into a list of comparable tokens.
Each token is either a number (an integer) or a letter sequence (a string).
A dot-number segment is represented as the same integer token as a bare
number; the shape of the address is already known from context.
Trailing periods on roots are absorbed because dots never appear in tokens.

Examples:
  \"1.\"        -> (1)
  \"1\"         -> (1)
  \"1.13\"      -> (1 13)
  \"1.13a\"     -> (1 13 \"a\")
  \"1.2a3b\"    -> (1 2 \"a\" 3 \"b\")"
  (let ((tokens '())
        (pos 0)
        (len (length address)))
    (while (< pos len)
      (let ((c (aref address pos)))
        (cond
         ;; Skip dots
         ((= c ?.) (setq pos (1+ pos)))
         ;; Digits
         ((and (>= c ?0) (<= c ?9))
          (let ((start pos))
            (while (and (< pos len)
                        (let ((d (aref address pos)))
                          (and (>= d ?0) (<= d ?9))))
              (setq pos (1+ pos)))
            (push (string-to-number (substring address start pos)) tokens)))
         ;; Letters
         ((and (>= c ?a) (<= c ?z))
          (let ((start pos))
            (while (and (< pos len)
                        (let ((d (aref address pos)))
                          (and (>= d ?a) (<= d ?z))))
              (setq pos (1+ pos)))
            (push (substring address start pos) tokens)))
         (t (setq pos (1+ pos))))))
    (nreverse tokens)))

(defun autoslip-roam--compare-addresses (a b)
  "Return non-nil if address A sorts before address B in hierarchical order."
  (let ((at (autoslip-roam--address-tokens a))
        (bt (autoslip-roam--address-tokens b))
        (result nil)
        (decided nil))
    (while (and (not decided) at bt)
      (let ((ax (car at))
            (bx (car bt)))
        (cond
         ;; Both numbers
         ((and (numberp ax) (numberp bx))
          (cond ((< ax bx) (setq decided t result t))
                ((> ax bx) (setq decided t result nil))
                (t (setq at (cdr at) bt (cdr bt)))))
         ;; Both strings
         ((and (stringp ax) (stringp bx))
          (cond ((string< ax bx) (setq decided t result t))
                ((string< bx ax) (setq decided t result nil))
                (t (setq at (cdr at) bt (cdr bt)))))
         ;; Mixed types: numbers come before strings at the same depth
         ((numberp ax) (setq decided t result t))
         (t (setq decided t result nil)))))
    (if decided
        result
      (< (length at) (length bt)))))

(defun autoslip-roam-goto-parent ()
  "Jump to the parent note of the current folgezettel-indexed note."
  (interactive)
  (autoslip-roam--maybe-sync-db)
  (let* ((node (org-roam-node-at-point))
         (title (and node (org-roam-node-title node)))
         (fz (and title (autoslip-roam--extract-from-title title)))
         (parent-addr (and fz (autoslip-roam--parse-address fz))))
    (cond
     ((not node)
      (user-error "No org-roam node at point"))
     ((not fz)
      (user-error "Current note has no folgezettel address in its title"))
     ((not parent-addr)
      (user-error "Note %s is a root note and has no parent" fz))
     (t
      (let ((parent (autoslip-roam--find-parent-node parent-addr)))
        (if parent
            (org-roam-node-visit parent)
          (user-error "No note found for parent address %s" parent-addr)))))))

(defun autoslip-roam-list-children ()
  "Prompt for one of the current note's direct children and jump to it."
  (interactive)
  (autoslip-roam--maybe-sync-db)
  (let* ((node (org-roam-node-at-point))
         (title (and node (org-roam-node-title node)))
         (fz (and title (autoslip-roam--extract-from-title title))))
    (cond
     ((not fz)
      (user-error "Current note has no folgezettel address in its title"))
     (t
      (let* ((children (autoslip-roam--children-nodes-of fz))
             (sorted (sort children
                           (lambda (a b)
                             (autoslip-roam--compare-addresses
                              (autoslip-roam--extract-from-title
                               (org-roam-node-title a))
                              (autoslip-roam--extract-from-title
                               (org-roam-node-title b)))))))
        (if (null sorted)
            (message "%s has no children" fz)
          (let* ((alist (mapcar (lambda (c)
                                  (cons (org-roam-node-title c) c))
                                sorted))
                 (choice (completing-read
                          (format "Children of %s: " fz)
                          (mapcar #'car alist) nil t)))
            (org-roam-node-visit (cdr (assoc choice alist))))))))))

;;; ============================================================================
;;; Tree visualization buffer
;;; ============================================================================

(defvar autoslip-roam-tree-buffer-name "*Autoslip Tree*"
  "Buffer name used by `autoslip-roam-show-tree'.")

(defvar autoslip-roam-tree-mode-map
  (let ((m (make-sparse-keymap)))
    (define-key m (kbd "RET") #'autoslip-roam-tree-visit)
    (define-key m (kbd "q")   #'quit-window)
    (define-key m (kbd "g")   #'autoslip-roam-show-tree)
    (define-key m (kbd "n")   #'next-line)
    (define-key m (kbd "p")   #'previous-line)
    m)
  "Keymap for `autoslip-roam-tree-mode'.")

(define-derived-mode autoslip-roam-tree-mode special-mode
  "Autoslip-Tree"
  "Major mode for the folgezettel tree buffer.
\\{autoslip-roam-tree-mode-map}")

(defun autoslip-roam-tree-visit ()
  "Visit the org-roam node whose tree line is at point."
  (interactive)
  (let ((id (get-text-property (line-beginning-position)
                               'folgezettel-node-id)))
    (if (not id)
        (message "No node on this line")
      (let ((node (org-roam-node-from-id id)))
        (if node
            (org-roam-node-visit node)
          (message "Node %s no longer exists; press g to refresh" id))))))

(defun autoslip-roam--tree-collect ()
  "Collect (ADDRESS . NODE) pairs for every node carrying a folgezettel."
  (let (pairs)
    (dolist (node (org-roam-node-list))
      (when-let* ((title (org-roam-node-title node))
                  (fz (autoslip-roam--extract-from-title title)))
        (push (cons fz node) pairs)))
    pairs))

;;;###autoload
(defun autoslip-roam-show-tree ()
  "Display a hierarchical tree of all folgezettel-indexed org-roam notes.
Each line is a button; press RET (or click) to visit the note.
Press g to refresh, q to close."
  (interactive)
  (autoslip-roam--maybe-sync-db)
  (let* ((pairs (autoslip-roam--tree-collect))
         (sorted (sort pairs
                       (lambda (a b)
                         (autoslip-roam--compare-addresses
                          (car a) (car b)))))
         (buffer (get-buffer-create autoslip-roam-tree-buffer-name)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (autoslip-roam-tree-mode)
        (insert "Autoslip Tree\n")
        (insert (make-string 60 ?=) "\n")
        (insert "RET: visit node   g: refresh   q: quit   n/p: move\n\n")
        (if (null sorted)
            (insert "No folgezettel-indexed notes found.\n")
          (dolist (pair sorted)
            (let* ((addr (car pair))
                   (node (cdr pair))
                   (title (org-roam-node-title node))
                   (depth (autoslip-roam--address-depth addr))
                   (line-start (point)))
              (insert (make-string (* 2 depth) ?\s))
              (insert-text-button
               title
               'follow-link t
               'action (lambda (_)
                         (let ((n (org-roam-node-from-id
                                   (org-roam-node-id node))))
                           (when n (org-roam-node-visit n)))))
              (insert "\n")
              (put-text-property line-start (point)
                                 'folgezettel-node-id
                                 (org-roam-node-id node))))))
      (goto-char (point-min)))
    (switch-to-buffer-other-window buffer)))

;;; ============================================================================
;;; Chain of thought (ancestor walk) and cross-linked chains
;;; ============================================================================

(defvar autoslip-roam-chain-buffer-name "*Autoslip Chain of Thought*"
  "Buffer name used by `autoslip-roam-show-chain-of-thought'.")

(defvar autoslip-roam-crosslinked-chains-buffer-name
  "*Autoslip Cross-linked Chains*"
  "Buffer name used by `autoslip-roam-show-crosslinked-chains'.")

(defvar-local autoslip-roam--chain-data nil
  "Buffer-local cache of the chain currently rendered in this buffer.
Value is a list of (ADDRESS TITLE ID) triples in root-to-leaf order.
ID may be nil for ancestors that have no note in the vault.")

(defvar-local autoslip-roam--chain-source-buffer nil
  "The note buffer that requested the current chain-of-thought view.")

(defvar-local autoslip-roam--chain-crosslinks nil
  "Buffer-local cache of cross-linked chains.
Value is a list of chains, each a list of (ADDRESS TITLE ID) triples
in root-to-leaf order.  Used by the cross-linked chains buffer.")

(defun autoslip-roam--ancestor-addresses (address)
  "Return the chain of folgezettel addresses from root to ADDRESS (inclusive).
For example, (\"1.2a3\") expands to (\"1.\" \"1.2\" \"1.2a\" \"1.2a3\").
The root is reported in canonical form with a trailing period.
Returns nil when ADDRESS itself is nil or empty."
  (when (and address (stringp address) (not (string-empty-p address)))
    (let ((chain (list address))
          (cur address)
          (parent nil))
      (while (setq parent (autoslip-roam--parse-address cur))
        (push parent chain)
        (setq cur parent))
      chain)))

(defun autoslip-roam--chain-triples (address)
  "Return (ADDR TITLE ID) triples from root to ADDRESS.
Each entry in the returned list corresponds to one step of the chain.
TITLE and ID are taken from the org-roam node for that address if a
note exists; otherwise TITLE is the address itself and ID is nil."
  (mapcar (lambda (addr)
            (let ((node (autoslip-roam--find-parent-node addr)))
              (if node
                  (list addr
                        (or (org-roam-node-title node) addr)
                        (org-roam-node-id node))
                (list addr addr nil))))
          (autoslip-roam--ancestor-addresses address)))

(defun autoslip-roam--chain-as-org-list (chain &optional heading)
  "Render CHAIN (root-to-leaf list of (ADDR TITLE ID)) as 'org-mode' text.
When HEADING is non-nil, prepend a second-level org heading line."
  (with-temp-buffer
    (when (and heading (not (string-empty-p heading)))
      (insert "** " heading "\n"))
    (let ((depth 0))
      (dolist (entry chain)
        (let ((title (nth 1 entry))
              (id    (nth 2 entry)))
          (insert (make-string (* 2 depth) ?\s) "- ")
          (if id
              (insert (format "[[id:%s][%s]]\n" id title))
            (insert (format "%s (no note)\n" title)))
          (setq depth (1+ depth)))))
    (buffer-string)))

(defvar autoslip-roam-chain-mode-map
  (let ((m (make-sparse-keymap)))
    (define-key m (kbd "RET") #'autoslip-roam-chain-visit)
    (define-key m (kbd "i")   #'autoslip-roam-chain-insert-into-source)
    (define-key m (kbd "q")   #'quit-window)
    (define-key m (kbd "g")   #'autoslip-roam-chain-refresh)
    (define-key m (kbd "n")   #'next-line)
    (define-key m (kbd "p")   #'previous-line)
    m)
  "Keymap for `autoslip-roam-chain-mode'.")

(define-derived-mode autoslip-roam-chain-mode special-mode
  "Autoslip-Chain"
  "Major mode for the chain-of-thought buffer.
\\{autoslip-roam-chain-mode-map}")

(defun autoslip-roam-chain-visit ()
  "Visit the org-roam node whose chain line is at point."
  (interactive)
  (let ((id (get-text-property (line-beginning-position)
                               'folgezettel-node-id)))
    (if (not id)
        (message "No note on this line")
      (let ((node (org-roam-node-from-id id)))
        (if node
            (org-roam-node-visit node)
          (message "Node %s no longer exists" id))))))

(defun autoslip-roam-chain-refresh ()
  "Refresh the current chain-of-thought buffer from its source note."
  (interactive)
  (let ((source autoslip-roam--chain-source-buffer))
    (if (not (buffer-live-p source))
        (message "Source buffer is no longer available")
      (with-current-buffer source
        (if autoslip-roam--chain-crosslinks
            (autoslip-roam-show-crosslinked-chains)
          (autoslip-roam-show-chain-of-thought))))))

(defun autoslip-roam-chain-insert-into-source ()
  "Insert the chain rendered in this buffer into the source note."
  (interactive)
  (cond
   ((not (buffer-live-p autoslip-roam--chain-source-buffer))
    (user-error "Source buffer is no longer available"))
   (autoslip-roam--chain-crosslinks
    (let ((chains autoslip-roam--chain-crosslinks)
          (source autoslip-roam--chain-source-buffer))
      (with-current-buffer source
        (autoslip-roam--insert-crosslinked-chains-at-point chains)
        (save-buffer))
      (message "Inserted %d cross-linked chain(s) into %s"
               (length chains) (buffer-name source))))
   (autoslip-roam--chain-data
    (let ((chain autoslip-roam--chain-data)
          (source autoslip-roam--chain-source-buffer))
      (with-current-buffer source
        (autoslip-roam--insert-chain-at-point chain)
        (save-buffer))
      (message "Inserted chain-of-thought into %s" (buffer-name source))))
   (t (user-error "No chain data in this buffer"))))

(defun autoslip-roam--insert-chain-at-point (chain)
  "Insert CHAIN (list of (ADDR TITLE ID)) as an org outline at point.
Uses `autoslip-roam-chain-heading' when non-nil."
  (let ((text (autoslip-roam--chain-as-org-list
               chain autoslip-roam-chain-heading)))
    (unless (bolp) (insert "\n"))
    (insert text)))

(defun autoslip-roam--insert-crosslinked-chains-at-point (chains)
  "Insert each chain in CHAINS as a successive org outline at point."
  (unless (bolp) (insert "\n"))
  (when autoslip-roam-chain-crosslink-heading
    (insert "** " autoslip-roam-chain-crosslink-heading "\n"))
  (dolist (chain chains)
    (let ((depth 0))
      (dolist (entry chain)
        (let ((title (nth 1 entry))
              (id    (nth 2 entry)))
          (insert (make-string (* 2 depth) ?\s) "- ")
          (if id
              (insert (format "[[id:%s][%s]]\n" id title))
            (insert (format "%s (no note)\n" title)))
          (setq depth (1+ depth)))))
    (insert "\n")))

(defun autoslip-roam--render-chain-buffer (buffer header chain source-buffer)
  "Fill BUFFER with HEADER and the CHAIN.
Remember SOURCE-BUFFER so the \"i\" key can insert back into it."
  (with-current-buffer buffer
    (let ((inhibit-read-only t))
      (erase-buffer)
      (autoslip-roam-chain-mode)
      (setq autoslip-roam--chain-source-buffer source-buffer)
      (setq autoslip-roam--chain-data chain)
      (setq autoslip-roam--chain-crosslinks nil)
      (insert header)
      (insert (make-string 60 ?=) "\n")
      (insert "RET: visit   i: insert into source   g: refresh   q: quit\n\n")
      (if (null chain)
          (insert "No ancestors.\n")
        (let ((depth 0))
          (dolist (entry chain)
            (let* ((addr  (nth 0 entry))
                   (title (nth 1 entry))
                   (id    (nth 2 entry))
                   (line-start (point)))
              (insert (make-string (* 2 depth) ?\s))
              (if id
                  (insert-text-button
                   (format "%s %s" addr title)
                   'follow-link t
                   'action (lambda (_)
                             (let ((n (org-roam-node-from-id id)))
                               (when n (org-roam-node-visit n)))))
                (insert (format "%s  (no note in vault)" addr)))
              (insert "\n")
              (when id
                (put-text-property line-start (point)
                                   'folgezettel-node-id id))
              (setq depth (1+ depth))))))
      (goto-char (point-min)))))

;;;###autoload
(defun autoslip-roam-show-chain-of-thought ()
  "Show the folgezettel chain of thought for the current note.
The chain walks from the current note up through every ancestor to the
root of its folgezettel tree, showing only the connecting notes (not
the whole subtree).  Press \"i\" in the resulting buffer to insert the
chain into the current note."
  (interactive)
  (autoslip-roam--maybe-sync-db)
  (let* ((source (current-buffer))
         (node   (org-roam-node-at-point))
         (title  (and node (org-roam-node-title node)))
         (fz     (and title (autoslip-roam--extract-from-title title))))
    (cond
     ((not node) (user-error "No org-roam node at point"))
     ((not fz)
      (user-error "Current note has no folgezettel address in its title"))
     (t
      (let* ((chain (autoslip-roam--chain-triples fz))
             (buffer (get-buffer-create autoslip-roam-chain-buffer-name))
             (header (format "Chain of Thought: %s %s\n"
                             fz (or title ""))))
        (autoslip-roam--render-chain-buffer
         buffer header chain source)
        (switch-to-buffer-other-window buffer))))))

;;;###autoload
(defun autoslip-roam-insert-chain-of-thought ()
  "Insert the current note's chain of thought at point as an org outline.
Walks from the current note to the root of its folgezettel tree and
inserts one bullet per ancestor, each linking to the corresponding
org-roam node.  Honors `autoslip-roam-chain-heading'."
  (interactive)
  (autoslip-roam--maybe-sync-db)
  (let* ((node  (org-roam-node-at-point))
         (title (and node (org-roam-node-title node)))
         (fz    (and title (autoslip-roam--extract-from-title title))))
    (cond
     ((not node) (user-error "No org-roam node at point"))
     ((not fz)
      (user-error "Current note has no folgezettel address in its title"))
     (t
      (let ((chain (autoslip-roam--chain-triples fz)))
        (autoslip-roam--insert-chain-at-point chain)
        (message "Inserted chain of thought (%d note%s)"
                 (length chain) (if (= 1 (length chain)) "" "s")))))))

(defun autoslip-roam--crosslink-ids-in-buffer ()
  "Return a list of org-roam node IDs linked under the Cross References heading.
Parses the current buffer for links of the form [[id:UUID][...]] that
appear between `autoslip-roam-crosslink-heading' and the next
heading at the same or shallower level.  Returns them in document order."
  (let (ids)
    (when autoslip-roam-crosslink-heading
      (save-excursion
        (goto-char (point-min))
        (when (re-search-forward
               (concat "^\\(\\*+\\) "
                       (regexp-quote autoslip-roam-crosslink-heading)
                       "[ \t]*$")
               nil t)
          (let* ((heading-level (length (match-string 1)))
                 (section-start (line-end-position))
                 (section-end
                  (save-excursion
                    (forward-line 1)
                    (if (re-search-forward
                         (format "^\\*\\{1,%d\\} " heading-level)
                         nil t)
                        (match-beginning 0)
                      (point-max)))))
            (save-restriction
              (narrow-to-region section-start section-end)
              (goto-char (point-min))
              (while (re-search-forward
                      "\\[\\[id:\\([^]]+\\)\\]" nil t)
                (push (match-string-no-properties 1) ids)))))))
    ;; IDS is in reverse document order; reverse once to restore order,
    ;; then drop duplicates keeping the first occurrence.
    (delete-dups (nreverse ids))))

(defun autoslip-roam--node-chain-triples (node)
  "Return the chain triples for NODE, or nil if NODE has no folgezettel."
  (when node
    (let* ((title (org-roam-node-title node))
           (fz    (and title (autoslip-roam--extract-from-title title))))
      (when fz
        (autoslip-roam--chain-triples fz)))))

(defun autoslip-roam--render-crosslinked-chains-buffer
    (buffer header chains source-buffer)
  "Fill BUFFER with HEADER and each chain in CHAINS.
Remember SOURCE-BUFFER so the \"i\" key can insert back into it."
  (with-current-buffer buffer
    (let ((inhibit-read-only t))
      (erase-buffer)
      (autoslip-roam-chain-mode)
      (setq autoslip-roam--chain-source-buffer source-buffer)
      (setq autoslip-roam--chain-crosslinks chains)
      (setq autoslip-roam--chain-data nil)
      (insert header)
      (insert (make-string 60 ?=) "\n")
      (insert "RET: visit   i: insert all into source   g: refresh   q: quit\n\n")
      (if (null chains)
          (insert "No cross-linked notes with folgezettel addresses found.\n")
        (dolist (chain chains)
          (let* ((last  (car (last chain)))
                 (addr  (nth 0 last))
                 (title (nth 1 last)))
            (insert (format "-- %s %s --\n" addr (or title ""))))
          (let ((depth 0))
            (dolist (entry chain)
              (let* ((addr  (nth 0 entry))
                     (title (nth 1 entry))
                     (id    (nth 2 entry))
                     (line-start (point)))
                (insert (make-string (* 2 depth) ?\s))
                (if id
                    (insert-text-button
                     (format "%s %s" addr title)
                     'follow-link t
                     'action (lambda (_)
                               (let ((n (org-roam-node-from-id id)))
                                 (when n (org-roam-node-visit n)))))
                  (insert (format "%s  (no note in vault)" addr)))
                (insert "\n")
                (when id
                  (put-text-property line-start (point)
                                     'folgezettel-node-id id))
                (setq depth (1+ depth)))))
          (insert "\n")))
      (goto-char (point-min)))))

;;;###autoload
(defun autoslip-roam-show-crosslinked-chains ()
  "Show chains of thought for every cross-link in the current note.
Finds the IDs listed under `autoslip-roam-crosslink-heading' in
the current note and, for each one, walks that note's folgezettel
chain from root to leaf.  The result groups one chain per cross-linked
note in a dedicated buffer.  Press \"i\" to insert all chains into the
current note."
  (interactive)
  (autoslip-roam--maybe-sync-db)
  (let* ((source (current-buffer))
         (ids    (autoslip-roam--crosslink-ids-in-buffer))
         (chains (delq nil
                       (mapcar
                        (lambda (id)
                          (autoslip-roam--node-chain-triples
                           (org-roam-node-from-id id)))
                        ids)))
         (node   (org-roam-node-at-point))
         (title  (and node (org-roam-node-title node)))
         (buffer (get-buffer-create
                  autoslip-roam-crosslinked-chains-buffer-name))
         (header (format "Cross-linked Chains of Thought from: %s\n"
                         (or title (buffer-name source)))))
    (autoslip-roam--render-crosslinked-chains-buffer
     buffer header chains source)
    (switch-to-buffer-other-window buffer)))

;;; ============================================================================
;;; Reparent commands
;;; ============================================================================

(defun autoslip-roam--replace-title-keyword (new-title)
  "Replace the #+TITLE keyword in the current buffer with NEW-TITLE.
Returns non-nil if a title was found and replaced."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^#\\+[Tt][Ii][Tt][Ll][Ee]:[ \t]*.*$" nil t)
      (replace-match (format "#+title: %s" new-title) t t)
      t)))

(defun autoslip-roam--remove-backlink-heading ()
  "Remove the Parent Note heading (and the link below it) from current buffer."
  (when autoslip-roam-backlink-heading
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward
             (concat "^\\(\\*+\\) "
                     (regexp-quote autoslip-roam-backlink-heading)
                     "[ \t]*$")
             nil t)
        (let* ((heading-start (match-beginning 0))
               (heading-level (length (match-string 1)))
               (section-end
                (save-excursion
                  (forward-line 1)
                  (if (re-search-forward
                       (format "^\\*\\{1,%d\\} " heading-level)
                       nil t)
                      (match-beginning 0)
                    (point-max)))))
          (delete-region heading-start section-end))))))

(defun autoslip-roam--remove-forward-link-line (child-id)
  "In the current buffer, remove any Child Notes line linking to CHILD-ID."
  (save-excursion
    (goto-char (point-min))
    (let ((pattern (format "^\\s-*\\[\\[id:%s\\].*\n"
                           (regexp-quote child-id))))
      (while (re-search-forward pattern nil t)
        (replace-match "")))))

(defun autoslip-roam--compute-renamed-file (file old-addr new-addr)
  "Return a renamed FILE with OLD-ADDR replaced by NEW-ADDR in its basename.
Tries the literal form first, then the common org-roam slug variants
where \".\" is rendered as \"_\" or \"-\".  Returns nil if no form of
OLD-ADDR is present, or if the rename would not change the basename."
  (when (and file (stringp file) old-addr new-addr
             (not (string-empty-p old-addr)))
    (let* ((dir (file-name-directory file))
           (base (file-name-nondirectory file))
           (result nil))
      (catch 'done
        (dolist (sep '("." "_" "-"))
          (let* ((cand-old (replace-regexp-in-string "\\." sep old-addr t t))
                 (cand-new (replace-regexp-in-string "\\." sep new-addr t t))
                 (pattern (concat "\\(^\\|[^0-9a-z]\\)"
                                  (regexp-quote cand-old)
                                  "\\([^0-9a-z]\\|$\\)")))
            (when (string-match pattern base)
              (setq result
                    (expand-file-name
                     (replace-match
                      (concat (match-string 1 base) cand-new (match-string 2 base))
                      t t base)
                     dir))
              (throw 'done nil)))))
      (when (and result (not (string= result (expand-file-name base dir))))
        result))))

(defun autoslip-roam--rename-visited-file-to (new-file)
  "Rename the current visited file on disk to NEW-FILE and update the buffer."
  (let ((old-file (buffer-file-name)))
    (when (and old-file new-file
               (not (string= old-file new-file)))
      (when (file-exists-p new-file)
        (user-error "Cannot rename %s: target %s already exists"
                    old-file new-file))
      (rename-file old-file new-file t)
      (set-visited-file-name new-file nil t)
      (set-buffer-modified-p nil))))

(defun autoslip-roam--apply-reparent-to-node (node old-addr new-addr
                                                          &optional update-parent-links)
  "Rewrite NODE from OLD-ADDR to NEW-ADDR.
When UPDATE-PARENT-LINKS is non-nil, also refresh the Parent Note entry
so it points at the new parent node (if any).  Returns the new file path."
  (let* ((file (org-roam-node-file node))
         (old-title (org-roam-node-title node))
         (new-title (if (and old-title
                             (string-prefix-p old-addr old-title))
                        (concat new-addr (substring old-title (length old-addr)))
                      old-title))
         (new-file (and autoslip-roam-rename-files-on-reparent
                        (autoslip-roam--compute-renamed-file
                         file old-addr new-addr))))
    (with-current-buffer (find-file-noselect file)
      (autoslip-roam--replace-title-keyword new-title)
      (when update-parent-links
        (pcase autoslip-roam-link-storage
          ('properties
           (autoslip-roam--delete-top-property
            autoslip-roam-parent-property))
          (_ (autoslip-roam--remove-backlink-heading)))
        (let* ((new-parent-addr
                (autoslip-roam--parse-address new-addr))
               (new-parent (and new-parent-addr
                                (autoslip-roam--find-parent-node
                                 new-parent-addr))))
          (when new-parent
            (autoslip-roam--insert-backlink new-parent))))
      (when new-file
        (autoslip-roam--rename-visited-file-to new-file))
      (save-buffer)
      (org-roam-db-update-file (buffer-file-name)))
    (or new-file file)))

(defun autoslip-roam--descendants-of (addr)
  "Return the list of (FZ . NODE) pairs that are descendants of ADDR.
The head note itself is not included.  Results are sorted so that
shallower nodes come before their own descendants."
  (let ((pairs '()))
    (dolist (node (org-roam-node-list))
      (when-let* ((title (org-roam-node-title node))
                  (fz (autoslip-roam--extract-from-title title)))
        (when (and (string-prefix-p addr fz)
                   (not (string= fz addr)))
          (push (cons fz node) pairs))))
    (sort pairs
          (lambda (a b)
            (autoslip-roam--compare-addresses (car a) (car b))))))

(defun autoslip-roam-reparent (new-address)
  "Renumber the current note's folgezettel to NEW-ADDRESS.
Updates the #+title, the Parent Note entry, the old parent's Child Notes
entry, the new parent's Child Notes, and renames the file on disk
when `autoslip-roam-rename-files-on-reparent' is non-nil.
Does not touch descendants; use `autoslip-roam-reparent-subtree'
for that."
  (interactive (list (read-string "New folgezettel address: ")))
  (autoslip-roam--maybe-sync-db)
  (let* ((node (org-roam-node-at-point))
         (title (and node (org-roam-node-title node)))
         (old-addr (and title (autoslip-roam--extract-from-title title))))
    (cond
     ((not node) (user-error "No org-roam node at point"))
     ((not old-addr)
      (user-error "Current note has no folgezettel address in its title"))
     (t
      (let ((errors (autoslip-roam-validate-address-full new-address)))
        (when errors
          (user-error "Invalid new address: %s" (string-join errors "; "))))
      (when (string= old-addr new-address)
        (user-error "New address is identical to the current one"))
      (unless (autoslip-roam-check-duplicate-index new-address)
        (user-error "Address %s is already in use" new-address))
      ;; Remove our forward link from the OLD parent (if any)
      (let* ((old-parent-addr (autoslip-roam--parse-address old-addr))
             (old-parent (and old-parent-addr
                              (autoslip-roam--find-parent-node
                               old-parent-addr)))
             (child-id (org-roam-node-id node)))
        (when old-parent
          (let ((old-parent-file (org-roam-node-file old-parent)))
            (when old-parent-file
              (with-current-buffer (find-file-noselect old-parent-file)
                (pcase autoslip-roam-link-storage
                  ('properties
                   (autoslip-roam--set-children-property-ids
                    (remove child-id
                            (autoslip-roam--children-property-ids))))
                  (_ (autoslip-roam--remove-forward-link-line child-id)))
                (save-buffer)
                (org-roam-db-update-file old-parent-file))))))
      ;; Rewrite THIS note
      (autoslip-roam--apply-reparent-to-node
       node old-addr new-address t)
      ;; Add forward link in NEW parent (if any)
      (let* ((new-parent-addr (autoslip-roam--parse-address new-address))
             (new-parent (and new-parent-addr
                              (autoslip-roam--find-parent-node
                               new-parent-addr))))
        (when new-parent
          (autoslip-roam--insert-forward-link
           node (org-roam-node-file new-parent))))
      (message "Reparented %s -> %s" old-addr new-address)))))

(defun autoslip-roam-reparent-subtree (new-address)
  "Renumber the current note AND all its descendants.
Every descendant's folgezettel has OLD prefix replaced by NEW-ADDRESS.
Titles, filenames, and (if using heading storage) visible parent-note
links remain pointing at the same node IDs; only titles and filenames
change for the descendants."
  (interactive (list (read-string "New folgezettel address for subtree root: ")))
  (autoslip-roam--maybe-sync-db)
  (let* ((node (org-roam-node-at-point))
         (title (and node (org-roam-node-title node)))
         (old-addr (and title (autoslip-roam--extract-from-title title))))
    (unless node (user-error "No org-roam node at point"))
    (unless old-addr
      (user-error "Current note has no folgezettel address in its title"))
    (let ((errors (autoslip-roam-validate-address-full new-address)))
      (when errors
        (user-error "Invalid new address: %s" (string-join errors "; "))))
    (when (string= old-addr new-address)
      (user-error "New address is identical to the current one"))
    (let ((descendants (autoslip-roam--descendants-of old-addr)))
      ;; Check for collisions: any descendant's renamed address must not
      ;; clash with an existing non-descendant node's address.
      (dolist (pair descendants)
        (let* ((old-fz (car pair))
               (suffix (substring old-fz (length old-addr)))
               (new-fz (concat new-address suffix))
               (clash (autoslip-roam--index-exists-p new-fz)))
          (when (and clash
                     (not (member (org-roam-node-id clash)
                                  (mapcar (lambda (p)
                                            (org-roam-node-id (cdr p)))
                                          descendants)))
                     (not (string= (org-roam-node-id clash)
                                   (org-roam-node-id node))))
            (user-error "Cannot reparent subtree: %s would collide with an existing note"
                        new-fz))))
      ;; Reparent the head first (this also swaps its parent pointer)
      (autoslip-roam-reparent new-address)
      ;; Then each descendant (top-down order is already the sort order)
      (dolist (pair descendants)
        (let* ((d-old (car pair))
               (d-node (cdr pair))
               (suffix (substring d-old (length old-addr)))
               (d-new (concat new-address suffix)))
          (autoslip-roam--apply-reparent-to-node
           d-node d-old d-new nil)))
      (message "Reparented subtree %s -> %s (%d descendants)"
               old-addr new-address (length descendants)))))

;;;###autoload
(define-minor-mode autoslip-roam-mode
  "Minor mode for automatic folgezettel backlink generation in org-roam."
  :global t
  :group 'autoslip-roam
  :lighter " FZ"
  (if autoslip-roam-mode
      (progn
        (add-hook 'org-roam-capture-new-node-hook
                  #'autoslip-roam--process-new-node)
        (advice-add 'org-insert-link :around
                    #'autoslip-roam--org-insert-link-advice))
    (remove-hook 'org-roam-capture-new-node-hook
                 #'autoslip-roam--process-new-node)
    (advice-remove 'org-insert-link
                   #'autoslip-roam--org-insert-link-advice)))

(provide 'autoslip-roam)

;;; autoslip-roam.el ends here
