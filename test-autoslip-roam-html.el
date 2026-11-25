;;; test-autoslip-roam-html.el --- Tests for autoslip-roam-html -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for autoslip-roam-html.el using ERT.  The org-roam node list is
;; replaced by mock nodes, so no database is needed.
;;
;; Run with:
;;   make test-html

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'autoslip-roam)
(require 'autoslip-roam-nav)
(require 'autoslip-roam-html)

(defvar test-autoslip-roam-html--titles
  '("1. Crystallography"
    "1.1 Data collection"
    "1.2 Phasing <fast> & \"simple\""
    "1.2a Molecular replacement"
    "1.2b Experimental phasing"
    "1.2b1 SAD"
    "1.14 Charge density"
    "2. RNA structure"
    "001 Writing of papers"
    "7.3b Lost note")
  "Titles of the mock vault.")

(defmacro test-autoslip-roam-html--with-vault (&rest body)
  "Run BODY with the mock vault and fresh lookup tables."
  (declare (indent 0))
  `(let ((autoslip-roam-nav--index nil)
         (autoslip-roam-nav--children nil)
         (autoslip-roam-sync-db-before-queries nil)
         (autoslip-roam-html-link-type 'org-protocol))
     (cl-letf (((symbol-function 'org-roam-node-list)
                (lambda ()
                  (mapcar (lambda (title)
                            (org-roam-node-create
                             :id (concat "ID " (car (split-string title)))
                             :title title
                             :file (concat "/tmp/my notes/"
                                           (car (split-string title))
                                           ".org")
                             :point 1))
                          test-autoslip-roam-html--titles))))
       (autoslip-roam-nav--build-index)
       ,@body)))

(defun test-autoslip-roam-html--count (regexp string)
  "Return the number of matches of REGEXP in STRING."
  (let ((count 0) (start 0))
    (while (string-match regexp string start)
      (setq count (1+ count)
            start (match-end 0)))
    count))

(ert-deftest test-html-escape ()
  "Special characters are replaced, and the ampersand is done first."
  (should (equal (autoslip-roam-html--escape "a <b> & \"c\"")
                 "a &lt;b&gt; &amp; &quot;c&quot;"))
  (should (equal (autoslip-roam-html--escape nil) "")))

(ert-deftest test-html-split-title ()
  "The address is taken off the front of the title."
  (should (equal (autoslip-roam-html--split-title "1." "1. Crystallography")
                 '("1." . "Crystallography")))
  (should (equal (autoslip-roam-html--split-title "1.2a" "1.2a Molecular")
                 '("1.2a" . "Molecular")))
  (should (equal (autoslip-roam-html--split-title "001." "001 Writing")
                 '("001" . "Writing")))
  (should (equal (autoslip-roam-html--split-title "3." "Untitled 3")
                 '("3." . "Untitled 3"))))

(ert-deftest test-html-count-descendants ()
  "Notes below a note are counted at every level."
  (test-autoslip-roam-html--with-vault
    (should (= (autoslip-roam-html--count-descendants "1.") 6))
    (should (= (autoslip-roam-html--count-descendants "1.2") 3))
    (should (= (autoslip-roam-html--count-descendants "1.2a") 0))))

(ert-deftest test-html-links ()
  "The three kinds of link are built as documented."
  (test-autoslip-roam-html--with-vault
    (let ((node (autoslip-roam-nav--node "1.2a")))
      (should (equal (autoslip-roam-html--href node)
                     "org-protocol://roam-node?node=ID%201.2a"))
      (let ((autoslip-roam-html-link-type 'file))
        (should (equal (autoslip-roam-html--href node)
                       "file:///tmp/my%20notes/1.2a.org")))
      (let ((autoslip-roam-html-link-type nil))
        (should-not (autoslip-roam-html--href node))))))

(ert-deftest test-html-page-structure ()
  "The page lists the roots, nests the children, and escapes the titles."
  (test-autoslip-roam-html--with-vault
    (let ((html (autoslip-roam-html-render)))
      (should (string-prefix-p "<!DOCTYPE html>" html))
      (should (string-match-p "2 roots, 10 notes with an address, 2 notes without"
                              html))
      ;; Every note appears once.
      (should (= (test-autoslip-roam-html--count "<li class=\"n" html) 10))
      ;; Notes with children fold; the others do not.
      (should (= (test-autoslip-roam-html--count "<details>" html) 3))
      (should (= (test-autoslip-roam-html--count "</details>" html) 3))
      (should (= (test-autoslip-roam-html--count "<ul" html)
                 (test-autoslip-roam-html--count "</ul>" html)))
      ;; The title with special characters is escaped.
      (should (string-match-p
               "Phasing &lt;fast&gt; &amp; &quot;simple&quot;" html))
      (should-not (string-match-p "<fast>" html))
      ;; The root shows its address apart from the rest of its title.
      (should (string-match-p
               "<span class=\"addr\">1\\.</span> <a class=\"title\" href=\"org-protocol://roam-node\\?node=ID%201\\.\">Crystallography</a> <span class=\"count\">6</span>"
               html))
      ;; Children follow the numeric order: 1.1, 1.2, 1.14.
      (should (< (string-match "data-a=\"1\\.1\"" html)
                 (string-match "data-a=\"1\\.2\"" html)
                 (string-match "data-a=\"1\\.14\"" html)))
      ;; The roots come before the notes without a parent note.
      (should (< (string-match "<h2>Roots</h2>" html)
                 (string-match "data-a=\"2\\.\"" html)
                 (string-match "<h2>Notes without a parent note</h2>" html)
                 (string-match "data-a=\"001\\.\"" html))))))

(ert-deftest test-html-page-without-links ()
  "With no link type the page has no anchors."
  (test-autoslip-roam-html--with-vault
    (let* ((autoslip-roam-html-link-type nil)
           (html (autoslip-roam-html-render)))
      (should-not (string-match-p "<a " html))
      (should (string-match-p "<span class=\"title\">Crystallography</span>"
                              html)))))

(ert-deftest test-html-export-writes-file ()
  "The export command writes the page and returns the file name."
  (test-autoslip-roam-html--with-vault
    (let* ((dir (make-temp-file "autoslip-html-" t))
           (file (expand-file-name "sub/index.html" dir)))
      (unwind-protect
          (progn
            (should (equal (autoslip-roam-html-export file) file))
            (should (file-exists-p file))
            (with-temp-buffer
              (insert-file-contents file)
              (should (string-match-p "</html>\n\\'" (buffer-string)))))
        (delete-directory dir t)))))

(ert-deftest test-html-open-calls-browser ()
  "The open command hands the written file to the browser."
  (test-autoslip-roam-html--with-vault
    (let* ((dir (make-temp-file "autoslip-html-" t))
           (file (expand-file-name "index.html" dir))
           opened)
      (unwind-protect
          (cl-letf (((symbol-function 'browse-url-of-file)
                     (lambda (f) (setq opened f))))
            (autoslip-roam-html-open file)
            (should (equal opened file)))
        (delete-directory dir t)))))

(provide 'test-autoslip-roam-html)

;;; test-autoslip-roam-html.el ends here
