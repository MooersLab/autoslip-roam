;;; autoslip-roam-html.el --- Browser dashboard for autoslip-roam -*- lexical-binding: t; -*-

;; Copyright (C) 2026

;; Author: Blaine Mooers
;; Version: 3.2.0
;; Package-Requires: ((emacs "28.1") (org-roam "2.0") (transient "0.4.0") (autoslip-roam "3.1.0"))
;; Keywords: org-mode, org-roam, zettelkasten, folgezettel
;; URL: https://github.com/MooersLab/autoslip-roam

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;;; Commentary:

;; This file writes the folgezettel hierarchy to one HTML page and opens
;; it in a web browser.  The page is a dashboard for the whole vault:
;;
;; - The root notes are listed first.  Each root unfolds into its chain
;;   of notes, level by level.
;; - A filter box narrows the tree to the notes that match what you type
;;   and unfolds the chains that lead to them.
;; - Buttons unfold or fold the whole tree.
;; - The page remembers which notes were unfolded, so it looks the same
;;   after you write it again.
;; - Notes that are not roots and have no parent note are listed in a
;;   separate section at the bottom.
;;
;; The page is a single file with no outside resources, so it works
;; without a network connection and can be shared or printed.
;;
;; Roots and orphans are found by the same rules as in the transient
;; menu, because this file reads the lookup tables of autoslip-roam-nav.
;;
;; Clicking a note opens it in Emacs through org-protocol.  This needs
;; `org-roam-protocol' to be loaded, a running Emacs server, and an
;; operating system that sends org-protocol links to emacsclient.  When
;; that is not set up, set `autoslip-roam-html-link-type' to `file' to
;; link to the Org files, or to nil for a page without links.
;;
;; Usage:
;;
;;   (require 'autoslip-roam-html)
;;   (global-set-key (kbd "C-c n h") #'autoslip-roam-html-open)
;;
;; The page is a snapshot.  Run the command again to bring it up to date.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'browse-url)
(require 'org-roam)
(require 'autoslip-roam)
(require 'autoslip-roam-nav)

(defgroup autoslip-roam-html nil
  "Browser dashboard for autoslip-roam."
  :group 'autoslip-roam
  :prefix "autoslip-roam-html-")

(defcustom autoslip-roam-html-file
  (locate-user-emacs-file "autoslip-roam-index.html")
  "File that the dashboard is written to."
  :type 'file
  :group 'autoslip-roam-html)

(defcustom autoslip-roam-html-title "Autoslip index"
  "Title shown at the top of the dashboard."
  :type 'string
  :group 'autoslip-roam-html)

(defcustom autoslip-roam-html-link-type 'org-protocol
  "How a note in the dashboard links back to the note itself.
With `org-protocol', a click opens the note in Emacs.  This needs
`org-roam-protocol', a running Emacs server, and an operating system
that hands org-protocol links to emacsclient.  With `file', the link
points to the Org file on disk.  With nil, the notes are not links."
  :type '(choice (const :tag "Open in Emacs with org-protocol" org-protocol)
                 (const :tag "Link to the Org file" file)
                 (const :tag "No links" nil))
  :group 'autoslip-roam-html)

;;; ============================================================================
;;; HTML pieces
;;; ============================================================================

(defun autoslip-roam-html--escape (text)
  "Return TEXT with the characters that are special in HTML replaced."
  (let ((text (or text "")))
    (dolist (pair '(("&" . "&amp;") ("<" . "&lt;") (">" . "&gt;")
                    ("\"" . "&quot;"))
                  text)
      (setq text (replace-regexp-in-string
                  (regexp-quote (car pair)) (cdr pair) text t t)))))

(defun autoslip-roam-html--href (node)
  "Return the link target for NODE, or nil when notes are not links."
  (pcase autoslip-roam-html-link-type
    ('org-protocol
     (when-let* ((id (org-roam-node-id node)))
       (concat "org-protocol://roam-node?node=" (url-hexify-string id))))
    ('file
     (when-let* ((file (org-roam-node-file node)))
       (concat "file://" (mapconcat #'url-hexify-string
                                    (split-string (expand-file-name file) "/")
                                    "/"))))
    (_ nil)))

(defun autoslip-roam-html--split-title (address title)
  "Return (ADDRESS-TEXT . REST) for a note with ADDRESS and TITLE.
REST is TITLE without the address when the title begins with it.  A
title that begins with a bare integer, such as \"001 Topic\", is split
after the integer, although its address is \"001.\"."
  (let ((title (string-trim (or title "")))
        (bare (string-remove-suffix "." address)))
    (cond
     ((string-prefix-p address title)
      (cons address (string-trim (substring title (length address)))))
     ((string-prefix-p (concat bare " ") title)
      (cons bare (string-trim (substring title (length bare)))))
     (t (cons address title)))))

(defun autoslip-roam-html--count-descendants (address)
  "Return the number of notes below ADDRESS at every level."
  (let ((children (autoslip-roam-nav--children-of address)))
    (apply #'+ (length children)
           (mapcar #'autoslip-roam-html--count-descendants children))))

(defun autoslip-roam-html--label (address)
  "Return the HTML for the address and title of the note with ADDRESS."
  (let* ((node (autoslip-roam-nav--node address))
         (parts (autoslip-roam-html--split-title
                 address (and node (org-roam-node-title node))))
         (href (and node (autoslip-roam-html--href node)))
         (text (autoslip-roam-html--escape (cdr parts))))
    (concat
     "<span class=\"addr\">" (autoslip-roam-html--escape (car parts))
     "</span> "
     (if href
         (format "<a class=\"title\" href=\"%s\">%s</a>"
                 (autoslip-roam-html--escape href) text)
       (format "<span class=\"title\">%s</span>" text)))))

(defun autoslip-roam-html--insert-node (address depth)
  "Insert the list item for ADDRESS at DEPTH, with its children."
  (let ((children (autoslip-roam-nav--children-of address))
        (indent (make-string (* 2 depth) ?\s))
        (key (autoslip-roam-html--escape address)))
    (if (null children)
        (insert indent "<li class=\"n leaf\" data-a=\"" key "\">"
                "<div class=\"row\">"
                (autoslip-roam-html--label address)
                "</div></li>\n")
      (insert indent "<li class=\"n\" data-a=\"" key "\"><details>"
              "<summary>" (autoslip-roam-html--label address)
              (format " <span class=\"count\">%d</span>"
                      (autoslip-roam-html--count-descendants address))
              "</summary>\n"
              indent "<ul>\n")
      (dolist (child children)
        (autoslip-roam-html--insert-node child (1+ depth)))
      (insert indent "</ul></details></li>\n"))))

(defun autoslip-roam-html--insert-tree (addresses)
  "Insert a nested list for ADDRESSES and everything below them."
  (insert "<ul class=\"tree\">\n")
  (dolist (address addresses)
    (autoslip-roam-html--insert-node address 1))
  (insert "</ul>\n"))

(defconst autoslip-roam-html--style "
:root { --bg:#fbfaf7; --fg:#1f2328; --muted:#6b7280; --line:#e5e2da;
        --accent:#0b5cad; --chip:#eef2f7; --hit:#fff3bf; }
@media (prefers-color-scheme: dark) {
  :root { --bg:#16181c; --fg:#e6e6e6; --muted:#9aa0a6; --line:#2c3036;
          --accent:#7ab7ff; --chip:#23272e; --hit:#5c4a00; }
}
* { box-sizing: border-box; }
body { margin:0; background:var(--bg); color:var(--fg);
       font:16px/1.5 -apple-system, 'Segoe UI', Helvetica, Arial, sans-serif; }
main { max-width:60rem; margin:0 auto; padding:1.5rem 1.25rem 4rem; }
h1 { font-size:1.6rem; margin:0 0 .25rem; }
h2 { font-size:1.1rem; margin:2rem 0 .5rem; padding-top:1rem;
     border-top:1px solid var(--line); }
.meta { color:var(--muted); font-size:.9rem; margin:0 0 1rem; }
.bar { position:sticky; top:0; background:var(--bg); padding:.6rem 0;
       display:flex; gap:.5rem; flex-wrap:wrap; align-items:center;
       border-bottom:1px solid var(--line); z-index:1; }
.bar input { flex:1 1 16rem; padding:.45rem .6rem; font:inherit;
       color:var(--fg); background:var(--bg); border:1px solid var(--line);
       border-radius:.4rem; }
.bar button { padding:.45rem .7rem; font:inherit; color:var(--fg);
       background:var(--chip); border:1px solid var(--line);
       border-radius:.4rem; cursor:pointer; }
.bar .hits { color:var(--muted); font-size:.9rem; min-width:6rem; }
ul.tree, ul.tree ul { list-style:none; margin:0; padding:0; }
ul.tree ul { margin-left:.7rem; padding-left:.9rem;
       border-left:1px solid var(--line); }
li.n { margin:.1rem 0; }
summary, .row { padding:.15rem .3rem; border-radius:.3rem; }
summary { cursor:pointer; }
summary:hover, .row:hover { background:var(--chip); }
li.leaf > .row { margin-left:1.05rem; }
.addr { font:600 .85rem ui-monospace, SFMono-Regular, Menlo, monospace;
       background:var(--chip); border:1px solid var(--line);
       border-radius:.3rem; padding:.05rem .35rem; }
a.title { color:var(--accent); text-decoration:none; }
a.title:hover { text-decoration:underline; }
.count { color:var(--muted); font-size:.8rem; margin-left:.25rem; }
li.hit > details > summary .title, li.hit > .row .title {
       background:var(--hit); }
li.hidden { display:none; }
@media print { .bar { display:none; } details > ul { display:block; } }
"
  "Style sheet of the dashboard.")

(defconst autoslip-roam-html--script "
(function () {
  var KEY = 'autoslip-roam-open';
  var box = document.getElementById('q');
  var hits = document.getElementById('hits');
  var all = Array.prototype.slice.call(document.querySelectorAll('details'));
  function load() {
    try { return JSON.parse(localStorage.getItem(KEY) || '[]'); }
    catch (e) { return []; }
  }
  function save() {
    if (box.value) { return; }
    var open = [];
    all.forEach(function (d) {
      if (d.open && d.parentNode.dataset.a) { open.push(d.parentNode.dataset.a); }
    });
    try { localStorage.setItem(KEY, JSON.stringify(open)); } catch (e) {}
  }
  function restore() {
    var open = load();
    all.forEach(function (d) {
      d.open = open.indexOf(d.parentNode.dataset.a) !== -1;
    });
  }
  function text(li) {
    var row = li.querySelector(':scope > details > summary, :scope > .row');
    return row ? row.textContent.toLowerCase() : '';
  }
  function visit(li, q) {
    var self = text(li).indexOf(q) !== -1;
    var below = false;
    var kids = li.querySelectorAll(':scope > details > ul > li.n');
    Array.prototype.forEach.call(kids, function (kid) {
      if (visit(kid, q)) { below = true; }
    });
    li.classList.toggle('hit', self);
    li.classList.toggle('hidden', !(self || below));
    var d = li.querySelector(':scope > details');
    if (d) { d.open = below; }
    return self || below;
  }
  function filter() {
    var q = box.value.trim().toLowerCase();
    var tops = document.querySelectorAll('ul.tree > li.n');
    if (!q) {
      Array.prototype.forEach.call(document.querySelectorAll('li.n'),
        function (li) { li.classList.remove('hit', 'hidden'); });
      restore();
      hits.textContent = '';
      return;
    }
    Array.prototype.forEach.call(tops, function (li) { visit(li, q); });
    var n = document.querySelectorAll('li.hit').length;
    hits.textContent = n + (n === 1 ? ' match' : ' matches');
  }
  function setAll(open) {
    all.forEach(function (d) { d.open = open; });
    save();
  }
  restore();
  all.forEach(function (d) { d.addEventListener('toggle', save); });
  box.addEventListener('input', filter);
  document.getElementById('open').addEventListener('click',
    function () { setAll(true); });
  document.getElementById('close').addEventListener('click',
    function () { setAll(false); });
  document.addEventListener('keydown', function (e) {
    if (e.key === '/' && document.activeElement !== box) {
      e.preventDefault(); box.focus();
    } else if (e.key === 'Escape') {
      box.value = ''; filter(); box.blur();
    }
  });
})();
"
  "Script of the dashboard.")

;;; ============================================================================
;;; Page
;;; ============================================================================

(defun autoslip-roam-html-render ()
  "Return the dashboard as a string of HTML.
The lookup tables of autoslip-roam-nav must have been built."
  (let* ((roots (autoslip-roam-nav--children-of nil))
         (orphans (autoslip-roam-nav--children-of :orphans))
         (title (autoslip-roam-html--escape autoslip-roam-html-title)))
    (with-temp-buffer
      (insert "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n"
              "<meta charset=\"utf-8\">\n"
              "<meta name=\"viewport\" content=\"width=device-width, "
              "initial-scale=1\">\n"
              "<title>" title "</title>\n"
              "<style>" autoslip-roam-html--style "</style>\n"
              "</head>\n<body>\n<main>\n"
              "<h1>" title "</h1>\n"
              (format "<p class=\"meta\">%d roots, %d notes with an address, %d notes without a parent note. Written %s.</p>\n"
                      (length roots)
                      (hash-table-count autoslip-roam-nav--index)
                      (length orphans)
                      (format-time-string "%Y-%m-%d %H:%M"))
              "<div class=\"bar\">\n"
              "<input id=\"q\" type=\"search\" autocomplete=\"off\" "
              "placeholder=\"Filter notes (press / to start, Esc to clear)\" "
              "aria-label=\"Filter notes\">\n"
              "<span id=\"hits\" class=\"hits\"></span>\n"
              "<button id=\"open\" type=\"button\">Unfold all</button>\n"
              "<button id=\"close\" type=\"button\">Fold all</button>\n"
              "</div>\n"
              "<h2>Roots</h2>\n")
      (if roots
          (autoslip-roam-html--insert-tree roots)
        (insert "<p class=\"meta\">No root notes were found. A root has a "
                "title that begins with an integer and a period.</p>\n"))
      (when orphans
        (insert "<h2>Notes without a parent note</h2>\n")
        (autoslip-roam-html--insert-tree orphans))
      (insert "</main>\n<script>" autoslip-roam-html--script "</script>\n"
              "</body>\n</html>\n")
      (buffer-string))))

;;;###autoload
(defun autoslip-roam-html-export (&optional file)
  "Write the dashboard to FILE and return the file name.
FILE defaults to `autoslip-roam-html-file'.  Interactively, a prefix
argument asks for the file."
  (interactive
   (list (and current-prefix-arg
              (read-file-name "Write the dashboard to: "
                              (file-name-directory autoslip-roam-html-file)
                              nil nil
                              (file-name-nondirectory
                               autoslip-roam-html-file)))))
  (let ((file (expand-file-name (or file autoslip-roam-html-file)))
        (coding-system-for-write 'utf-8-unix))
    (autoslip-roam--maybe-sync-db)
    (autoslip-roam-nav--build-index)
    (make-directory (file-name-directory file) t)
    (with-temp-file file
      (insert (autoslip-roam-html-render)))
    (when (called-interactively-p 'interactive)
      (message "Wrote %s" (abbreviate-file-name file)))
    file))

;;;###autoload
(defun autoslip-roam-html-open (&optional file)
  "Write the dashboard to FILE and open it in the web browser.
FILE defaults to `autoslip-roam-html-file'."
  (interactive)
  (let ((file (autoslip-roam-html-export file)))
    (browse-url-of-file file)
    file))

(provide 'autoslip-roam-html)

;;; autoslip-roam-html.el ends here
