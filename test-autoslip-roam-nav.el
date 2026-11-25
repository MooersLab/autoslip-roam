;;; test-autoslip-roam-nav.el --- Tests for autoslip-roam-nav -*- lexical-binding: t; -*-

;;; Commentary:

;; Tests for autoslip-roam-nav.el using ERT.  The org-roam node list is
;; replaced by mock nodes, so no database is needed.
;;
;; Run with:
;;   make test-nav

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'autoslip-roam)
(require 'autoslip-roam-nav)

(defvar test-autoslip-roam-nav--titles
  '("1. Crystallography"
    "1.1 Data collection"
    "1.2 Phasing"
    "1.2a Molecular replacement"
    "1.2b Experimental phasing"
    "1.2b1 SAD"
    "1.2b2 MAD"
    "1.14 Charge density"
    "2. RNA structure"
    "2.1 Tetraloops"
    "00.0 Index of index")
  "Titles of the mock vault.")

(defmacro test-autoslip-roam-nav--with-vault (titles &rest body)
  "Run BODY with mock nodes that have TITLES and a fresh index."
  (declare (indent 1))
  `(let ((autoslip-roam-nav--index nil)
         (autoslip-roam-nav--children nil)
         (autoslip-roam-nav--current nil)
         (autoslip-roam-nav--page 0)
         (autoslip-roam-sync-db-before-queries nil))
     (cl-letf (((symbol-function 'org-roam-node-list)
                (lambda ()
                  (mapcar (lambda (title)
                            (org-roam-node-create
                             :id (concat "id-" title) :title title
                             :file (concat "/tmp/" title ".org") :point 1))
                          ,titles))))
       (autoslip-roam-nav--build-index)
       ,@body)))

(ert-deftest test-nav-top-lists-roots-and-orphans ()
  "The first screen lists the roots and the notes without a parent note."
  (test-autoslip-roam-nav--with-vault test-autoslip-roam-nav--titles
    (should (equal (autoslip-roam-nav--children-of nil)
                   '("00.0" "1." "2.")))))

(ert-deftest test-nav-children-are-sorted-numerically ()
  "Children are sorted by address, so 1.2 comes before 1.14."
  (test-autoslip-roam-nav--with-vault test-autoslip-roam-nav--titles
    (should (equal (autoslip-roam-nav--children-of "1.")
                   '("1.1" "1.2" "1.14")))
    (should (equal (autoslip-roam-nav--children-of "1.2")
                   '("1.2a" "1.2b")))
    (should-not (autoslip-roam-nav--children-of "1.2a"))))

(ert-deftest test-nav-chain-and-parent ()
  "The chain runs from the root down to the note."
  (test-autoslip-roam-nav--with-vault test-autoslip-roam-nav--titles
    (should (equal (autoslip-roam-nav--chain "1.2b2")
                   '("1." "1.2" "1.2b" "1.2b2")))
    (should (equal (autoslip-roam-nav--parent "1.2b") "1.2"))
    (should-not (autoslip-roam-nav--parent "1."))
    ;; The parent 00. does not exist, so 00.0 has no parent in the menu.
    (should-not (autoslip-roam-nav--parent "00.0"))
    (should (equal (autoslip-roam-nav--chain "00.0") '("00.0")))))

(ert-deftest test-nav-siblings ()
  "Previous and next siblings follow the sorted order."
  (test-autoslip-roam-nav--with-vault test-autoslip-roam-nav--titles
    (should (equal (autoslip-roam-nav--neighbor "1.2" -1) "1.1"))
    (should (equal (autoslip-roam-nav--neighbor "1.2" 1) "1.14"))
    (should-not (autoslip-roam-nav--neighbor "1.1" -1))
    (should-not (autoslip-roam-nav--neighbor "1.14" 1))
    (should (equal (autoslip-roam-nav--neighbor "1." 1) "2."))))

(ert-deftest test-nav-keys-from-address-ends ()
  "Unambiguous address ends are used as keys."
  (test-autoslip-roam-nav--with-vault test-autoslip-roam-nav--titles
    (should (equal (autoslip-roam-nav--assign-keys '("1.2a" "1.2b") "1.2")
                   '(("a" . "1.2a") ("b" . "1.2b"))))
    (should (equal (autoslip-roam-nav--assign-keys '("1.2b1" "1.2b2") "1.2b")
                   '(("1" . "1.2b1") ("2" . "1.2b2"))))))

(ert-deftest test-nav-keys-are-padded-when-one-starts-another ()
  "Keys are padded when one key would be the start of another."
  (test-autoslip-roam-nav--with-vault test-autoslip-roam-nav--titles
    (should (equal (mapcar #'car (autoslip-roam-nav--assign-keys
                                  '("1.1" "1.2" "1.14") "1."))
                   '("01" "02" "14")))
    (should (equal (mapcar #'car (autoslip-roam-nav--assign-keys
                                  '("1.2a" "1.2z" "1.2aa") "1.2"))
                   '("-a" "-z" "aa")))))

(ert-deftest test-nav-keys-fall-back-to-numbers ()
  "Entries are numbered when the address ends cannot serve as keys."
  (test-autoslip-roam-nav--with-vault test-autoslip-roam-nav--titles
    (should (equal (mapcar #'car (autoslip-roam-nav--assign-keys
                                  '("00.0" "1." "2.") nil))
                   '("1" "2" "3")))
    ;; 0. and 00. would both be padded to 00.
    (should (equal (mapcar #'car (autoslip-roam-nav--assign-keys
                                  '("0." "00.") nil))
                   '("1" "2")))))

(ert-deftest test-nav-key-string ()
  "A key of several characters is read as a sequence of keys."
  (should (equal (autoslip-roam-nav--key-string "14") "1 4"))
  (should (equal (kbd (autoslip-roam-nav--key-string "-a")) (kbd "- a"))))

(ert-deftest test-nav-paging ()
  "Children beyond the page size go to later pages."
  (test-autoslip-roam-nav--with-vault
      (cons "1. Root" (cl-loop for i from 1 to 7
                               collect (format "1.%d Child %d" i i)))
    (let ((autoslip-roam-nav-page-size 3)
          (autoslip-roam-nav--current "1."))
      (should (= (autoslip-roam-nav--page-count) 3))
      (should (equal (mapcar #'cdr (autoslip-roam-nav--page-entries))
                     '("1.1" "1.2" "1.3")))
      (setq autoslip-roam-nav--page 2)
      (should (equal (autoslip-roam-nav--page-entries)
                     '(("7" . "1.7")))))))

(ert-deftest test-nav-header-shows-chain ()
  "The heading lists the chain with the current note last."
  (test-autoslip-roam-nav--with-vault test-autoslip-roam-nav--titles
    (should (string-match-p "Autoslip roots (11 notes"
                            (autoslip-roam-nav--header)))
    (setq autoslip-roam-nav--current "1.2b")
    (let ((lines (split-string (substring-no-properties
                                (autoslip-roam-nav--header))
                               "\n")))
      (should (equal lines '("Chain of thought"
                             "1. Crystallography"
                             "  1.2 Phasing"
                             "    1.2b Experimental phasing"))))))

(ert-deftest test-nav-duplicate-address-keeps-one-note ()
  "An address that is used twice appears once."
  (test-autoslip-roam-nav--with-vault '("1. Root" "1.1 First" "1.1 Second")
    (should (equal (autoslip-roam-nav--children-of "1.") '("1.1")))))

(ert-deftest test-nav-child-specs-parse ()
  "The entries for the children are accepted by transient."
  (test-autoslip-roam-nav--with-vault test-autoslip-roam-nav--titles
    (setq autoslip-roam-nav--current "1.")
    (let ((specs (autoslip-roam-nav--child-specs)))
      (should (equal (mapcar #'car specs) '("0 1" "0 2" "1 4")))
      (should (equal (mapcar #'cadr specs)
                     '("1.1 Data collection" "1.2 Phasing"
                       "1.14 Charge density")))
      (should (= (length (autoslip-roam-nav--setup-children nil)) 3))
      ;; The third entry on the page leads to 1.14.
      (cl-letf (((symbol-function 'autoslip-roam-nav--redisplay) #'ignore))
        (funcall (nth 2 (nth 2 specs)))
        (should (equal autoslip-roam-nav--current "1.14"))))))

(ert-deftest test-nav-moving-changes-state ()
  "The commands change the current note and draw the menu again."
  (test-autoslip-roam-nav--with-vault test-autoslip-roam-nav--titles
    (let ((redraws 0))
      (cl-letf (((symbol-function 'autoslip-roam-nav--redisplay)
                 (lambda () (cl-incf redraws))))
        (autoslip-roam-nav--goto "1.2b")
        (should (equal autoslip-roam-nav--current "1.2b"))
        (autoslip-roam-nav-previous-sibling)
        (should (equal autoslip-roam-nav--current "1.2a"))
        (autoslip-roam-nav-previous-sibling)
        (should (equal autoslip-roam-nav--current "1.2a"))
        (autoslip-roam-nav-next-sibling)
        (should (equal autoslip-roam-nav--current "1.2b"))
        (autoslip-roam-nav-up)
        (should (equal autoslip-roam-nav--current "1.2"))
        (autoslip-roam-nav-up)
        (autoslip-roam-nav-up)
        (should-not autoslip-roam-nav--current)
        (autoslip-roam-nav--goto "2.1")
        (autoslip-roam-nav-top)
        (should-not autoslip-roam-nav--current)
        (should (= redraws 9))))))

(ert-deftest test-nav-menu-opens ()
  "The command builds the menu from the roots and from a note."
  (test-autoslip-roam-nav--with-vault test-autoslip-roam-nav--titles
    (unwind-protect
        (progn
          (autoslip-roam-nav t)
          (should (eq (oref transient--prefix command) 'autoslip-roam-nav))
          (should-not autoslip-roam-nav--current)
          (transient-quit-all)
          (autoslip-roam-nav--goto "1.2")
          (should (eq (oref transient--prefix command) 'autoslip-roam-nav))
          (should (equal autoslip-roam-nav--current "1.2")))
      (ignore-errors (transient-quit-all)))))

(provide 'test-autoslip-roam-nav)

;;; test-autoslip-roam-nav.el ends here
