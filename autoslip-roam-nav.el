;;; autoslip-roam-nav.el --- Transient navigation for autoslip-roam -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; Author: Blaine Mooers
;; Version: 3.1.0
;; Package-Requires: ((emacs "28.1") (org-roam "2.0") (transient "0.4.0") (autoslip-roam "3.1.0"))
;; Keywords: org-mode, org-roam, zettelkasten, folgezettel
;; URL: https://github.com/MooersLab/autoslip-roam

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; This file adds one command, `autoslip-roam-nav', that walks the
;; folgezettel hierarchy in a transient menu.  The menu redraws itself at
;; each step, so you move through the chain of notes without opening a
;; file until you want to.
;;
;; The menu shows three things at once:
;;
;; - the chain of thought from the root down to the current note,
;; - the previous and the next sibling of the current note,
;; - the children of the current note, each with its own key.
;;
;; The first screen lists the root notes only.  A root note has a title
;; that begins with an integer followed by a period, for example
;; "1. Crystallography".  A title such as "001 Writing of papers" (no
;; period) or "Untitled 3" (number not at the start) is not a root here,
;; even though autoslip-roam can read a number from it.  The list is
;; computed from the org-roam database, so no hand-kept index note is
;; needed.  A note that is not a root and whose parent does not exist is
;; an orphan.  Orphans are kept off the first screen and have a screen of
;; their own, so that no note is unreachable.
;;
;; Keys for the children are taken from the last part of the address
;; when that is unambiguous: the child 1.2c has the key c, and the child
;; 1.2a7 has the key 7.  When one key would be the start of another (for
;; example 1 and 14), the keys are padded to the same width (01 and 14).
;; The fixed commands use punctuation keys, so they never collide with
;; the keys of the children.
;;
;; Usage:
;;
;;   (require 'autoslip-roam-nav)
;;   (global-set-key (kbd "C-c n z") #'autoslip-roam-nav)
;;
;; With a prefix argument the command starts at the list of roots.
;; Otherwise it starts at the note at point when that note has an address.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'transient)
(require 'org-roam)
(require 'autoslip-roam)

(defgroup autoslip-roam-nav nil
  "Transient navigation for autoslip-roam."
  :group 'autoslip-roam
  :prefix "autoslip-roam-nav-")

(defcustom autoslip-roam-nav-page-size 30
  "Maximum number of children shown on one page of the menu."
  :type 'integer
  :group 'autoslip-roam-nav)

(defcustom autoslip-roam-nav-title-width 70
  "Maximum number of characters shown of a note title in the menu."
  :type 'integer
  :group 'autoslip-roam-nav)

(defface autoslip-roam-nav-current
  '((t :inherit transient-value :weight bold))
  "Face for the current note in the chain of thought."
  :group 'autoslip-roam-nav)

;;; ============================================================================
;;; State
;;; ============================================================================

(defvar autoslip-roam-nav--index nil
  "Hash table that maps a folgezettel address to its org-roam node.")

(defvar autoslip-roam-nav--children nil
  "Hash table that maps an address to the sorted addresses of its children.
The key `:top' holds the roots, which are the entries of the first
screen.  See `autoslip-roam-nav--root-p' for what counts as a root.
The key `:orphans' holds the notes that are not roots and whose parent
does not exist.")

(defvar autoslip-roam-nav--current nil
  "Address of the note the menu is showing.
The value is nil on the first screen and `:orphans' on the screen that
lists the orphans.")

(defvar autoslip-roam-nav--page 0
  "Zero-based page of the list of children.")

;;; ============================================================================
;;; Index
;;; ============================================================================

(defun autoslip-roam-nav--leading-address-p (address title)
  "Return non-nil when TITLE begins with ADDRESS.
For a root this means the integer and its period, so \"1. Topic\" begins
with the address \"1.\" and \"001 Topic\" does not begin with \"001.\"."
  (and (stringp title)
       (string-prefix-p address (string-trim-left title))))

(defun autoslip-roam-nav--root-p (address node)
  "Return non-nil when NODE with ADDRESS is a root note.
The address must be an integer with a period, and the title of NODE must
begin with it."
  (and (autoslip-roam--root-address-p address)
       (autoslip-roam-nav--leading-address-p
        address (org-roam-node-title node))))

(defun autoslip-roam-nav--build-index ()
  "Read all folgezettel notes once and fill the lookup tables."
  (let ((index (make-hash-table :test #'equal))
        (children (make-hash-table :test #'equal)))
    (dolist (node (org-roam-node-list))
      (when-let* ((title (org-roam-node-title node))
                  (address (autoslip-roam--extract-from-title title)))
        ;; When an address is found in two titles, keep the note whose
        ;; title begins with the address.  Otherwise keep the first one.
        ;; This stops \"Untitled 3\" from hiding the root \"3. Topic\".
        (let ((existing (gethash address index)))
          (when (or (null existing)
                    (and (autoslip-roam-nav--leading-address-p address title)
                         (not (autoslip-roam-nav--leading-address-p
                               address (org-roam-node-title existing)))))
            (puthash address node index)))))
    (maphash
     (lambda (address node)
       (let* ((parent (autoslip-roam--parse-address address))
              (key (cond
                    ((and parent (gethash parent index)) parent)
                    ((autoslip-roam-nav--root-p address node) :top)
                    (t :orphans))))
         (push address (gethash key children))))
     index)
    (maphash
     (lambda (key addresses)
       (puthash key (sort addresses #'autoslip-roam--compare-addresses)
                children))
     children)
    (setq autoslip-roam-nav--index index
          autoslip-roam-nav--children children)))

(defun autoslip-roam-nav--node (address)
  "Return the node with ADDRESS, or nil."
  (and (stringp address) (gethash address autoslip-roam-nav--index)))

(defun autoslip-roam-nav--children-of (address)
  "Return the sorted child addresses of ADDRESS.
A nil ADDRESS stands for the first screen and `:orphans' for the
screen of orphans."
  (gethash (or address :top) autoslip-roam-nav--children))

(defun autoslip-roam-nav--parent (address)
  "Return the parent address of ADDRESS when that note exists, else nil."
  (when (stringp address)
    (let ((parent (autoslip-roam--parse-address address)))
      (and parent (gethash parent autoslip-roam-nav--index) parent))))

(defun autoslip-roam-nav--siblings (address)
  "Return the sorted addresses on the same level as ADDRESS.
The siblings of an orphan are the other orphans."
  (let ((orphans (autoslip-roam-nav--children-of :orphans)))
    (if (member address orphans)
        orphans
      (autoslip-roam-nav--children-of (autoslip-roam-nav--parent address)))))

(defun autoslip-roam-nav--neighbor (address offset)
  "Return the sibling of ADDRESS that is OFFSET places away, or nil."
  (let* ((siblings (autoslip-roam-nav--siblings address))
         (pos (cl-position address siblings :test #'equal))
         (new (and pos (+ pos offset))))
    (and new (>= new 0) (nth new siblings))))

(defun autoslip-roam-nav--chain (address)
  "Return the addresses from the top of the chain down to ADDRESS."
  (let (chain)
    (while (stringp address)
      (push address chain)
      (setq address (autoslip-roam-nav--parent address)))
    chain))

(defun autoslip-roam-nav--title (address)
  "Return the title of the note with ADDRESS, shortened for the menu."
  (let ((node (autoslip-roam-nav--node address)))
    (truncate-string-to-width
     (or (and node (org-roam-node-title node)) address)
     autoslip-roam-nav-title-width nil nil t)))

;;; ============================================================================
;;; Keys
;;; ============================================================================

(defun autoslip-roam-nav--raw-key (address parent)
  "Return the part of ADDRESS that distinguishes it under PARENT.
A PARENT that is not a string stands for one of the two list screens."
  (string-remove-suffix
   "."
   (if (and (stringp parent) (string-prefix-p parent address))
       (substring address (length parent))
     address)))

(defun autoslip-roam-nav--pad (key width)
  "Left-pad KEY to WIDTH, with 0 for numbers and - for anything else."
  (let ((missing (- width (length key))))
    (if (<= missing 0)
        key
      (concat (make-string missing
                           (if (string-match-p "\\`[0-9]+\\'" key) ?0 ?-))
              key))))

(defun autoslip-roam-nav--keys-usable-p (keys)
  "Return non-nil when KEYS are unique, plain, and all of the same width."
  (and (cl-every (lambda (key) (string-match-p "\\`[-0-9a-z]+\\'" key)) keys)
       (= (length (delete-dups (copy-sequence keys))) (length keys))
       (or (null keys)
           (cl-every (lambda (key) (= (length key) (length (car keys))))
                     keys))))

(defun autoslip-roam-nav--assign-keys (addresses parent)
  "Return a list of (KEY . ADDRESS) for ADDRESSES under PARENT.
The keys are the ends of the addresses when that gives unique keys of
one width.  Otherwise they are padded, and as a last resort the entries
are numbered."
  (let* ((raw (mapcar (lambda (address)
                        (autoslip-roam-nav--raw-key address parent))
                      addresses))
         (width (apply #'max 0 (mapcar #'length raw)))
         (padded (mapcar (lambda (key) (autoslip-roam-nav--pad key width))
                         raw))
         (keys (cond
                ((autoslip-roam-nav--keys-usable-p raw) raw)
                ((autoslip-roam-nav--keys-usable-p padded) padded)
                (t (let ((digits (length (number-to-string
                                          (length addresses)))))
                     (cl-loop for i from 1 to (length addresses)
                              collect (format (format "%%0%dd" digits) i)))))))
    (cl-mapcar #'cons keys addresses)))

(defun autoslip-roam-nav--key-string (key)
  "Return KEY in the form that `kbd' reads as a sequence of single keys."
  (mapconcat #'char-to-string key " "))

;;; ============================================================================
;;; Moving
;;; ============================================================================

(defun autoslip-roam-nav--redisplay ()
  "Draw the menu again for the current state."
  (transient-setup 'autoslip-roam-nav))

(defun autoslip-roam-nav--goto (address)
  "Make ADDRESS the current note and draw the menu again."
  (setq autoslip-roam-nav--current address
        autoslip-roam-nav--page 0)
  (autoslip-roam-nav--redisplay))

(defun autoslip-roam-nav--page-count ()
  "Return the number of pages of children of the current note."
  (max 1 (ceiling (length (autoslip-roam-nav--children-of
                           autoslip-roam-nav--current))
                  (float (max 1 autoslip-roam-nav-page-size)))))

(defun autoslip-roam-nav--page-entries ()
  "Return the (KEY . ADDRESS) pairs on the current page."
  (let* ((all (autoslip-roam-nav--assign-keys
               (autoslip-roam-nav--children-of autoslip-roam-nav--current)
               autoslip-roam-nav--current))
         (size (max 1 autoslip-roam-nav-page-size))
         (start (* size autoslip-roam-nav--page)))
    (seq-take (nthcdr start all) size)))

(defun autoslip-roam-nav-visit ()
  "Open the current note and leave the menu."
  (interactive)
  (if-let* ((node (autoslip-roam-nav--node autoslip-roam-nav--current)))
      (org-roam-node-visit node)
    (user-error "No note is selected")))

(defun autoslip-roam-nav-peek ()
  "Show the current note in another window and keep the menu open."
  (interactive)
  (when-let* ((node (autoslip-roam-nav--node autoslip-roam-nav--current))
              (file (org-roam-node-file node))
              (buffer (find-file-noselect file))
              (window (display-buffer
                       buffer '((display-buffer-reuse-window
                                 display-buffer-use-some-window)
                                (inhibit-same-window . t)))))
    (set-window-point window (or (org-roam-node-point node) 1))))

(defun autoslip-roam-nav-up ()
  "Move to the parent of the current note.
From a root, move to the first screen.  From an orphan, move to the
screen of orphans."
  (interactive)
  (let ((current autoslip-roam-nav--current))
    (autoslip-roam-nav--goto
     (or (autoslip-roam-nav--parent current)
         (and (member current (autoslip-roam-nav--children-of :orphans))
              :orphans)))))

(defun autoslip-roam-nav-top ()
  "Move to the first screen, which lists the roots."
  (interactive)
  (autoslip-roam-nav--goto nil))

(defun autoslip-roam-nav-orphans ()
  "Move to the screen that lists the notes without a parent note."
  (interactive)
  (autoslip-roam-nav--goto :orphans))

(defun autoslip-roam-nav-previous-sibling ()
  "Move to the previous note on the same level."
  (interactive)
  (autoslip-roam-nav--goto
   (or (autoslip-roam-nav--neighbor autoslip-roam-nav--current -1)
       autoslip-roam-nav--current)))

(defun autoslip-roam-nav-next-sibling ()
  "Move to the next note on the same level."
  (interactive)
  (autoslip-roam-nav--goto
   (or (autoslip-roam-nav--neighbor autoslip-roam-nav--current 1)
       autoslip-roam-nav--current)))

(defun autoslip-roam-nav-next-page ()
  "Show the next page of children."
  (interactive)
  (setq autoslip-roam-nav--page
        (min (1+ autoslip-roam-nav--page)
             (1- (autoslip-roam-nav--page-count))))
  (autoslip-roam-nav--redisplay))

(defun autoslip-roam-nav-previous-page ()
  "Show the previous page of children."
  (interactive)
  (setq autoslip-roam-nav--page (max 0 (1- autoslip-roam-nav--page)))
  (autoslip-roam-nav--redisplay))

(defun autoslip-roam-nav-jump ()
  "Choose any folgezettel note in the minibuffer and move to it."
  (interactive)
  (let* ((titles (let (all)
                   (maphash (lambda (_address node)
                              (push (org-roam-node-title node) all))
                            autoslip-roam-nav--index)
                   (sort all #'string<)))
         (choice (completing-read "Jump to note: " titles nil t)))
    (autoslip-roam-nav--goto (autoslip-roam--extract-from-title choice))))

(defun autoslip-roam-nav-new-child ()
  "Open the current note and create a child of it."
  (interactive)
  (autoslip-roam-nav-visit)
  (call-interactively #'autoslip-roam-insert-next-child))

(defun autoslip-roam-nav-refresh ()
  "Read the notes again and draw the menu again."
  (interactive)
  (autoslip-roam--maybe-sync-db)
  (autoslip-roam-nav--build-index)
  (unless (autoslip-roam-nav--node autoslip-roam-nav--current)
    (setq autoslip-roam-nav--current nil))
  (setq autoslip-roam-nav--page 0)
  (autoslip-roam-nav--redisplay))

;;; ============================================================================
;;; Menu text
;;; ============================================================================

(defun autoslip-roam-nav--header ()
  "Return the heading of the menu: the chain down to the current note."
  (cond
   ((null autoslip-roam-nav--current)
    (format "Autoslip roots (%d notes with an address)"
            (hash-table-count autoslip-roam-nav--index)))
   ((eq autoslip-roam-nav--current :orphans)
    "Autoslip orphans (notes that are not roots and have no parent note)")
   (t
    (let ((chain (autoslip-roam-nav--chain autoslip-roam-nav--current))
          (depth 0)
          lines)
      (dolist (address chain)
        (let ((title (autoslip-roam-nav--title address)))
          (push (concat (make-string (* 2 depth) ?\s)
                        (if (equal address autoslip-roam-nav--current)
                            (propertize title 'face
                                        'autoslip-roam-nav-current)
                          (propertize title 'face 'transient-inactive-value)))
                lines))
        (setq depth (1+ depth)))
      (concat (propertize "Chain of thought" 'face 'transient-heading) "\n"
              (string-join (nreverse lines) "\n"))))))

(defun autoslip-roam-nav--children-heading ()
  "Return the heading of the list of children."
  (let ((count (length (autoslip-roam-nav--children-of
                        autoslip-roam-nav--current)))
        (pages (autoslip-roam-nav--page-count)))
    (concat (cond ((null autoslip-roam-nav--current) "Roots")
                  ((eq autoslip-roam-nav--current :orphans) "Orphans")
                  (t "Children"))
            (format " (%d)" count)
            (if (> pages 1)
                (format ", page %d of %d"
                        (1+ autoslip-roam-nav--page) pages)
              ""))))

(defun autoslip-roam-nav--describe-up ()
  "Return the menu text of the command that moves up."
  (let ((current autoslip-roam-nav--current))
    (cond
     ((autoslip-roam-nav--parent current)
      (format "Up to %s" (autoslip-roam-nav--title
                          (autoslip-roam-nav--parent current))))
     ((member current (autoslip-roam-nav--children-of :orphans))
      "Up to the orphans")
     (t "Up to the roots"))))

(defun autoslip-roam-nav--describe-previous ()
  "Return the menu text of the command that moves to the previous sibling."
  (format "Previous: %s"
          (autoslip-roam-nav--title
           (autoslip-roam-nav--neighbor autoslip-roam-nav--current -1))))

(defun autoslip-roam-nav--describe-next ()
  "Return the menu text of the command that moves to the next sibling."
  (format "Next: %s"
          (autoslip-roam-nav--title
           (autoslip-roam-nav--neighbor autoslip-roam-nav--current 1))))

(defun autoslip-roam-nav--current-p ()
  "Return non-nil when the menu shows a note and not a list screen."
  (stringp autoslip-roam-nav--current))

(defun autoslip-roam-nav--not-top-p ()
  "Return non-nil when the menu does not show the first screen."
  (and autoslip-roam-nav--current t))

(defun autoslip-roam-nav--orphans-p ()
  "Return non-nil when there are orphans and their screen is not shown."
  (and (autoslip-roam-nav--children-of :orphans)
       (not (eq autoslip-roam-nav--current :orphans))))

(defun autoslip-roam-nav--describe-orphans ()
  "Return the menu text of the command that lists the orphans."
  (format "Orphans (%d)" (length (autoslip-roam-nav--children-of :orphans))))

(defun autoslip-roam-nav--previous-p ()
  "Return non-nil when the current note has a previous sibling."
  (and (stringp autoslip-roam-nav--current)
       (autoslip-roam-nav--neighbor autoslip-roam-nav--current -1)))

(defun autoslip-roam-nav--next-p ()
  "Return non-nil when the current note has a next sibling."
  (and (stringp autoslip-roam-nav--current)
       (autoslip-roam-nav--neighbor autoslip-roam-nav--current 1)))

(defun autoslip-roam-nav--children-p ()
  "Return non-nil when the current note has children."
  (and (autoslip-roam-nav--children-of autoslip-roam-nav--current) t))

(defun autoslip-roam-nav--pages-p ()
  "Return non-nil when the children do not fit on one page."
  (> (autoslip-roam-nav--page-count) 1))

(defun autoslip-roam-nav--child-command (position)
  "Return a command that moves to the child at POSITION on the page.
The commands are named and created on demand.  Named commands are used
because transient cannot take anonymous functions in every version."
  (let ((symbol (intern (format "autoslip-roam-nav-child-%d" position))))
    (unless (fboundp symbol)
      (defalias symbol
        (lambda ()
          (interactive)
          (if-let* ((entry (nth position (autoslip-roam-nav--page-entries))))
              (autoslip-roam-nav--goto (cdr entry))
            (user-error "No child at position %d" (1+ position))))
        (format "Move to child number %d on the current menu page."
                (1+ position))))
    symbol))

(defun autoslip-roam-nav--child-specs ()
  "Return the transient suffix specifications for the current page."
  (let ((position -1))
    (mapcar
     (lambda (entry)
       (setq position (1+ position))
       (list (autoslip-roam-nav--key-string (car entry))
             (autoslip-roam-nav--title (cdr entry))
             (autoslip-roam-nav--child-command position)))
     (autoslip-roam-nav--page-entries))))

(defun autoslip-roam-nav--setup-children (_children)
  "Build the entries for the children of the current note."
  (transient-parse-suffixes 'autoslip-roam-nav
                            (autoslip-roam-nav--child-specs)))

;;; ============================================================================
;;; Menu
;;; ============================================================================

;;;###autoload (autoload 'autoslip-roam-nav "autoslip-roam-nav" nil t)
(transient-define-prefix autoslip-roam-nav (&optional top)
  "Walk the folgezettel hierarchy in a menu.
Start at the note at point when it has an address.  With the prefix
argument TOP, or when there is no such note, start at the list of roots."
  [:description
   autoslip-roam-nav--header
   ("RET" "Visit this note" autoslip-roam-nav-visit
    :if autoslip-roam-nav--current-p)
   ("SPC" "Peek at this note" autoslip-roam-nav-peek
    :if autoslip-roam-nav--current-p :transient t)
   ("^" autoslip-roam-nav-up
    :description autoslip-roam-nav--describe-up
    :if autoslip-roam-nav--current-p)
   ("<" autoslip-roam-nav-previous-sibling
    :description autoslip-roam-nav--describe-previous
    :if autoslip-roam-nav--previous-p)
   (">" autoslip-roam-nav-next-sibling
    :description autoslip-roam-nav--describe-next
    :if autoslip-roam-nav--next-p)]
  [:description
   autoslip-roam-nav--children-heading
   :if autoslip-roam-nav--children-p
   :class transient-column
   :setup-children autoslip-roam-nav--setup-children]
  ["Menu"
   :class transient-row
   ("~" "Roots" autoslip-roam-nav-top
    :if autoslip-roam-nav--not-top-p)
   ("%" autoslip-roam-nav-orphans
    :description autoslip-roam-nav--describe-orphans
    :if autoslip-roam-nav--orphans-p)
   ("[" "Previous page" autoslip-roam-nav-previous-page
    :if autoslip-roam-nav--pages-p)
   ("]" "Next page" autoslip-roam-nav-next-page
    :if autoslip-roam-nav--pages-p)
   ("@" "Jump to any note" autoslip-roam-nav-jump)
   ("+" "New child" autoslip-roam-nav-new-child
    :if autoslip-roam-nav--current-p)
   ("!" "Refresh" autoslip-roam-nav-refresh)]
  (interactive "P")
  (let ((here (and (not top)
                   (derived-mode-p 'org-mode)
                   (when-let* ((node (ignore-errors (org-roam-node-at-point)))
                               (title (org-roam-node-title node)))
                     (autoslip-roam--extract-from-title title)))))
    (autoslip-roam--maybe-sync-db)
    (autoslip-roam-nav--build-index)
    (setq autoslip-roam-nav--current
          (and here (autoslip-roam-nav--node here) here)
          autoslip-roam-nav--page 0)
    (transient-setup 'autoslip-roam-nav)))

(provide 'autoslip-roam-nav)

;;; autoslip-roam-nav.el ends here
