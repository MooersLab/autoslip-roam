;;; autoslip-subtree-notes-generator.el --- Notes from addressed headlines for autoslip-roam -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; Author: Blaine Mooers
;; Version: 3.2.0
;; Package-Requires: ((emacs "27.1") (org-roam "2.0") (autoslip-roam "3.1.0"))
;; Keywords: org-mode, org-roam, zettelkasten, folgezettel
;; URL: https://github.com/MooersLab/autoslip-roam

;;; Commentary:

;; This package turns an outline of addressed headlines into org-roam
;; notes.  It runs beside autoslip-roam and uses its address functions,
;; its headings, and its link descriptions, so the notes that it writes
;; look like the notes that autoslip-roam writes.
;;
;; The outline sits in the parent note, in a separate file, or in the
;; clipboard.  Each headline has the form
;;
;;   ** 7.1 Crystal growth
;;   *** 7.1a Vapor diffusion
;;
;; that is, stars, a folgezettel address, and a title.  The headlines can
;; be written by hand or by the autoslip-index-generator skill.
;;
;; Usage:
;;
;;   1. Visit the parent note, for example "7. Crystallography".
;;   2. M-x autoslip-subtree-notes-generator-preview   (writes nothing)
;;   3. M-x autoslip-subtree-notes-generator-generate
;;
;; With a prefix argument (C-u), both commands ask where the outline is:
;; in this note, in a file, or in the clipboard.  Two more commands skip
;; that question:
;;
;;   M-x autoslip-subtree-notes-generator-generate-from-file
;;   M-x autoslip-subtree-notes-generator-generate-from-clipboard
;;
;; In all cases the current buffer visits the parent note.  The notes are
;; linked to that note, wherever the outline came from.
;;
;; The generate command shows the plan, asks one question, and then writes
;; one note file for each headline whose address lies below the address of
;; the parent note.  It does this for every level of the subtree.
;;
;; Each new note holds:
;;
;;   - a property drawer with a new ID,
;;   - the headline as its #+title,
;;   - the index lines that sat below the headline (optional),
;;   - the keyword lines of the template of its kind (optional),
;;   - ten blank lines,
;;   - the "Parent Note" heading with a link back to the parent,
;;   - the headings of the template of its kind (optional),
;;   - the "Child Notes" heading with a link to each of its own children.
;;
;; The parent note gets a link to each new child under "Child Notes".
;;
;; Rules:
;;
;;   - The address decides the parent of a note.  The number of stars
;;     does not.
;;   - A note whose address is already in the vault is never overwritten.
;;     It is skipped, so the command is safe to run twice.
;;   - A headline without a parent note in the outline or in the vault
;;     stops the command before anything is written.
;;   - Only the `headings' value of `autoslip-roam-link-storage' is
;;     supported.
;;
;; Kinds and templates:
;;
;; The kinds are given in level order, starting with the children of the
;; parent note.  The last kind repeats for the deeper levels.  The kind
;; "plain" needs no template.  Any other kind K needs the file K.org in
;; `autoslip-subtree-notes-generator-templates-directory'.  A template may
;; hold keyword lines and headings.  It must not hold a #+title line or a
;; property drawer.  These placeholders are filled in: ${title},
;; ${heading}, ${address}, ${kind}, and ${date}.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'org-id)
(require 'org-roam)
(require 'autoslip-roam)

(defgroup autoslip-subtree-notes-generator nil
  "Generate org-roam notes from an outline of addressed headlines."
  :group 'autoslip-roam
  :prefix "autoslip-subtree-notes-generator-")

(defcustom autoslip-subtree-notes-generator-kinds '("plain")
  "Default kinds of notes, in level order.
The first kind is for the children of the parent note, the second for
the grandchildren, and so on.  The last kind repeats for all deeper
levels."
  :type '(repeat string)
  :group 'autoslip-subtree-notes-generator)

(defcustom autoslip-subtree-notes-generator-templates-directory nil
  "Directory that holds one template file KIND.org for each kind.
The kind \"plain\" needs no template file."
  :type '(choice (const :tag "None" nil) directory)
  :group 'autoslip-subtree-notes-generator)

(defcustom autoslip-subtree-notes-generator-blank-lines 10
  "Number of blank lines between the title block and the parent heading."
  :type 'integer
  :group 'autoslip-subtree-notes-generator)

(defcustom autoslip-subtree-notes-generator-copy-index-lines t
  "Whether to copy the index lines below a headline to its note.
An index line starts with #+LATEX: \\index{ and sits directly below the
headline in the outline."
  :type 'boolean
  :group 'autoslip-subtree-notes-generator)

(defvar autoslip-subtree-notes-generator-buffer-name "*Autoslip Subtree Notes*"
  "Name of the buffer that shows the plan.")

;;; ---------------------------------------------------------------------------
;;; Addresses

(defun autoslip-subtree-notes-generator--address (string)
  "Return STRING as a canonical folgezettel address, or nil if it is not one.
A root gets its trailing period.  The index of indices is not accepted."
  (let ((case-fold-search nil))
    (when (and (stringp string)
               (not (string= string autoslip-roam-index-address))
               (string-match-p "\\`[0-9]+\\(?:[.][0-9a-z]*\\)?\\'" string)
               (or (autoslip-roam--root-address-p string)
                   (autoslip-roam-validate-address string)))
      (autoslip-roam--canonicalize-root string))))

(defun autoslip-subtree-notes-generator--below-p (address parent)
  "Return non-nil if ADDRESS lies below PARENT at any depth."
  (let ((cur (autoslip-roam--parse-address address))
        (found nil))
    (while (and cur (not found))
      (if (string= cur parent)
          (setq found t)
        (setq cur (autoslip-roam--parse-address cur))))
    found))

;;; ---------------------------------------------------------------------------
;;; Reading the outline

(defun autoslip-subtree-notes-generator--read-outline (parent-address)
  "Return the headlines of the current buffer that lie below PARENT-ADDRESS.
Each item is a plist with the keys :address, :heading, and :keys.  The
list is in folgezettel order.  Signal an error when an address appears
twice."
  (let ((case-fold-search nil)
        (seen (make-hash-table :test #'equal))
        (items nil))
    (org-with-wide-buffer
     (goto-char (point-min))
     (while (re-search-forward
             "^\\*+[ \t]+\\([0-9][0-9a-z.]*\\)[ \t]+\\(.*?\\)[ \t]*$" nil t)
       ;; Read both groups first, because the address check below
       ;; changes the match data.
       (let* ((raw (match-string-no-properties 1))
              (heading (match-string-no-properties 2))
              (address (autoslip-subtree-notes-generator--address raw))
              (keys nil))
         (when (and address
                    (not (string-empty-p heading))
                    (autoslip-subtree-notes-generator--below-p
                     address parent-address))
           (when (gethash address seen)
             (user-error "The address %s appears twice in the outline" address))
           (puthash address t seen)
           ;; Collect the index lines directly below the headline.
           (save-excursion
             (forward-line 1)
             (let ((case-fold-search t))
               (while (looking-at "^#\\+LATEX:[ \t]*\\\\index{.*$")
                 (push (match-string-no-properties 0) keys)
                 (forward-line 1))))
           (push (list :address address :heading heading :keys (nreverse keys))
                 items)))))
    (sort items (lambda (a b)
                  (autoslip-roam--compare-addresses
                   (plist-get a :address) (plist-get b :address))))))

;; An outline source is one of:
;;   nil          the current buffer, which visits the parent note
;;   a string     the name of an outline file
;;   clipboard    the text in the clipboard (a symbol)
;;   (text . S)   the string S, for Lisp programs and tests

(defun autoslip-subtree-notes-generator--clipboard-text ()
  "Return the text in the clipboard, or the newest kill when there is none."
  (let ((text (ignore-errors (current-kill 0 t))))
    (if (and text (not (string-empty-p (string-trim text))))
        (substring-no-properties text)
      (user-error "The clipboard is empty"))))

(defun autoslip-subtree-notes-generator--source-name (outline)
  "Return a short name of the outline source OUTLINE for messages."
  (cond ((null outline) "this note")
        ((stringp outline) (abbreviate-file-name outline))
        ((eq outline 'clipboard) "the clipboard")
        (t "the given text")))

(defun autoslip-subtree-notes-generator--outline-items (parent-address outline)
  "Return the headlines below PARENT-ADDRESS from the source OUTLINE.
See `autoslip-subtree-notes-generator--read-outline' for the result."
  (cond
   ((null outline)
    (autoslip-subtree-notes-generator--read-outline parent-address))
   ((stringp outline)
    (let ((file (expand-file-name outline)))
      (unless (and (file-regular-p file) (file-readable-p file))
        (user-error "The outline file %s cannot be read" file))
      (with-temp-buffer
        (insert-file-contents file)
        (autoslip-subtree-notes-generator--read-outline parent-address))))
   ((eq outline 'clipboard)
    (let ((text (autoslip-subtree-notes-generator--clipboard-text)))
      (with-temp-buffer
        (insert text)
        (autoslip-subtree-notes-generator--read-outline parent-address))))
   ((eq (car-safe outline) 'text)
    (with-temp-buffer
      (insert (cdr outline))
      (autoslip-subtree-notes-generator--read-outline parent-address)))
   (t (error "Unknown outline source: %S" outline))))

;;; ---------------------------------------------------------------------------
;;; Templates

(defun autoslip-subtree-notes-generator--template (kind)
  "Return the template of KIND as a cons cell (HEADER . BODY).
HEADER holds the lines before the first heading and BODY the rest.  Both
are strings without a newline at either end."
  (if (string= kind "plain")
      (cons "" "")
    (let ((dir autoslip-subtree-notes-generator-templates-directory))
      (unless dir
        (user-error
         "The kind %s needs `autoslip-subtree-notes-generator-templates-directory'"
         kind))
      (let ((file (expand-file-name (concat kind ".org") dir)))
        (unless (file-readable-p file)
          (user-error "No template %s for the kind %s" file kind))
        (with-temp-buffer
          (insert-file-contents file)
          (let ((case-fold-search t))
            (goto-char (point-min))
            (when (re-search-forward
                   "^\\(?:#\\+title:\\|:PROPERTIES:\\|:ID:\\)" nil t)
              (user-error
               "The template %s must not hold a title or a property drawer"
               file)))
          (goto-char (point-min))
          (let ((split (if (re-search-forward "^\\*" nil t)
                           (match-beginning 0)
                         (point-max))))
            (cons (string-trim (buffer-substring-no-properties
                                (point-min) split)
                               "\n+" "[ \t\n]+")
                  (string-trim (buffer-substring-no-properties
                                split (point-max))
                               "\n+" "[ \t\n]+"))))))))

(defun autoslip-subtree-notes-generator--fill (text values)
  "Replace each ${KEY} in TEXT by its value in the alist VALUES."
  (dolist (pair values text)
    (setq text (replace-regexp-in-string
                (regexp-quote (format "${%s}" (car pair)))
                (cdr pair) text t t))))

;;; ---------------------------------------------------------------------------
;;; The plan

(defun autoslip-subtree-notes-generator--kind (kinds level)
  "Return the kind in KINDS for LEVEL, where the children are level 2."
  (nth (min (- level 2) (1- (length kinds))) kinds))

(defun autoslip-subtree-notes-generator--file-name (title directory stamped time taken)
  "Return a fresh file name for a note with TITLE in DIRECTORY.
When STAMPED is non-nil the name starts with a timestamp, which is taken
from the cons cell TIME and moved forward by one second per try.  TAKEN
is a list of names that are already planned."
  (let* ((slug (org-roam-node-slug (org-roam-node-create :title title)))
         (file nil))
    (while (null file)
      (let ((candidate
             (expand-file-name
              (if stamped
                  (format "%s-%s.org"
                          (format-time-string "%Y%m%d%H%M%S" (car time)) slug)
                (concat slug ".org"))
              directory)))
        (setcar time (time-add (car time) 1))
        (cond
         ((not (or (file-exists-p candidate) (member candidate taken)))
          (setq file candidate))
         ((not stamped)
          (user-error "The file %s already exists" candidate)))))
    file))

(defun autoslip-subtree-notes-generator--plan (parent-address kinds &optional outline)
  "Return the plan for the current buffer, the note with PARENT-ADDRESS.
KINDS is the list of kinds in level order.  OUTLINE is the outline
source, and nil means the current buffer.  The plan is a plist with
the keys :parent-id, :parent-file, :new, and :skipped.  :new is a list of
note plists and :skipped a list of addresses that are already in use."
  (let* ((parent-file (buffer-file-name (buffer-base-buffer)))
         (parent-id (org-entry-get (point-min) "ID"))
         (source outline)
         (outline (autoslip-subtree-notes-generator--outline-items
                   parent-address source))
         (table (progn (autoslip-roam--maybe-sync-db)
                       (autoslip-roam--address-table)))
         (directory (file-name-directory parent-file))
         (stamped (string-match-p "\\`[0-9]\\{14\\}-"
                                  (file-name-nondirectory parent-file)))
         (time (list (current-time)))
         (depth0 (autoslip-roam--address-depth parent-address))
         (ids (make-hash-table :test #'equal))
         (new nil) (skipped nil) (taken nil))
    (unless outline
      (user-error "No headline with an address below %s was found in %s"
                  parent-address
                  (autoslip-subtree-notes-generator--source-name source)))
    ;; Check the templates before anything is planned.
    (dolist (kind (delete-dups (copy-sequence kinds)))
      (autoslip-subtree-notes-generator--template kind))
    ;; Known notes: the parent and every note of the vault with an address.
    (maphash (lambda (address node)
               (puthash address (cons (org-roam-node-id node)
                                      (org-roam-node-file node))
                        ids))
             table)
    (puthash parent-address (cons parent-id parent-file) ids)
    ;; Split the outline into new notes and notes that exist.
    (dolist (item outline)
      (let ((address (plist-get item :address)))
        (if (gethash address table)
            (push address skipped)
          (let* ((title (concat address " " (plist-get item :heading)))
                 (level (1+ (- (autoslip-roam--address-depth address) depth0)))
                 (file (autoslip-subtree-notes-generator--file-name
                        title directory stamped time taken))
                 (id (org-id-uuid)))
            (push file taken)
            (puthash address (cons id file) ids)
            (push (append item
                          (list :title title
                                :kind (autoslip-subtree-notes-generator--kind
                                       kinds level)
                                :id id
                                :file file
                                :parent (autoslip-roam--parse-address address)))
                  new)))))
    (setq new (nreverse new))
    ;; Every new note needs a parent note.
    (let ((orphans (cl-remove-if
                    (lambda (note) (gethash (plist-get note :parent) ids))
                    new)))
      (when orphans
        (user-error "These headlines have no parent note: %s"
                    (mapconcat (lambda (note) (plist-get note :address))
                               orphans ", "))))
    ;; Record the ID and file of each parent, and who is new.
    (let ((new-addresses (mapcar (lambda (note) (plist-get note :address)) new)))
      (setq new
            (mapcar
             (lambda (note)
               (let* ((parent (plist-get note :parent))
                      (cell (gethash parent ids)))
                 (append note
                         (list :parent-id (car cell)
                               :parent-file (cdr cell)
                               :parent-new (and (member parent new-addresses)
                                                t)))))
             new)))
    (list :parent-id parent-id
          :parent-file parent-file
          :parent-address parent-address
          :source (autoslip-subtree-notes-generator--source-name source)
          :new new
          :skipped (nreverse skipped))))

;;; ---------------------------------------------------------------------------
;;; Writing

(defun autoslip-subtree-notes-generator--link (id description)
  "Return an org link to ID with DESCRIPTION, which may be nil or empty."
  (if (and description (not (string-empty-p description)))
      (format "[[id:%s][%s]]" id description)
    (format "[[id:%s]]" id)))

(defun autoslip-subtree-notes-generator--child-link (note)
  "Return the forward link to NOTE."
  (autoslip-subtree-notes-generator--link
   (plist-get note :id)
   (or autoslip-roam-child-link-description (plist-get note :title))))

(defun autoslip-subtree-notes-generator--note-text (note children parent-title)
  "Return the text of NOTE.
CHILDREN is the list of the new notes below NOTE.  PARENT-TITLE is used
as the description of the parent link when
`autoslip-roam-parent-link-description' is nil."
  (let* ((template (autoslip-subtree-notes-generator--template
                    (plist-get note :kind)))
         (values `(("title" . ,(plist-get note :title))
                   ("heading" . ,(plist-get note :heading))
                   ("address" . ,(plist-get note :address))
                   ("kind" . ,(plist-get note :kind))
                   ("date" . ,(format-time-string "%Y-%m-%d"))))
         (header (autoslip-subtree-notes-generator--fill (car template) values))
         (body (autoslip-subtree-notes-generator--fill (cdr template) values))
         (lines (list ":PROPERTIES:"
                      (format ":ID:       %s" (plist-get note :id))
                      ":END:"
                      (concat "#+title: " (plist-get note :title)))))
    (when autoslip-subtree-notes-generator-copy-index-lines
      (setq lines (append lines (plist-get note :keys))))
    (unless (string-empty-p header)
      (setq lines (append lines (list header))))
    (setq lines
          (append lines
                  (make-list autoslip-subtree-notes-generator-blank-lines "")
                  (list (concat "* " autoslip-roam-backlink-heading)
                        (autoslip-subtree-notes-generator--link
                         (plist-get note :parent-id)
                         (or autoslip-roam-parent-link-description
                             parent-title)))))
    (unless (string-empty-p body)
      (setq lines (append lines (list "" body))))
    (when children
      (setq lines
            (append lines
                    (list "" (concat "* " autoslip-roam-forward-link-heading))
                    (mapcar #'autoslip-subtree-notes-generator--child-link
                            children))))
    (concat (mapconcat #'identity lines "\n") "\n")))

(defun autoslip-subtree-notes-generator--add-forward-links (file children)
  "Add a link to each note in CHILDREN under the child heading of FILE.
A link that is already there is left alone.  New links go to the end of
the section, so the children stay in folgezettel order.  Return the
number of links added."
  (let ((added 0))
    (with-current-buffer (find-file-noselect file)
      (org-with-wide-buffer
       (dolist (child children)
         (unless (autoslip-roam--link-under-heading-p
                  (plist-get child :id) autoslip-roam-forward-link-heading)
           (goto-char (point-min))
           (if (re-search-forward
                (concat "^\\*+ "
                        (regexp-quote autoslip-roam-forward-link-heading)
                        "[ \t]*$")
                nil t)
               ;; Go to the end of the section, before trailing blank lines.
               (progn
                 (forward-line 1)
                 (if (re-search-forward "^\\*+ " nil t)
                     (goto-char (match-beginning 0))
                   (goto-char (point-max)))
                 (skip-chars-backward " \t\n")
                 (forward-line 1)
                 (unless (bolp) (insert "\n")))
             ;; The heading does not exist.  Create it at the end.
             (goto-char (point-max))
             (skip-chars-backward " \t\n")
             (delete-region (point) (point-max))
             (insert "\n\n* " autoslip-roam-forward-link-heading "\n"))
           (insert (autoslip-subtree-notes-generator--child-link child) "\n")
           (setq added (1+ added)))))
      (when (> added 0)
        (save-buffer)
        (org-roam-db-update-file file)))
    added))

(defun autoslip-subtree-notes-generator--write (plan)
  "Write the notes of PLAN and add the forward links.
Return the list of the files written."
  (let* ((new (plist-get plan :new))
         (titles (make-hash-table :test #'equal))
         (by-parent (make-hash-table :test #'equal))
         (files nil))
    (dolist (note new)
      (puthash (plist-get note :address) (plist-get note :title) titles)
      (puthash (plist-get note :parent)
               (append (gethash (plist-get note :parent) by-parent)
                       (list note))
               by-parent))
    ;; Write the new notes.  A new parent gets its child links here.
    (dolist (note new)
      (let ((file (plist-get note :file))
            (text (autoslip-subtree-notes-generator--note-text
                   note
                   (gethash (plist-get note :address) by-parent)
                   (gethash (plist-get note :parent) titles))))
        ;; The value excl makes Emacs refuse to overwrite a file.
        (write-region text nil file nil 'silent nil 'excl)
        (org-id-add-location (plist-get note :id) file)
        (push file files)))
    ;; Add the forward links to the parents that existed before.
    (maphash (lambda (_parent children)
               (unless (plist-get (car children) :parent-new)
                 (autoslip-subtree-notes-generator--add-forward-links
                  (plist-get (car children) :parent-file) children)))
             by-parent)
    (setq files (nreverse files))
    (dolist (file files)
      (org-roam-db-update-file file))
    files))

;;; ---------------------------------------------------------------------------
;;; The report

(defun autoslip-subtree-notes-generator--report (plan written)
  "Show PLAN in the report buffer.
WRITTEN is non-nil when the notes were written."
  (let ((new (plist-get plan :new))
        (skipped (plist-get plan :skipped)))
    (with-current-buffer
        (get-buffer-create autoslip-subtree-notes-generator-buffer-name)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "%s %d notes below %s\nOutline from %s\n\n"
                        (if written "Wrote" "Plan:")
                        (length new)
                        (plist-get plan :parent-address)
                        (plist-get plan :source)))
        (dolist (note new)
          (insert (format "%-14s %-10s %s\n"
                          (plist-get note :address)
                          (plist-get note :kind)
                          (file-name-nondirectory (plist-get note :file)))))
        (when skipped
          (insert (format "\nSkipped, already in the vault: %s\n"
                          (mapconcat #'identity skipped ", "))))
        (goto-char (point-min)))
      (special-mode)
      (display-buffer (current-buffer)))))

;;; ---------------------------------------------------------------------------
;;; Commands

(defun autoslip-subtree-notes-generator--read-kinds ()
  "Read the kinds of notes from the minibuffer."
  (let ((answer (read-string
                 "Kinds of notes per level, separated by commas: "
                 (mapconcat #'identity
                            autoslip-subtree-notes-generator-kinds ","))))
    (or (split-string answer "[ \t]*,[ \t]*" t "[ \t]+")
        (list "plain"))))

(defun autoslip-subtree-notes-generator--read-source ()
  "Ask where the outline is and return the outline source."
  (let ((choice (completing-read
                 "Outline from: "
                 '("this note" "a file" "the clipboard") nil t nil nil
                 "this note")))
    (cond ((string= choice "a file")
           (expand-file-name (read-file-name "Outline file: " nil nil t)))
          ((string= choice "the clipboard") 'clipboard)
          (t nil))))

(defun autoslip-subtree-notes-generator--check-parent (interactive-p)
  "Check the current buffer and return the address of its note.
When INTERACTIVE-P is non-nil, offer to create a missing ID."
  (unless (derived-mode-p 'org-mode)
    (user-error "The parent note must be an Org file"))
  (unless (buffer-file-name (buffer-base-buffer))
    (user-error "The parent note must be saved to a file first"))
  (unless (eq autoslip-roam-link-storage 'headings)
    (user-error
     "Only the headings value of `autoslip-roam-link-storage' is supported"))
  (unless (and autoslip-roam-backlink-heading
               autoslip-roam-forward-link-heading)
    (user-error "The parent and child headings of autoslip-roam must be set"))
  (let* ((title (autoslip-roam--buffer-title))
         (address (and title (autoslip-roam--extract-from-title title))))
    (unless address
      (user-error "The title of this note carries no folgezettel address"))
    (unless (org-entry-get (point-min) "ID")
      (if (and interactive-p
               (y-or-n-p "The parent note has no ID.  Create one? "))
          (save-excursion
            (goto-char (point-min))
            (org-id-get-create)
            (save-buffer))
        (user-error "The parent note has no ID, so nothing can link to it")))
    address))

;;;###autoload
(defun autoslip-subtree-notes-generator-generate (&optional kinds no-confirm dry-run outline)
  "Write one note for each addressed headline below the current note.
The current buffer visits the parent note.  KINDS is a list of kinds in
level order and defaults to `autoslip-subtree-notes-generator-kinds'.
The command shows the plan and asks before it writes, unless NO-CONFIRM
is non-nil.  With DRY-RUN non-nil it writes nothing.

OUTLINE says where the headlines are.  It is nil for the current note,
a file name for an outline file, or the symbol `clipboard' for the text
in the clipboard.  With a prefix argument the command asks for it.

Return the list of the files written, or the plan after a dry run."
  (interactive
   (let ((outline (and current-prefix-arg
                       (autoslip-subtree-notes-generator--read-source))))
     (list (autoslip-subtree-notes-generator--read-kinds) nil nil outline)))
  (let* ((interactive-p (called-interactively-p 'any))
         (address (autoslip-subtree-notes-generator--check-parent
                   interactive-p))
         (kinds (or kinds autoslip-subtree-notes-generator-kinds '("plain")))
         (plan (autoslip-subtree-notes-generator--plan address kinds outline))
         (count (length (plist-get plan :new))))
    (unless noninteractive
      (autoslip-subtree-notes-generator--report plan nil))
    (cond
     (dry-run plan)
     ((zerop count)
      (message "Every headline below %s has a note already" address)
      nil)
     ((or no-confirm
          (y-or-n-p (format "Write %d notes below %s? " count address)))
      (let ((files (autoslip-subtree-notes-generator--write plan)))
        (unless noninteractive
          (autoslip-subtree-notes-generator--report plan t))
        (message "Wrote %d notes below %s" (length files) address)
        files))
     (t (message "Nothing was written.") nil))))

;;;###autoload
(defun autoslip-subtree-notes-generator-generate-from-file (file &optional kinds no-confirm dry-run)
  "Write the notes below the current note from the outline in FILE.
KINDS, NO-CONFIRM, and DRY-RUN are as in
`autoslip-subtree-notes-generator-generate'."
  (interactive
   (list (read-file-name "Outline file: " nil nil t)
         (autoslip-subtree-notes-generator--read-kinds)))
  (autoslip-subtree-notes-generator-generate
   kinds no-confirm dry-run (expand-file-name file)))

;;;###autoload
(defun autoslip-subtree-notes-generator-generate-from-clipboard (&optional kinds no-confirm dry-run)
  "Write the notes below the current note from the outline in the clipboard.
KINDS, NO-CONFIRM, and DRY-RUN are as in
`autoslip-subtree-notes-generator-generate'."
  (interactive (list (autoslip-subtree-notes-generator--read-kinds)))
  (autoslip-subtree-notes-generator-generate
   kinds no-confirm dry-run 'clipboard))

;;;###autoload
(defun autoslip-subtree-notes-generator-preview (&optional kinds outline)
  "Show the notes that would be written below the current note.
KINDS is a list of kinds in level order.  OUTLINE is the outline source
as in `autoslip-subtree-notes-generator-generate', and with a prefix
argument the command asks for it.  Nothing is written."
  (interactive
   (let ((outline (and current-prefix-arg
                       (autoslip-subtree-notes-generator--read-source))))
     (list (autoslip-subtree-notes-generator--read-kinds) outline)))
  (let ((plan (autoslip-subtree-notes-generator-generate kinds nil t outline)))
    (autoslip-subtree-notes-generator--report plan nil)
    plan))

(provide 'autoslip-subtree-notes-generator)

;;; autoslip-subtree-notes-generator.el ends here
