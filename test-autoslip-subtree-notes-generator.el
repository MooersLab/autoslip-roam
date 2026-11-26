;;; test-autoslip-subtree-notes-generator.el --- Tests -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for autoslip-subtree-notes-generator.el using ERT.  Each test
;; works in a fresh temporary directory.  The org-roam node list is built
;; from the files in that directory, so no database is needed.
;;
;; Run with:
;;   emacs -Q --batch -L . -L <org-roam and its dependencies> \
;;     -l test-autoslip-subtree-notes-generator.el \
;;     -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'autoslip-roam)
(require 'autoslip-subtree-notes-generator)

(defconst test-asng--parent-id "11111111-1111-4111-8111-111111111111")

(defconst test-asng--parent-text
  (concat ":PROPERTIES:\n:ID:       " test-asng--parent-id "\n:END:\n"
          "#+title: 7. Crystallography\n\nSome text.\n\n"
          "* 7. Crystallography\n"
          "** 7.1 Crystal growth\n#+LATEX: \\index{crystallization}\n"
          "*** 7.1a Vapor diffusion\n"
          "**** 7.1a1 Hanging drop\n"
          "*** 7.1b Screening strategies\n"
          "** 7.2 Symmetry and space groups\n"
          "** 8.1 Stray headline\n"
          "** 7.2.3 Bad address\n"
          "* Notes\n"))

(defun test-asng--nodes (dir)
  "Return one org-roam node for each Org file in DIR."
  (delq nil
        (mapcar
         (lambda (file)
           (with-temp-buffer
             (insert-file-contents file)
             (let ((case-fold-search t) id title)
               (when (re-search-forward "^:ID:[ \t]+\\(\\S-+\\)" nil t)
                 (setq id (match-string 1)))
               (goto-char (point-min))
               (when (re-search-forward "^#\\+title:[ \t]*\\(.*\\)$" nil t)
                 (setq title (match-string 1)))
               (when (and id title)
                 (org-roam-node-create :id id :title title :file file)))))
         (directory-files dir t "\\.org\\'"))))

(defmacro test-asng--with-vault (parent-name &rest body)
  "Run BODY in the buffer of a parent note named PARENT-NAME in a new vault.
The variable `dir' is bound to the vault directory."
  (declare (indent 1))
  `(let* ((dir (file-name-as-directory (make-temp-file "asng" t)))
          (parent (expand-file-name ,parent-name dir))
          (autoslip-roam-sync-db-before-queries nil)
          (autoslip-roam-link-storage 'headings)
          (autoslip-subtree-notes-generator-templates-directory nil)
          (org-id-locations-file (expand-file-name ".ids" dir))
          (org-id-track-globally nil)
          (create-lockfiles nil))
     (unwind-protect
         (cl-letf (((symbol-function 'org-roam-node-list)
                    (lambda () (test-asng--nodes dir)))
                   ((symbol-function 'org-roam-db-update-file) #'ignore)
                   ((symbol-function 'org-roam-db-sync) #'ignore))
           (with-temp-file parent (insert test-asng--parent-text))
           (with-current-buffer (find-file-noselect parent)
             (unwind-protect
                 (progn ,@body)
               (set-buffer-modified-p nil)
               (kill-buffer))))
       (dolist (buffer (buffer-list))
         (when (and (buffer-file-name buffer)
                    (string-prefix-p dir (buffer-file-name buffer)))
           (with-current-buffer buffer (set-buffer-modified-p nil))
           (kill-buffer buffer)))
       (delete-directory dir t))))

(defun test-asng--file-of (dir address)
  "Return the file in DIR whose note has ADDRESS."
  (cl-loop for node in (test-asng--nodes dir)
           when (equal address (autoslip-roam--extract-from-title
                                (org-roam-node-title node)))
           return (org-roam-node-file node)))

(defun test-asng--text (file)
  "Return the text of FILE."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(ert-deftest test-asng-address ()
  "Addresses are canonical and bad ones are refused."
  (should (equal "7." (autoslip-subtree-notes-generator--address "7")))
  (should (equal "7." (autoslip-subtree-notes-generator--address "7.")))
  (should (equal "7.1a" (autoslip-subtree-notes-generator--address "7.1a")))
  (should-not (autoslip-subtree-notes-generator--address "7.2.3"))
  (should-not (autoslip-subtree-notes-generator--address "7.2A"))
  (should-not (autoslip-subtree-notes-generator--address "00.0"))
  (should-not (autoslip-subtree-notes-generator--address "Notes")))

(ert-deftest test-asng-read-outline ()
  "Only valid headlines below the parent are read, in folgezettel order."
  (test-asng--with-vault "7_crystallography.org"
    (let ((items (autoslip-subtree-notes-generator--read-outline "7.")))
      (should (equal '("7.1" "7.1a" "7.1a1" "7.1b" "7.2")
                     (mapcar (lambda (i) (plist-get i :address)) items)))
      (should (equal "Crystal growth" (plist-get (car items) :heading)))
      (should (equal '("#+LATEX: \\index{crystallization}")
                     (plist-get (car items) :keys))))))

(ert-deftest test-asng-plan-kinds ()
  "The kind follows the level of the address and the last kind repeats."
  (test-asng--with-vault "7_crystallography.org"
    (cl-letf (((symbol-function 'autoslip-subtree-notes-generator--template)
               (lambda (_kind) (cons "" ""))))
      (let* ((plan (autoslip-subtree-notes-generator-generate
                    '("hub" "plain") nil t))
             (kinds (mapcar (lambda (n) (cons (plist-get n :address)
                                              (plist-get n :kind)))
                            (plist-get plan :new))))
        (should (equal "hub" (cdr (assoc "7.1" kinds))))
        (should (equal "plain" (cdr (assoc "7.1a" kinds))))
        (should (equal "plain" (cdr (assoc "7.1a1" kinds))))
        (should (equal "hub" (cdr (assoc "7.2" kinds))))
        ;; A dry run writes nothing.
        (should (= 1 (length (directory-files dir nil "\\.org\\'"))))))))

(ert-deftest test-asng-generate-notes ()
  "Notes are written with the title, ten blank lines, and both links."
  (test-asng--with-vault "7_crystallography.org"
    (let ((files (autoslip-subtree-notes-generator-generate nil t)))
      (should (= 5 (length files)))
      (let* ((file (test-asng--file-of dir "7.1"))
             (text (test-asng--text file))
             (id-7.1 (progn (string-match ":ID:[ \t]+\\(\\S-+\\)" text)
                            (match-string 1 text))))
        (should (equal "7_1_crystal_growth.org" (file-name-nondirectory file)))
        ;; Title, index line, exactly ten blank lines, parent heading.
        (should (string-match-p
                 (concat "#\\+title: 7\\.1 Crystal growth\n"
                         "#\\+LATEX: \\\\index{crystallization}\n"
                         "\n\\{10\\}\\* Parent Note\n"
                         "\\[\\[id:" test-asng--parent-id "\\]\\[Parent note\\]\\]\n")
                 text))
        (should-not (string-match-p "\n\\{12\\}\\* Parent Note" text))
        ;; The new parent lists its own children.
        (should (string-match-p
                 "\\* Child Notes\n\\[\\[id:[^]]+\\]\\[7\\.1a Vapor diffusion\\]\\]\n\\[\\[id:[^]]+\\]\\[7\\.1b Screening strategies\\]\\]"
                 text))
        ;; A grandchild links back to the new note, not to the root.
        (should (string-match-p
                 (concat "\\* Parent Note\n\\[\\[id:" id-7.1 "\\]")
                 (test-asng--text (test-asng--file-of dir "7.1a")))))
      ;; The plain note without index lines: title, ten blank lines, heading.
      (should (string-match-p
               "#\\+title: 7\\.2 Symmetry and space groups\n\n\\{10\\}\\* Parent Note\n"
               (test-asng--text (test-asng--file-of dir "7.2"))))
      ;; The parent note got its forward links, in order.
      (should (string-match-p
               "\\* Child Notes\n\\[\\[id:[^]]+\\]\\[7\\.1 Crystal growth\\]\\]\n\\[\\[id:[^]]+\\]\\[7\\.2 Symmetry and space groups\\]\\]\n"
               (buffer-string)))
      ;; The package itself finds nothing to repair.
      (should-not (autoslip-roam--find-missing-links)))))

(ert-deftest test-asng-second-run-writes-nothing ()
  "A second run skips every address and adds no link."
  (test-asng--with-vault "7_crystallography.org"
    (autoslip-subtree-notes-generator-generate nil t)
    (let ((before (buffer-string))
          (count (length (directory-files dir nil "\\.org\\'"))))
      (should-not (autoslip-subtree-notes-generator-generate nil t))
      (should (equal before (buffer-string)))
      (should (= count (length (directory-files dir nil "\\.org\\'"))))
      (let ((plan (autoslip-subtree-notes-generator-generate nil nil t)))
        (should (= 5 (length (plist-get plan :skipped))))))))

(ert-deftest test-asng-timestamp-file-names ()
  "A parent with a timestamp gives children with timestamps."
  (test-asng--with-vault "20261101120000-7_crystallography.org"
    (let ((files (autoslip-subtree-notes-generator-generate nil t)))
      (dolist (file files)
        (should (string-match-p "\\`[0-9]\\{14\\}-7_"
                                (file-name-nondirectory file))))
      (should (= 5 (length (delete-dups (copy-sequence files))))))))

(ert-deftest test-asng-orphan-stops ()
  "A headline without a parent note stops the command before any write."
  (test-asng--with-vault "7_crystallography.org"
    (goto-char (point-max))
    (insert "*** 7.5a Orphan\n")
    (should-error (autoslip-subtree-notes-generator-generate nil t)
                  :type 'user-error)
    (should (= 1 (length (directory-files dir nil "\\.org\\'"))))))

(ert-deftest test-asng-duplicate-stops ()
  "An address that appears twice in the outline is an error."
  (test-asng--with-vault "7_crystallography.org"
    (goto-char (point-max))
    (insert "** 7.2 Again\n")
    (should-error (autoslip-subtree-notes-generator-generate nil t)
                  :type 'user-error)))

(ert-deftest test-asng-template ()
  "Template keyword lines go above the blank lines and headings below."
  (test-asng--with-vault "7_crystallography.org"
    (let ((autoslip-subtree-notes-generator-templates-directory
           (expand-file-name "templates" dir)))
      (make-directory autoslip-subtree-notes-generator-templates-directory)
      (with-temp-file (expand-file-name
                       "hub.org"
                       autoslip-subtree-notes-generator-templates-directory)
        (insert "#+filetags: :hub:\n* Overview of ${heading}\n"))
      (autoslip-subtree-notes-generator-generate '("hub" "plain") t)
      (should (string-match-p
               (concat "#\\+filetags: :hub:\n\n\\{10\\}\\* Parent Note\n"
                       "\\[\\[id:[^]]+\\]\\[Parent note\\]\\]\n\n"
                       "\\* Overview of Symmetry and space groups\n")
               (test-asng--text (test-asng--file-of dir "7.2"))))
      ;; A missing template is an error.
      (should-error (autoslip-subtree-notes-generator-generate '("nokind") t)
                    :type 'user-error))))

(ert-deftest test-asng-parent-without-id ()
  "A parent note without an ID is refused from Lisp."
  (test-asng--with-vault "7_crystallography.org"
    (erase-buffer)
    (insert "#+title: 7. Crystallography\n** 7.1 Crystal growth\n")
    (should-error (autoslip-subtree-notes-generator-generate nil t)
                  :type 'user-error)))

(defconst test-asng--bare-parent-text
  (concat ":PROPERTIES:\n:ID:       " test-asng--parent-id "\n:END:\n"
          "#+title: 7. Crystallography\n\nSome text.\n")
  "A parent note without an outline.")

(defconst test-asng--outline-text
  (concat "* 7. Crystallography\n"
          "** 7.1 Crystal growth\n#+LATEX: \\index{crystallization}\n"
          "*** 7.1a Vapor diffusion\n"
          "** 7.2 Symmetry and space groups\n"
          "** 8.1 Stray headline\n")
  "An outline that is kept outside the parent note.")

(defun test-asng--check-separate-outline (dir)
  "Check the three notes written in DIR from `test-asng--outline-text'."
  (should (= 4 (length (directory-files dir nil "\\`[0-9].*\\.org\\'"))))
  (should (string-match-p
           (concat "#\\+title: 7\\.1 Crystal growth\n"
                   "#\\+LATEX: \\\\index{crystallization}\n"
                   "\n\\{10\\}\\* Parent Note\n"
                   "\\[\\[id:" test-asng--parent-id "\\]")
           (test-asng--text (test-asng--file-of dir "7.1"))))
  ;; The forward links go to the parent note, not to the outline source.
  (should (string-match-p
           "\\* Child Notes\n\\[\\[id:[^]]+\\]\\[7\\.1 Crystal growth\\]\\]\n\\[\\[id:[^]]+\\]\\[7\\.2 Symmetry and space groups\\]\\]\n"
           (buffer-string)))
  (should-not (autoslip-roam--find-missing-links)))

(ert-deftest test-asng-outline-from-file ()
  "The outline can be read from a separate file, which is left unchanged."
  (test-asng--with-vault "7_crystallography.org"
    (erase-buffer)
    (insert test-asng--bare-parent-text)
    (save-buffer)
    ;; The outline file has no .org ending, so it is not a note of the vault.
    (let ((outline (expand-file-name "outline.txt" dir)))
      (with-temp-file outline (insert test-asng--outline-text))
      ;; Without an outline in the note, the default source finds nothing.
      (should-error (autoslip-subtree-notes-generator-generate nil t)
                    :type 'user-error)
      (should (= 3 (length (autoslip-subtree-notes-generator-generate-from-file
                            outline nil t))))
      (test-asng--check-separate-outline dir)
      (should (equal test-asng--outline-text (test-asng--text outline)))
      ;; A second run from the same file writes nothing.
      (should-not (autoslip-subtree-notes-generator-generate-from-file
                   outline nil t)))))

(ert-deftest test-asng-outline-file-missing ()
  "An outline file that does not exist is an error."
  (test-asng--with-vault "7_crystallography.org"
    (should-error (autoslip-subtree-notes-generator-generate
                   nil t nil (expand-file-name "no-such-file.org" dir))
                  :type 'user-error)))

(ert-deftest test-asng-outline-from-clipboard ()
  "The outline can be read from the clipboard."
  (test-asng--with-vault "7_crystallography.org"
    (erase-buffer)
    (insert test-asng--bare-parent-text)
    (save-buffer)
    (cl-letf (((symbol-function 'current-kill)
               (lambda (&rest _) test-asng--outline-text)))
      (let ((plan (autoslip-subtree-notes-generator-generate-from-clipboard
                   nil nil t)))
        (should (equal "the clipboard" (plist-get plan :source)))
        (should (= 3 (length (plist-get plan :new)))))
      (should (= 3 (length
                    (autoslip-subtree-notes-generator-generate-from-clipboard
                     nil t))))
      (test-asng--check-separate-outline dir))))

(ert-deftest test-asng-clipboard-empty-or-unrelated ()
  "An empty clipboard and a clipboard without headlines are errors."
  (test-asng--with-vault "7_crystallography.org"
    (cl-letf (((symbol-function 'current-kill) (lambda (&rest _) "  \n")))
      (should-error (autoslip-subtree-notes-generator-generate-from-clipboard
                     nil t)
                    :type 'user-error))
    (cl-letf (((symbol-function 'current-kill)
               (lambda (&rest _) "Some text that is not an outline.\n")))
      (should-error (autoslip-subtree-notes-generator-generate-from-clipboard
                     nil t)
                    :type 'user-error))
    (should (= 1 (length (directory-files dir nil "\\.org\\'"))))))

(provide 'test-autoslip-subtree-notes-generator)

;;; test-autoslip-subtree-notes-generator.el ends here
