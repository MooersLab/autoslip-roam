;;; test-autoslip-roam.el --- Tests for autoslip-roam -*- lexical-binding: t; -*-

;; Copyright (C) 2025

;; Author: Blaine Mooers

;;; Commentary:

;; Comprehensive test suite for autoslip-roam.el using ERT.
;; Run all tests with: M-x ert RET t RET
;; Or from command line: emacs -batch -l ert -l autoslip-roam.el -l test-autoslip-roam.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Load the package being tested
(require 'autoslip-roam)

;;; ============================================================================
;;; Test Utilities and Mock Infrastructure
;;; ============================================================================

(defvar test-autoslip-roam--temp-dir nil
  "Temporary directory for test files.")

(defvar test-autoslip-roam--mock-nodes nil
  "List of mock nodes for testing.")

(defun test-autoslip-roam--create-mock-node (id title file)
  "Create a mock org-roam node with ID, TITLE, and FILE."
  (org-roam-node-create :id id :title title :file file))

(defmacro test-autoslip-roam--with-temp-dir (&rest body)
  "Execute BODY with a temporary directory set up and cleaned up."
  `(let ((test-autoslip-roam--temp-dir (make-temp-file "autoslip-test-" t)))
     (unwind-protect
         (progn ,@body)
       (when (and test-autoslip-roam--temp-dir
                  (file-exists-p test-autoslip-roam--temp-dir))
         (delete-directory test-autoslip-roam--temp-dir t)))))

(defmacro test-autoslip-roam--with-mock-nodes (nodes &rest body)
  "Execute BODY with NODES as the mock org-roam-node-list."
  `(cl-letf (((symbol-function 'org-roam-node-list) (lambda () ,nodes)))
     ,@body))

(defun test-autoslip-roam--create-temp-org-file (filename content)
  "Create a temporary org file with FILENAME and CONTENT."
  (let ((filepath (expand-file-name filename test-autoslip-roam--temp-dir)))
    (with-temp-file filepath
      (insert content))
    filepath))

;;; ============================================================================
;;; Unit Tests: autoslip-roam--parse-address
;;; ============================================================================

(ert-deftest test-parse-address-single-number ()
  "Test parsing root addresses (single numbers have no parent)."
  (should (equal nil (autoslip-roam--parse-address "1")))
  (should (equal nil (autoslip-roam--parse-address "7")))
  (should (equal nil (autoslip-roam--parse-address "42")))
  (should (equal nil (autoslip-roam--parse-address "123"))))

(ert-deftest test-parse-address-dot-number ()
  "Test parsing dot-number addresses."
  (should (equal "1" (autoslip-roam--parse-address "1.2")))
  (should (equal "1" (autoslip-roam--parse-address "1.13")))
  (should (equal "7" (autoslip-roam--parse-address "7.1")))
  (should (equal "42" (autoslip-roam--parse-address "42.99"))))

(ert-deftest test-parse-address-single-letter ()
  "Test parsing addresses ending with single letter."
  (should (equal "1.2" (autoslip-roam--parse-address "1.2a")))
  (should (equal "1.13" (autoslip-roam--parse-address "1.13b")))
  (should (equal "7.1" (autoslip-roam--parse-address "7.1z"))))

(ert-deftest test-parse-address-extended-letters ()
  "Test parsing addresses ending with extended letter sequences (aa, ab, etc.)."
  (should (equal "1.13" (autoslip-roam--parse-address "1.13aa")))
  (should (equal "1.13" (autoslip-roam--parse-address "1.13az")))
  (should (equal "1.13" (autoslip-roam--parse-address "1.13ba")))
  (should (equal "1.2" (autoslip-roam--parse-address "1.2aaa"))))

(ert-deftest test-parse-address-number-after-letter ()
  "Test parsing addresses ending with number after letter."
  (should (equal "1.2a" (autoslip-roam--parse-address "1.2a1")))
  (should (equal "1.2a" (autoslip-roam--parse-address "1.2a15")))
  (should (equal "1.13aa" (autoslip-roam--parse-address "1.13aa5"))))

(ert-deftest test-parse-address-complex-chains ()
  "Test parsing complex folgezettel chains."
  (should (equal "1.2a3" (autoslip-roam--parse-address "1.2a3b")))
  (should (equal "1.2a3b" (autoslip-roam--parse-address "1.2a3b4")))
  (should (equal "1.2a3c5" (autoslip-roam--parse-address "1.2a3c5d")))
  (should (equal "1.2a3c5d" (autoslip-roam--parse-address "1.2a3c5d7")))
  (should (equal "1.2a3c5d7" (autoslip-roam--parse-address "1.2a3c5d7a"))))

(ert-deftest test-parse-address-invalid-input ()
  "Test parsing invalid inputs."
  (should (equal nil (autoslip-roam--parse-address nil)))
  (should (equal nil (autoslip-roam--parse-address "")))
  (should (equal nil (autoslip-roam--parse-address "abc"))))

;;; ============================================================================
;;; Unit Tests: autoslip-roam--extract-from-title
;;; ============================================================================

(ert-deftest test-extract-from-title-basic ()
  "Test extracting folgezettel from basic titles."
  (should (equal "1" (autoslip-roam--extract-from-title "1 Introduction")))
  (should (equal "1.2" (autoslip-roam--extract-from-title "1.2 Methods")))
  (should (equal "1.2a" (autoslip-roam--extract-from-title "1.2a Details"))))

(ert-deftest test-extract-from-title-complex ()
  "Test extracting complex folgezettel from titles."
  (should (equal "1.13" (autoslip-roam--extract-from-title "1.13 Topic")))
  (should (equal "1.13aa" (autoslip-roam--extract-from-title "1.13aa Extended")))
  (should (equal "1.2a3c5d7a" (autoslip-roam--extract-from-title "1.2a3c5d7a Deep Chain"))))

(ert-deftest test-extract-from-title-address-only ()
  "Test extracting when title is just the address."
  (should (equal "7" (autoslip-roam--extract-from-title "7")))
  (should (equal "7.1" (autoslip-roam--extract-from-title "7.1")))
  (should (equal "7.1a" (autoslip-roam--extract-from-title "7.1a"))))

(ert-deftest test-extract-from-title-no-match ()
  "Test extraction when no folgezettel is present."
  (should (equal nil (autoslip-roam--extract-from-title "Introduction to Topic")))
  (should (equal nil (autoslip-roam--extract-from-title "Notes on Methods")))
  (should (equal nil (autoslip-roam--extract-from-title nil)))
  (should (equal nil (autoslip-roam--extract-from-title ""))))

(ert-deftest test-extract-from-title-embedded-numbers ()
  "Test extraction does not match embedded numbers incorrectly."
  ;; Should match the leading folgezettel only
  (should (equal "1" (autoslip-roam--extract-from-title "1 Chapter with 42 pages")))
  (should (equal "2.3" (autoslip-roam--extract-from-title "2.3 Analysis of Year 2024"))))

;;; ============================================================================
;;; Unit Tests: autoslip-roam--next-letter-sequence
;;; ============================================================================

(ert-deftest test-next-letter-sequence-basic ()
  "Test basic letter increment."
  (should (equal "b" (autoslip-roam--next-letter-sequence "a")))
  (should (equal "c" (autoslip-roam--next-letter-sequence "b")))
  (should (equal "z" (autoslip-roam--next-letter-sequence "y"))))

(ert-deftest test-next-letter-sequence-wraparound ()
  "Test letter wraparound from z to aa."
  (should (equal "aa" (autoslip-roam--next-letter-sequence "z"))))

(ert-deftest test-next-letter-sequence-double-letters ()
  "Test double letter sequences."
  (should (equal "ab" (autoslip-roam--next-letter-sequence "aa")))
  (should (equal "az" (autoslip-roam--next-letter-sequence "ay")))
  (should (equal "ba" (autoslip-roam--next-letter-sequence "az")))
  (should (equal "bb" (autoslip-roam--next-letter-sequence "ba"))))

(ert-deftest test-next-letter-sequence-zz-wraparound ()
  "Test wraparound from zz to aaa."
  (should (equal "aaa" (autoslip-roam--next-letter-sequence "zz"))))

(ert-deftest test-next-letter-sequence-triple-letters ()
  "Test triple letter sequences."
  (should (equal "aab" (autoslip-roam--next-letter-sequence "aaa")))
  (should (equal "baa" (autoslip-roam--next-letter-sequence "azz"))))

;;; ============================================================================
;;; Unit Tests: Validation Functions
;;; ============================================================================

(ert-deftest test-validate-no-multiple-periods-valid ()
  "Test that single or no period is valid."
  (should (equal nil (autoslip-roam--validate-no-multiple-periods "1")))
  (should (equal nil (autoslip-roam--validate-no-multiple-periods "1.2")))
  (should (equal nil (autoslip-roam--validate-no-multiple-periods "1.2a3b"))))

(ert-deftest test-validate-no-multiple-periods-invalid ()
  "Test that multiple periods are invalid."
  (should (stringp (autoslip-roam--validate-no-multiple-periods "1.2.3")))
  (should (stringp (autoslip-roam--validate-no-multiple-periods "1.2.3.4")))
  (should (string-match-p "Only one period" 
                          (autoslip-roam--validate-no-multiple-periods "1.2.3"))))

(ert-deftest test-validate-no-invalid-characters-valid ()
  "Test valid characters pass validation."
  (should (equal nil (autoslip-roam--validate-no-invalid-characters "1")))
  (should (equal nil (autoslip-roam--validate-no-invalid-characters "1.2")))
  (should (equal nil (autoslip-roam--validate-no-invalid-characters "1.2a3b4c")))
  (should (equal nil (autoslip-roam--validate-no-invalid-characters "42.99zz"))))

(ert-deftest test-validate-no-invalid-characters-uppercase ()
  "Test uppercase letters are invalid."
  (should (stringp (autoslip-roam--validate-no-invalid-characters "1.2A")))
  (should (stringp (autoslip-roam--validate-no-invalid-characters "1.2aB"))))

(ert-deftest test-validate-no-invalid-characters-special ()
  "Test special characters are invalid."
  (should (stringp (autoslip-roam--validate-no-invalid-characters "1.2a!")))
  (should (stringp (autoslip-roam--validate-no-invalid-characters "1/2")))
  (should (stringp (autoslip-roam--validate-no-invalid-characters "1,2")))
  (should (stringp (autoslip-roam--validate-no-invalid-characters "1*2")))
  (should (stringp (autoslip-roam--validate-no-invalid-characters "1?2"))))

(ert-deftest test-validate-alternation-pattern-valid ()
  "Test valid alternation patterns."
  (should (equal nil (autoslip-roam--validate-alternation-pattern "1")))
  (should (equal nil (autoslip-roam--validate-alternation-pattern "1.2")))
  (should (equal nil (autoslip-roam--validate-alternation-pattern "1.2a")))
  (should (equal nil (autoslip-roam--validate-alternation-pattern "1.2a3")))
  (should (equal nil (autoslip-roam--validate-alternation-pattern "1.2a3b")))
  (should (equal nil (autoslip-roam--validate-alternation-pattern "1.2aa")))
  (should (equal nil (autoslip-roam--validate-alternation-pattern "1.2aaa3bbb"))))

(ert-deftest test-validate-child-for-parent-number-parent ()
  "Test child validation when parent ends with number."
  ;; Valid: letter child
  (should (equal nil (autoslip-roam--validate-child-for-parent "1.2" "a")))
  (should (equal nil (autoslip-roam--validate-child-for-parent "1.2" "aa")))
  ;; Valid: dot-number child
  (should (equal nil (autoslip-roam--validate-child-for-parent "1" ".2")))
  ;; Invalid: bare number child (without dot)
  (should (stringp (autoslip-roam--validate-child-for-parent "1.2" "3"))))

(ert-deftest test-validate-child-for-parent-letter-parent ()
  "Test child validation when parent ends with letter."
  ;; Valid: number child
  (should (equal nil (autoslip-roam--validate-child-for-parent "1.2a" "1")))
  (should (equal nil (autoslip-roam--validate-child-for-parent "1.2a" "15")))
  ;; Invalid: letter child
  (should (stringp (autoslip-roam--validate-child-for-parent "1.2a" "b"))))

(ert-deftest test-validate-address-valid ()
  "Test complete address validation for valid addresses."
  (should (autoslip-roam-validate-address "1"))
  (should (autoslip-roam-validate-address "1.2"))
  (should (autoslip-roam-validate-address "1.2a"))
  (should (autoslip-roam-validate-address "1.2a3"))
  (should (autoslip-roam-validate-address "1.13aa"))
  (should (autoslip-roam-validate-address "42.99zz15")))

(ert-deftest test-validate-address-invalid ()
  "Test complete address validation for invalid addresses."
  (should (equal nil (autoslip-roam-validate-address nil)))
  (should (equal nil (autoslip-roam-validate-address "")))
  (should (equal nil (autoslip-roam-validate-address "1.2.3")))
  (should (equal nil (autoslip-roam-validate-address "1.2A")))
  (should (equal nil (autoslip-roam-validate-address "abc"))))

(ert-deftest test-validate-address-full-returns-errors ()
  "Test that validate-address-full returns error list for invalid addresses."
  (should (equal nil (autoslip-roam-validate-address-full "1.2a")))
  (should (listp (autoslip-roam-validate-address-full "1.2.3")))
  (should (listp (autoslip-roam-validate-address-full "1.2A")))
  (should (> (length (autoslip-roam-validate-address-full "1.2.3!A")) 1)))

(ert-deftest test-validate-new-child-valid ()
  "Test validation of valid parent-child relationships."
  (should (equal nil (autoslip-roam-validate-new-child "1" "1.1")))
  (should (equal nil (autoslip-roam-validate-new-child "1.2" "1.2a")))
  (should (equal nil (autoslip-roam-validate-new-child "1.2a" "1.2a1")))
  (should (equal nil (autoslip-roam-validate-new-child "1.13" "1.13aa"))))

(ert-deftest test-validate-new-child-invalid ()
  "Test validation of invalid parent-child relationships."
  ;; Child does not start with parent
  (should (listp (autoslip-roam-validate-new-child "1.2" "1.3a")))
  ;; Child identical to parent
  (should (listp (autoslip-roam-validate-new-child "1.2" "1.2")))
  ;; Invalid child suffix
  (should (listp (autoslip-roam-validate-new-child "1.2a" "1.2ab"))))

;;; ============================================================================
;;; Unit Tests: autoslip-roam-suggest-next-child
;;; ============================================================================

(ert-deftest test-suggest-next-child-root-number ()
  "Test suggestions for root number parents."
  (test-autoslip-roam--with-mock-nodes '()
    (let ((suggestions (autoslip-roam-suggest-next-child "7")))
      (should (equal '("7.1") suggestions)))))

(ert-deftest test-suggest-next-child-root-with-existing ()
  "Test suggestions for root number with existing children."
  (let* ((child1 (test-autoslip-roam--create-mock-node "id1" "7.1 First" "/tmp/7-1.org"))
         (child2 (test-autoslip-roam--create-mock-node "id2" "7.2 Second" "/tmp/7-2.org"))
         (nodes (list child1 child2)))
    (test-autoslip-roam--with-mock-nodes nodes
      (let ((suggestions (autoslip-roam-suggest-next-child "7")))
        (should (equal '("7.3") suggestions))))))

(ert-deftest test-suggest-next-child-dot-number ()
  "Test suggestions for dot-number parents."
  (test-autoslip-roam--with-mock-nodes '()
    (let ((suggestions (autoslip-roam-suggest-next-child "7.1")))
      (should (equal '("7.1a") suggestions)))))

(ert-deftest test-suggest-next-child-dot-number-with-existing ()
  "Test suggestions for dot-number with existing letter children."
  (let* ((child1 (test-autoslip-roam--create-mock-node "id1" "7.1a First" "/tmp/7-1a.org"))
         (child2 (test-autoslip-roam--create-mock-node "id2" "7.1b Second" "/tmp/7-1b.org"))
         (nodes (list child1 child2)))
    (test-autoslip-roam--with-mock-nodes nodes
      (let ((suggestions (autoslip-roam-suggest-next-child "7.1")))
        (should (equal '("7.1c") suggestions))))))

(ert-deftest test-suggest-next-child-letter-ending ()
  "Test suggestions for letter-ending parents."
  (test-autoslip-roam--with-mock-nodes '()
    (let ((suggestions (autoslip-roam-suggest-next-child "7.1a")))
      (should (equal '("7.1a1") suggestions)))))

(ert-deftest test-suggest-next-child-letter-ending-with-existing ()
  "Test suggestions for letter-ending with existing number children."
  (let* ((child1 (test-autoslip-roam--create-mock-node "id1" "7.1a1 First" "/tmp/7-1a1.org"))
         (child2 (test-autoslip-roam--create-mock-node "id2" "7.1a2 Second" "/tmp/7-1a2.org"))
         (nodes (list child1 child2)))
    (test-autoslip-roam--with-mock-nodes nodes
      (let ((suggestions (autoslip-roam-suggest-next-child "7.1a")))
        (should (equal '("7.1a3") suggestions))))))

(ert-deftest test-suggest-next-child-extended-letters ()
  "Test suggestions handle extended letter sequences (z -> aa)."
  (let* ((children (cl-loop for i from 1 to 26
                            for letter = (char-to-string (+ ?a (1- i)))
                            collect (test-autoslip-roam--create-mock-node
                                     (format "id%d" i)
                                     (format "7.1%s Child" letter)
                                     (format "/tmp/7-1%s.org" letter))))
         (nodes children))
    (test-autoslip-roam--with-mock-nodes nodes
      (let ((suggestions (autoslip-roam-suggest-next-child "7.1")))
        (should (equal '("7.1aa") suggestions))))))

(ert-deftest test-suggest-next-child-invalid-parent ()
  "Test that invalid parent returns nil."
  (test-autoslip-roam--with-mock-nodes '()
    (should (equal nil (autoslip-roam-suggest-next-child "1.2.3")))
    (should (equal nil (autoslip-roam-suggest-next-child "")))))

;;; ============================================================================
;;; Unit Tests: autoslip-roam--find-parent-node
;;; ============================================================================

(ert-deftest test-find-parent-node-exists ()
  "Test finding a parent node that exists."
  (let* ((parent (test-autoslip-roam--create-mock-node "parent-id" "7 Parent Topic" "/tmp/7.org"))
         (nodes (list parent)))
    (test-autoslip-roam--with-mock-nodes nodes
      (let ((result (autoslip-roam--find-parent-node "7")))
        (should result)
        (should (equal "parent-id" (org-roam-node-id result)))))))

(ert-deftest test-find-parent-node-not-exists ()
  "Test finding a parent node that does not exist."
  (let* ((other (test-autoslip-roam--create-mock-node "other-id" "8 Other Topic" "/tmp/8.org"))
         (nodes (list other)))
    (test-autoslip-roam--with-mock-nodes nodes
      (let ((result (autoslip-roam--find-parent-node "7")))
        (should (equal nil result))))))

(ert-deftest test-find-parent-node-multiple-nodes ()
  "Test finding parent among multiple nodes."
  (let* ((node1 (test-autoslip-roam--create-mock-node "id1" "1 First" "/tmp/1.org"))
         (node2 (test-autoslip-roam--create-mock-node "id2" "1.2 Second" "/tmp/1-2.org"))
         (node3 (test-autoslip-roam--create-mock-node "id3" "1.2a Third" "/tmp/1-2a.org"))
         (nodes (list node1 node2 node3)))
    (test-autoslip-roam--with-mock-nodes nodes
      (should (equal "id2" (org-roam-node-id (autoslip-roam--find-parent-node "1.2"))))
      (should (equal "id1" (org-roam-node-id (autoslip-roam--find-parent-node "1")))))))

(ert-deftest test-find-parent-node-nil-address ()
  "Test finding parent with nil address returns nil."
  (test-autoslip-roam--with-mock-nodes '()
    (should (equal nil (autoslip-roam--find-parent-node nil)))))

;;; ============================================================================
;;; Unit Tests: autoslip-roam--index-exists-p
;;; ============================================================================

(ert-deftest test-index-exists-p-found ()
  "Test that existing index is found."
  (let* ((node (test-autoslip-roam--create-mock-node "id1" "1.2a Topic" "/tmp/1-2a.org"))
         (nodes (list node)))
    (test-autoslip-roam--with-mock-nodes nodes
      (should (autoslip-roam--index-exists-p "1.2a")))))

(ert-deftest test-index-exists-p-not-found ()
  "Test that non-existing index is not found."
  (let* ((node (test-autoslip-roam--create-mock-node "id1" "1.2a Topic" "/tmp/1-2a.org"))
         (nodes (list node)))
    (test-autoslip-roam--with-mock-nodes nodes
      (should (equal nil (autoslip-roam--index-exists-p "1.2b"))))))

;;; ============================================================================
;;; Integration Tests: Link Insertion Functions
;;; ============================================================================

(ert-deftest test-insert-backlink-creates-heading ()
  "Test that insert-backlink creates the Parent Note heading."
  (test-autoslip-roam--with-temp-dir
    (let* ((child-file (test-autoslip-roam--create-temp-org-file
                        "child.org"
                        "#+title: 1.2a Child Topic\n\nContent here."))
           (parent-node (test-autoslip-roam--create-mock-node
                         "parent-id" "1.2 Parent Topic" "/tmp/parent.org"))
           (autoslip-roam-backlink-heading "Parent Note"))
      (with-current-buffer (find-file-noselect child-file)
        (autoslip-roam--insert-backlink parent-node)
        (goto-char (point-min))
        (should (search-forward "* Parent Note" nil t))
        (should (search-forward "[[id:parent-id]" nil t))
        (kill-buffer)))))

(ert-deftest test-insert-backlink-uses-description ()
  "Test that insert-backlink uses the configured description."
  (test-autoslip-roam--with-temp-dir
    (let* ((child-file (test-autoslip-roam--create-temp-org-file
                        "child.org"
                        "#+title: 1.2a Child Topic\n"))
           (parent-node (test-autoslip-roam--create-mock-node
                         "parent-id" "1.2 Parent Topic" "/tmp/parent.org"))
           (autoslip-roam-parent-link-description "Parent note"))
      (with-current-buffer (find-file-noselect child-file)
        (autoslip-roam--insert-backlink parent-node)
        (goto-char (point-min))
        (should (search-forward "[[id:parent-id][Parent note]]" nil t))
        (kill-buffer)))))

(ert-deftest test-insert-forward-link-creates-heading ()
  "Test that insert-forward-link creates the Child Notes heading."
  (test-autoslip-roam--with-temp-dir
    (let* ((parent-file (test-autoslip-roam--create-temp-org-file
                         "parent.org"
                         "#+title: 1.2 Parent Topic\n\nContent here."))
           (child-node (test-autoslip-roam--create-mock-node
                        "child-id" "1.2a Child Topic" parent-file))
           (autoslip-roam-forward-link-heading "Child Notes"))
      ;; Mock org-roam-db-update-file to avoid database errors
      (cl-letf (((symbol-function 'org-roam-db-update-file) #'ignore))
        (autoslip-roam--insert-forward-link child-node parent-file)
        (with-current-buffer (find-file-noselect parent-file)
          (goto-char (point-min))
          (should (search-forward "* Child Notes" nil t))
          (should (search-forward "[[id:child-id]" nil t))
          (kill-buffer))))))

(ert-deftest test-insert-forward-link-uses-title ()
  "Test that insert-forward-link uses child title as description."
  (test-autoslip-roam--with-temp-dir
    (let* ((parent-file (test-autoslip-roam--create-temp-org-file
                         "parent.org"
                         "#+title: 1.2 Parent Topic\n"))
           (child-node (test-autoslip-roam--create-mock-node
                        "child-id" "1.2a Child Topic" parent-file))
           (autoslip-roam-child-link-description nil))
      (cl-letf (((symbol-function 'org-roam-db-update-file) #'ignore))
        (autoslip-roam--insert-forward-link child-node parent-file)
        (with-current-buffer (find-file-noselect parent-file)
          (goto-char (point-min))
          (should (search-forward "[[id:child-id][1.2a Child Topic]]" nil t))
          (kill-buffer))))))

(ert-deftest test-insert-crosslink-creates-heading ()
  "Test that insert-crosslink creates the Cross References heading."
  (test-autoslip-roam--with-temp-dir
    (let* ((target-file (test-autoslip-roam--create-temp-org-file
                         "target.org"
                         "#+title: Target Note\n\nContent."))
           (source-node (test-autoslip-roam--create-mock-node
                         "source-id" "Source Note" "/tmp/source.org"))
           (target-node (test-autoslip-roam--create-mock-node
                         "target-id" "Target Note" target-file))
           (autoslip-roam-crosslink-heading "Cross References"))
      (cl-letf (((symbol-function 'org-roam-db-update-file) #'ignore))
        (autoslip-roam--insert-crosslink target-node source-node target-file)
        (with-current-buffer (find-file-noselect target-file)
          (goto-char (point-min))
          (should (search-forward "* Cross References" nil t))
          (should (search-forward "[[id:source-id][Source Note]]" nil t))
          (kill-buffer))))))

(ert-deftest test-insert-crosslink-prevents-duplicates ()
  "Test that insert-crosslink does not create duplicate links."
  (test-autoslip-roam--with-temp-dir
    (let* ((target-file (test-autoslip-roam--create-temp-org-file
                         "target.org"
                         "#+title: Target Note\n\n* Cross References\n[[id:source-id][Source Note]]\n"))
           (source-node (test-autoslip-roam--create-mock-node
                         "source-id" "Source Note" "/tmp/source.org"))
           (target-node (test-autoslip-roam--create-mock-node
                         "target-id" "Target Note" target-file)))
      (cl-letf (((symbol-function 'org-roam-db-update-file) #'ignore))
        (autoslip-roam--insert-crosslink target-node source-node target-file)
        (with-current-buffer (find-file-noselect target-file)
          (goto-char (point-min))
          ;; Count occurrences - should be exactly 1
          (let ((count 0))
            (while (search-forward "[[id:source-id]" nil t)
              (setq count (1+ count)))
            (should (equal 1 count)))
          (kill-buffer))))))

;;; ============================================================================
;;; Integration Tests: Bidirectional Link Creation
;;; ============================================================================

(ert-deftest test-bidirectional-links-in-parent-and-child ()
  "Test that both parent and child get appropriate links."
  (test-autoslip-roam--with-temp-dir
    (let* ((parent-file (test-autoslip-roam--create-temp-org-file
                         "parent.org"
                         "#+title: 7.1 Parent Topic\n\nParent content."))
           (child-file (test-autoslip-roam--create-temp-org-file
                        "child.org"
                        "#+title: 7.1a Child Topic\n\nChild content."))
           (parent-node (test-autoslip-roam--create-mock-node
                         "parent-id" "7.1 Parent Topic" parent-file))
           (child-node (test-autoslip-roam--create-mock-node
                        "child-id" "7.1a Child Topic" child-file)))
      (cl-letf (((symbol-function 'org-roam-db-update-file) #'ignore))
        ;; Insert backlink in child
        (with-current-buffer (find-file-noselect child-file)
          (autoslip-roam--insert-backlink parent-node)
          (save-buffer))
        ;; Insert forward link in parent
        (autoslip-roam--insert-forward-link child-node parent-file)
        
        ;; Verify child has parent link
        (with-current-buffer (find-file-noselect child-file)
          (goto-char (point-min))
          (should (search-forward "* Parent Note" nil t))
          (should (search-forward "[[id:parent-id]" nil t))
          (kill-buffer))
        
        ;; Verify parent has child link
        (with-current-buffer (find-file-noselect parent-file)
          (goto-char (point-min))
          (should (search-forward "* Child Notes" nil t))
          (should (search-forward "[[id:child-id]" nil t))
          (kill-buffer))))))

;;; ============================================================================
;;; Integration Tests: Mode Activation
;;; ============================================================================

(ert-deftest test-mode-activation ()
  "Test that mode can be activated and deactivated."
  (unwind-protect
      (progn
        ;; Activate mode
        (autoslip-roam-mode 1)
        (should (equal t autoslip-roam-mode))
        (should (member 'autoslip-roam--process-new-node 
                        org-roam-capture-new-node-hook))
        
        ;; Deactivate mode
        (autoslip-roam-mode -1)
        (should (equal nil autoslip-roam-mode))
        (should (not (member 'autoslip-roam--process-new-node 
                             org-roam-capture-new-node-hook))))
    ;; Cleanup
    (autoslip-roam-mode -1)))

;;; ============================================================================
;;; Regression Tests
;;; ============================================================================

(ert-deftest test-regression-multidigit-numbers ()
  "Regression: Multi-digit numbers should be handled correctly."
  (should (equal "1" (autoslip-roam--parse-address "1.123")))
  (should (equal "1.123" (autoslip-roam--parse-address "1.123a")))
  (should (equal "1.123a" (autoslip-roam--parse-address "1.123a456"))))

(ert-deftest test-regression-extended-alphabet-parent ()
  "Regression: Extended alphabet sequences should parse to correct parent."
  ;; aa, ab, etc. are children of 1.2, not 1.2a
  (should (equal "1.2" (autoslip-roam--parse-address "1.2aa")))
  (should (equal "1.2" (autoslip-roam--parse-address "1.2ab")))
  (should (equal "1.2" (autoslip-roam--parse-address "1.2zz")))
  (should (equal "1.2" (autoslip-roam--parse-address "1.2aaa"))))

(ert-deftest test-regression-deep-chains ()
  "Regression: Very deep chains should be handled."
  (should (equal "1.2a3b4c5d6e7f8g9h"
                 (autoslip-roam--parse-address "1.2a3b4c5d6e7f8g9h10")))
  (should (equal "1.2a3b4c5d6e7f8g9h10"
                 (autoslip-roam--parse-address "1.2a3b4c5d6e7f8g9h10i"))))

(ert-deftest test-regression-title-with-numbers ()
  "Regression: Titles containing numbers should extract correctly."
  (should (equal "1.2" (autoslip-roam--extract-from-title "1.2 Chapter 5 Analysis")))
  (should (equal "3.14" (autoslip-roam--extract-from-title "3.14 Pi Discussion"))))

(ert-deftest test-regression-case-sensitivity ()
  "Regression: Uppercase letters should be rejected."
  (should (stringp (autoslip-roam--validate-no-invalid-characters "1.2A")))
  (should (stringp (autoslip-roam--validate-no-invalid-characters "1.2aB3")))
  (should (equal nil (autoslip-roam-validate-address "1.2A"))))

;;; ============================================================================
;;; Edge Case Tests
;;; ============================================================================

(ert-deftest test-edge-empty-title ()
  "Test handling of empty titles."
  (should (equal nil (autoslip-roam--extract-from-title "")))
  (should (equal nil (autoslip-roam--extract-from-title nil))))

(ert-deftest test-edge-whitespace-title ()
  "Test handling of whitespace-only titles."
  (should (equal nil (autoslip-roam--extract-from-title "   ")))
  (should (equal nil (autoslip-roam--extract-from-title "\t\n"))))

(ert-deftest test-edge-very-long-address ()
  "Test handling of very long addresses."
  (let ((long-addr "1.2a3b4c5d6e7f8g9h10i11j12k13l14m15n16o17p18q19r20s21t22u23v24w25x26y27z28"))
    (should (autoslip-roam-validate-address long-addr))))

(ert-deftest test-edge-single-letter-all ()
  "Test all single letters work correctly."
  (dolist (letter (mapcar #'char-to-string (number-sequence ?a ?z)))
    (let ((addr (concat "1.2" letter)))
      (should (equal "1.2" (autoslip-roam--parse-address addr))))))

(ert-deftest test-edge-customization-nil-heading ()
  "Test behavior when headings are set to nil."
  (test-autoslip-roam--with-temp-dir
    (let* ((child-file (test-autoslip-roam--create-temp-org-file
                        "child.org"
                        "#+title: 1.2a Child Topic\n\n"))
           (parent-node (test-autoslip-roam--create-mock-node
                         "parent-id" "1.2 Parent Topic" "/tmp/parent.org"))
           (autoslip-roam-backlink-heading nil))
      (with-current-buffer (find-file-noselect child-file)
        (autoslip-roam--insert-backlink parent-node)
        (goto-char (point-min))
        ;; Should not have a heading
        (should (not (search-forward "* Parent Note" nil t)))
        ;; But should have the link
        (goto-char (point-min))
        (should (search-forward "[[id:parent-id]" nil t))
        (kill-buffer)))))

;;; ============================================================================
;;; Performance Tests (Optional - can be slow)
;;; ============================================================================

(ert-deftest test-perf-many-nodes-lookup ()
  "Test performance with many nodes (should complete quickly)."
  :tags '(:perf)
  (let* ((nodes (cl-loop for i from 1 to 1000
                         collect (test-autoslip-roam--create-mock-node
                                  (format "id%d" i)
                                  (format "1.%d Topic %d" i i)
                                  (format "/tmp/1-%d.org" i)))))
    (test-autoslip-roam--with-mock-nodes nodes
      (let ((start-time (float-time)))
        (autoslip-roam--find-parent-node "1.500")
        (let ((elapsed (- (float-time) start-time)))
          ;; Should complete in under 1 second
          (should (< elapsed 1.0)))))))

(ert-deftest test-perf-validation-batch ()
  "Test validation performance on many addresses."
  :tags '(:perf)
  (let ((addresses '("1" "1.2" "1.2a" "1.2a3" "1.2a3b" "1.2a3b4"
                     "1.13" "1.13aa" "1.13aa5" "42.99zz15abc")))
    (let ((start-time (float-time)))
      (dotimes (_ 1000)
        (dolist (addr addresses)
          (autoslip-roam-validate-address addr)))
      (let ((elapsed (- (float-time) start-time)))
        ;; 10000 validations should complete in under 2 seconds
        (should (< elapsed 2.0))))))

;;; ============================================================================
;;; Unit Tests: Address depth and comparison
;;; ============================================================================

(ert-deftest test-address-depth-root ()
  "Root addresses have depth 0."
  (should (equal 0 (autoslip-roam--address-depth "1")))
  (should (equal 0 (autoslip-roam--address-depth "42"))))

(ert-deftest test-address-depth-increments ()
  "Each parent step adds one to the depth."
  (should (equal 1 (autoslip-roam--address-depth "1.2")))
  (should (equal 2 (autoslip-roam--address-depth "1.2a")))
  (should (equal 3 (autoslip-roam--address-depth "1.2a3")))
  (should (equal 4 (autoslip-roam--address-depth "1.2a3b"))))

(ert-deftest test-address-tokens-shape ()
  "Address tokenization separates numbers and letter groups."
  (should (equal '(1) (autoslip-roam--address-tokens "1")))
  (should (equal '(1 13) (autoslip-roam--address-tokens "1.13")))
  (should (equal '(1 13 "a") (autoslip-roam--address-tokens "1.13a")))
  (should (equal '(1 2 "a" 3 "b")
                 (autoslip-roam--address-tokens "1.2a3b"))))

(ert-deftest test-compare-addresses-ordering ()
  "Address comparison places 1 < 1.1 < 1.1a < 1.2 < 2."
  (should (autoslip-roam--compare-addresses "1" "1.1"))
  (should (autoslip-roam--compare-addresses "1.1" "1.1a"))
  (should (autoslip-roam--compare-addresses "1.1a" "1.1a1"))
  (should (autoslip-roam--compare-addresses "1.1a1" "1.1b"))
  (should (autoslip-roam--compare-addresses "1.1b" "1.2"))
  (should (autoslip-roam--compare-addresses "1.2" "2"))
  ;; Symmetry: reverse should be false
  (should-not (autoslip-roam--compare-addresses "1.2" "1.1")))

(ert-deftest test-compare-addresses-numeric-order ()
  "Numeric segments sort numerically, not lexicographically."
  (should (autoslip-roam--compare-addresses "1.2" "1.13"))
  (should (autoslip-roam--compare-addresses "1.9" "1.10")))

;;; ============================================================================
;;; Unit Tests: Children-of lookup
;;; ============================================================================

(ert-deftest test-children-nodes-of-direct ()
  "`--children-nodes-of' only returns direct children, not grandchildren."
  (let* ((c1 (test-autoslip-roam--create-mock-node
              "id-1-1" "1.1 First" "/tmp/1-1.org"))
         (c2 (test-autoslip-roam--create-mock-node
              "id-1-2" "1.2 Second" "/tmp/1-2.org"))
         (gc (test-autoslip-roam--create-mock-node
              "id-1-1-a" "1.1a Grandchild" "/tmp/1-1a.org")))
    (test-autoslip-roam--with-mock-nodes (list c1 c2 gc)
      (let ((children (autoslip-roam--children-nodes-of "1")))
        (should (equal 2 (length children)))
        (should (cl-every (lambda (n)
                            (member (org-roam-node-id n) '("id-1-1" "id-1-2")))
                          children))))))

(ert-deftest test-children-nodes-of-none ()
  "Nodes with no children yield the empty list."
  (let ((leaf (test-autoslip-roam--create-mock-node
               "id-leaf" "1.1a Leaf" "/tmp/leaf.org")))
    (test-autoslip-roam--with-mock-nodes (list leaf)
      (should (equal nil (autoslip-roam--children-nodes-of "1.1a"))))))

;;; ============================================================================
;;; Unit Tests: File-rename computation for reparent
;;; ============================================================================

(ert-deftest test-compute-renamed-file-literal ()
  "Literal folgezettel in basename is substituted."
  (should (equal "/tmp/1.2b_topic.org"
                 (autoslip-roam--compute-renamed-file
                  "/tmp/1.2a_topic.org" "1.2a" "1.2b"))))

(ert-deftest test-compute-renamed-file-underscore-slug ()
  "Underscore-slugged address is substituted in the same style."
  (should (equal "/tmp/20260101-1_2b_topic.org"
                 (autoslip-roam--compute-renamed-file
                  "/tmp/20260101-1_2a_topic.org" "1.2a" "1.2b"))))

(ert-deftest test-compute-renamed-file-no-match ()
  "No substitution yields nil."
  (should (equal nil
                 (autoslip-roam--compute-renamed-file
                  "/tmp/unrelated.org" "1.2a" "1.2b"))))

(ert-deftest test-compute-renamed-file-same-addr ()
  "When old and new addresses match, no rename is produced."
  (should (equal nil
                 (autoslip-roam--compute-renamed-file
                  "/tmp/1.2a_topic.org" "1.2a" "1.2a"))))

;;; ============================================================================
;;; Integration Tests: Property-drawer link storage
;;; ============================================================================

(ert-deftest test-link-storage-properties-parent ()
  "Parent backlink is written to the FZ_PARENT property when storage is `properties'."
  (test-autoslip-roam--with-temp-dir
    (let* ((child-file (test-autoslip-roam--create-temp-org-file
                        "child.org"
                        "#+title: 1.2a Child Topic\n\nContent.\n"))
           (parent-node (test-autoslip-roam--create-mock-node
                         "parent-id-xyz" "1.2 Parent" "/tmp/parent.org"))
           (autoslip-roam-link-storage 'properties))
      (with-current-buffer (find-file-noselect child-file)
        (autoslip-roam--insert-backlink parent-node)
        (save-buffer)
        (goto-char (point-min))
        (should (re-search-forward "^:FZ_PARENT: parent-id-xyz" nil t))
        ;; No Parent Note heading should appear.
        (goto-char (point-min))
        (should-not (search-forward "* Parent Note" nil t))
        (kill-buffer)))))

(ert-deftest test-link-storage-properties-children ()
  "Forward link adds the child ID to FZ_CHILDREN (and subsequent adds dedupe/append)."
  (test-autoslip-roam--with-temp-dir
    (let* ((parent-file (test-autoslip-roam--create-temp-org-file
                         "parent.org"
                         "#+title: 1.2 Parent\n\nContent.\n"))
           (c1 (test-autoslip-roam--create-mock-node
                "child-1" "1.2a Child A" "/tmp/c1.org"))
           (c2 (test-autoslip-roam--create-mock-node
                "child-2" "1.2b Child B" "/tmp/c2.org"))
           (autoslip-roam-link-storage 'properties))
      (cl-letf (((symbol-function 'org-roam-db-update-file) #'ignore))
        (autoslip-roam--insert-forward-link c1 parent-file)
        (autoslip-roam--insert-forward-link c2 parent-file)
        ;; Inserting c1 again should NOT create a duplicate entry.
        (autoslip-roam--insert-forward-link c1 parent-file)
        (with-current-buffer (find-file-noselect parent-file)
          (goto-char (point-min))
          (should (re-search-forward "^:FZ_CHILDREN: child-1,child-2$" nil t))
          ;; No visible Child Notes heading in this mode.
          (goto-char (point-min))
          (should-not (search-forward "* Child Notes" nil t))
          (kill-buffer))))))

(ert-deftest test-link-storage-headings-unchanged ()
  "Default `headings' storage still writes visible Parent Note / Child Notes."
  (test-autoslip-roam--with-temp-dir
    (let* ((child-file (test-autoslip-roam--create-temp-org-file
                        "child.org"
                        "#+title: 1.2a Child Topic\n\nContent.\n"))
           (parent-node (test-autoslip-roam--create-mock-node
                         "parent-id-def" "1.2 Parent" "/tmp/parent.org"))
           (autoslip-roam-link-storage 'headings))
      (with-current-buffer (find-file-noselect child-file)
        (autoslip-roam--insert-backlink parent-node)
        (goto-char (point-min))
        (should (search-forward "* Parent Note" nil t))
        (should (search-forward "[[id:parent-id-def]" nil t))
        (kill-buffer)))))

;;; ============================================================================
;;; Integration Tests: Reparent
;;; ============================================================================

(ert-deftest test-remove-backlink-heading-removes-section ()
  "`--remove-backlink-heading' deletes the Parent Note heading and its link."
  (test-autoslip-roam--with-temp-dir
    (let* ((file (test-autoslip-roam--create-temp-org-file
                  "note.org"
                  "#+title: 1.2a Child\n\n* Parent Note\n[[id:pid][Parent note]]\n\n* Body\nText.\n")))
      (with-current-buffer (find-file-noselect file)
        (autoslip-roam--remove-backlink-heading)
        (goto-char (point-min))
        (should-not (search-forward "* Parent Note" nil t))
        ;; The Body heading should remain intact.
        (goto-char (point-min))
        (should (search-forward "* Body" nil t))
        (kill-buffer)))))

(ert-deftest test-remove-forward-link-line-specific-id ()
  "`--remove-forward-link-line' removes only the line for the matching child id."
  (test-autoslip-roam--with-temp-dir
    (let* ((file (test-autoslip-roam--create-temp-org-file
                  "parent.org"
                  "#+title: 1.2 Parent\n\n* Child Notes\n[[id:child-a][1.2a A]]\n[[id:child-b][1.2b B]]\n")))
      (with-current-buffer (find-file-noselect file)
        (autoslip-roam--remove-forward-link-line "child-a")
        (goto-char (point-min))
        (should-not (search-forward "[[id:child-a]" nil t))
        (goto-char (point-min))
        (should (search-forward "[[id:child-b]" nil t))
        (kill-buffer)))))

(ert-deftest test-replace-title-keyword-preserves-text ()
  "Rewriting the #+title line keeps other content intact."
  (test-autoslip-roam--with-temp-dir
    (let ((file (test-autoslip-roam--create-temp-org-file
                 "note.org"
                 "#+title: 1.2a Old Heading\n\nBody text.\n")))
      (with-current-buffer (find-file-noselect file)
        (autoslip-roam--replace-title-keyword "1.2b Old Heading")
        (goto-char (point-min))
        (should (search-forward "#+title: 1.2b Old Heading" nil t))
        (goto-char (point-min))
        (should (search-forward "Body text." nil t))
        (kill-buffer)))))

;;; ============================================================================
;;; Integration Tests: Tree buffer
;;; ============================================================================

(ert-deftest test-show-tree-orders-nodes ()
  "`show-tree' renders all indexed nodes in hierarchical order."
  (let* ((n1   (test-autoslip-roam--create-mock-node
                "id-1"    "1 Root"      "/tmp/1.org"))
         (n11  (test-autoslip-roam--create-mock-node
                "id-1-1"  "1.1 Sub"     "/tmp/1-1.org"))
         (n11a (test-autoslip-roam--create-mock-node
                "id-1-1a" "1.1a Branch" "/tmp/1-1a.org"))
         (n12  (test-autoslip-roam--create-mock-node
                "id-1-2"  "1.2 Other"   "/tmp/1-2.org"))
         (nodes (list n12 n11a n1 n11)))
    (test-autoslip-roam--with-mock-nodes nodes
      (cl-letf (((symbol-function 'autoslip-roam--maybe-sync-db) #'ignore)
                ((symbol-function 'switch-to-buffer-other-window)
                 (lambda (buf) buf)))
        (unwind-protect
            (progn
              (autoslip-roam-show-tree)
              (with-current-buffer autoslip-roam-tree-buffer-name
                (let ((text (buffer-string)))
                  (should (string-match-p "1 Root" text))
                  (should (string-match-p "1\\.1 Sub" text))
                  (should (string-match-p "1\\.1a Branch" text))
                  (should (string-match-p "1\\.2 Other" text))
                  ;; Check that the root appears before sub which appears before branch.
                  (let ((p-root   (string-match "1 Root" text))
                        (p-sub    (string-match "1\\.1 Sub" text))
                        (p-branch (string-match "1\\.1a Branch" text))
                        (p-other  (string-match "1\\.2 Other" text)))
                    (should (< p-root p-sub))
                    (should (< p-sub p-branch))
                    (should (< p-branch p-other))))))
          (when (get-buffer autoslip-roam-tree-buffer-name)
            (kill-buffer autoslip-roam-tree-buffer-name)))))))

(ert-deftest test-show-tree-empty-vault ()
  "`show-tree' renders a friendly message when there are no indexed nodes."
  (test-autoslip-roam--with-mock-nodes '()
    (cl-letf (((symbol-function 'autoslip-roam--maybe-sync-db) #'ignore)
              ((symbol-function 'switch-to-buffer-other-window)
               (lambda (buf) buf)))
      (unwind-protect
          (progn
            (autoslip-roam-show-tree)
            (with-current-buffer autoslip-roam-tree-buffer-name
              (should (string-match-p "No folgezettel-indexed notes found"
                                      (buffer-string)))))
        (when (get-buffer autoslip-roam-tree-buffer-name)
          (kill-buffer autoslip-roam-tree-buffer-name))))))

;;; ============================================================================
;;; Integration Tests: goto-parent and list-children
;;; ============================================================================

(ert-deftest test-goto-parent-errors-on-root ()
  "`goto-parent' errors when the current note has no parent."
  (let ((root (test-autoslip-roam--create-mock-node
               "id-root" "1 Root" "/tmp/1.org")))
    (test-autoslip-roam--with-mock-nodes (list root)
      (cl-letf (((symbol-function 'autoslip-roam--maybe-sync-db) #'ignore)
                ((symbol-function 'org-roam-node-at-point) (lambda () root)))
        (should-error (autoslip-roam-goto-parent)
                      :type 'user-error)))))

(ert-deftest test-goto-parent-visits-parent ()
  "`goto-parent' calls `org-roam-node-visit' on the parent node."
  (let* ((parent (test-autoslip-roam--create-mock-node
                  "id-1" "1 Root" "/tmp/1.org"))
         (child  (test-autoslip-roam--create-mock-node
                  "id-1-1" "1.1 Child" "/tmp/1-1.org"))
         (visited nil))
    (test-autoslip-roam--with-mock-nodes (list parent child)
      (cl-letf (((symbol-function 'autoslip-roam--maybe-sync-db) #'ignore)
                ((symbol-function 'org-roam-node-at-point) (lambda () child))
                ((symbol-function 'org-roam-node-visit)
                 (lambda (n) (setq visited n))))
        (autoslip-roam-goto-parent)
        (should visited)
        (should (equal "id-1" (org-roam-node-id visited)))))))

(ert-deftest test-list-children-visits-selection ()
  "`list-children' prompts, then visits the chosen child node."
  (let* ((parent (test-autoslip-roam--create-mock-node
                  "id-p" "1 Root" "/tmp/1.org"))
         (c1 (test-autoslip-roam--create-mock-node
              "id-c1" "1.1 First" "/tmp/1-1.org"))
         (c2 (test-autoslip-roam--create-mock-node
              "id-c2" "1.2 Second" "/tmp/1-2.org"))
         (visited nil))
    (test-autoslip-roam--with-mock-nodes (list parent c1 c2)
      (cl-letf (((symbol-function 'autoslip-roam--maybe-sync-db) #'ignore)
                ((symbol-function 'org-roam-node-at-point) (lambda () parent))
                ((symbol-function 'completing-read)
                 (lambda (&rest _) "1.2 Second"))
                ((symbol-function 'org-roam-node-visit)
                 (lambda (n) (setq visited n))))
        (autoslip-roam-list-children)
        (should visited)
        (should (equal "id-c2" (org-roam-node-id visited)))))))

;;; ============================================================================
;;; Chain of Thought
;;; ============================================================================

(ert-deftest test-ancestor-addresses-root ()
  "A root address has a single-element chain."
  (should (equal (autoslip-roam--ancestor-addresses "1")
                 '("1"))))

(ert-deftest test-ancestor-addresses-chain ()
  "A deep address produces the full chain from root to leaf."
  (should (equal (autoslip-roam--ancestor-addresses "1.2a3b")
                 '("1" "1.2" "1.2a" "1.2a3" "1.2a3b"))))

(ert-deftest test-ancestor-addresses-nil ()
  "A nil or empty address returns nil."
  (should (null (autoslip-roam--ancestor-addresses nil)))
  (should (null (autoslip-roam--ancestor-addresses ""))))

(ert-deftest test-chain-triples-resolves-nodes ()
  "`--chain-triples' walks the chain and resolves each address to a node."
  (let* ((n1   (test-autoslip-roam--create-mock-node
                "id-1" "1 Root" "/tmp/1.org"))
         (n12  (test-autoslip-roam--create-mock-node
                "id-12" "1.2 Middle" "/tmp/1-2.org"))
         (n12a (test-autoslip-roam--create-mock-node
                "id-12a" "1.2a Leaf" "/tmp/1-2a.org")))
    (test-autoslip-roam--with-mock-nodes (list n1 n12 n12a)
      (let ((chain (autoslip-roam--chain-triples "1.2a")))
        (should (equal 3 (length chain)))
        (should (equal '("1" "1 Root" "id-1") (nth 0 chain)))
        (should (equal '("1.2" "1.2 Middle" "id-12") (nth 1 chain)))
        (should (equal '("1.2a" "1.2a Leaf" "id-12a") (nth 2 chain)))))))

(ert-deftest test-chain-triples-missing-ancestor ()
  "When an ancestor has no note, its title falls back to the address."
  (let* ((n1   (test-autoslip-roam--create-mock-node
                "id-1" "1 Root" "/tmp/1.org"))
         (n12a (test-autoslip-roam--create-mock-node
                "id-12a" "1.2a Orphaned" "/tmp/1-2a.org")))
    (test-autoslip-roam--with-mock-nodes (list n1 n12a)
      (let ((chain (autoslip-roam--chain-triples "1.2a")))
        (should (equal 3 (length chain)))
        ;; Middle entry for "1.2" has no node.
        (should (equal '("1.2" "1.2" nil) (nth 1 chain)))
        (should (equal "id-12a" (nth 2 (nth 2 chain))))))))

(ert-deftest test-chain-as-org-list-format ()
  "The org-list renderer indents by depth and uses `id:' links."
  (let ((chain '(("1"   "Root title"   "id-1")
                 ("1.2" "Middle title" "id-12")
                 ("1.2a" "Leaf title"  "id-12a"))))
    (let ((text (autoslip-roam--chain-as-org-list chain nil)))
      (should (string-match-p "^- \\[\\[id:id-1\\]\\[Root title\\]\\]$" text))
      (should (string-match-p "^  - \\[\\[id:id-12\\]\\[Middle title\\]\\]$" text))
      (should (string-match-p "^    - \\[\\[id:id-12a\\]\\[Leaf title\\]\\]$" text)))))

(ert-deftest test-chain-as-org-list-heading ()
  "When a heading is provided, it is emitted as a second-level heading."
  (let* ((chain '(("1" "Root" "id-1")))
         (text (autoslip-roam--chain-as-org-list chain "Chain of Thought")))
    (should (string-match-p "\\`\\*\\* Chain of Thought\n" text))))

(ert-deftest test-chain-as-org-list-missing-node ()
  "An entry with no id is rendered as plain text."
  (let* ((chain '(("1" "1" nil)))
         (text (autoslip-roam--chain-as-org-list chain nil)))
    (should (string-match-p "^- 1 (no note)$" text))))

(ert-deftest test-show-chain-of-thought-renders-buffer ()
  "`show-chain-of-thought' fills the chain buffer with one line per ancestor."
  (let* ((n1   (test-autoslip-roam--create-mock-node
                "id-1" "1 Root" "/tmp/1.org"))
         (n12  (test-autoslip-roam--create-mock-node
                "id-12" "1.2 Middle" "/tmp/1-2.org"))
         (leaf (test-autoslip-roam--create-mock-node
                "id-12a" "1.2a Leaf" "/tmp/1-2a.org")))
    (test-autoslip-roam--with-mock-nodes (list n1 n12 leaf)
      (cl-letf (((symbol-function 'autoslip-roam--maybe-sync-db) #'ignore)
                ((symbol-function 'org-roam-node-at-point) (lambda () leaf))
                ((symbol-function 'switch-to-buffer-other-window) #'ignore))
        (unwind-protect
            (progn
              (autoslip-roam-show-chain-of-thought)
              (with-current-buffer autoslip-roam-chain-buffer-name
                (let ((text (buffer-string)))
                  (should (string-match-p "Chain of Thought: 1.2a" text))
                  (should (string-match-p "1 Root" text))
                  (should (string-match-p "1.2 Middle" text))
                  (should (string-match-p "1.2a Leaf" text)))
                (should (equal 3 (length autoslip-roam--chain-data)))))
          (when (get-buffer autoslip-roam-chain-buffer-name)
            (kill-buffer autoslip-roam-chain-buffer-name)))))))

(ert-deftest test-insert-chain-of-thought-writes-list ()
  "`insert-chain-of-thought' inserts an org list at point in the current note."
  (let* ((n1   (test-autoslip-roam--create-mock-node
                "id-1" "1 Root" "/tmp/1.org"))
         (n12  (test-autoslip-roam--create-mock-node
                "id-12" "1.2 Middle" "/tmp/1-2.org"))
         (leaf (test-autoslip-roam--create-mock-node
                "id-12a" "1.2a Leaf" "/tmp/1-2a.org")))
    (test-autoslip-roam--with-mock-nodes (list n1 n12 leaf)
      (cl-letf (((symbol-function 'autoslip-roam--maybe-sync-db) #'ignore)
                ((symbol-function 'org-roam-node-at-point) (lambda () leaf)))
        (with-temp-buffer
          (let ((autoslip-roam-chain-heading "Chain of Thought"))
            (autoslip-roam-insert-chain-of-thought))
          (let ((text (buffer-string)))
            (should (string-match-p "^\\*\\* Chain of Thought$" text))
            (should (string-match-p "\\[\\[id:id-1\\]\\[1 Root\\]\\]" text))
            (should (string-match-p "\\[\\[id:id-12\\]\\[1.2 Middle\\]\\]" text))
            (should (string-match-p "\\[\\[id:id-12a\\]\\[1.2a Leaf\\]\\]" text))))))))

(ert-deftest test-crosslink-ids-in-buffer-returns-ids ()
  "The crosslink parser returns every id listed under the crosslink heading."
  (with-temp-buffer
    (insert "#+title: 1.2 Some note\n\n"
            "* Cross References\n"
            "[[id:aaa][First]]\n"
            "[[id:bbb][Second]]\n"
            "* Parent Note\n"
            "[[id:ccc][Unrelated]]\n")
    (let ((autoslip-roam-crosslink-heading "Cross References"))
      (should (equal '("aaa" "bbb")
                     (autoslip-roam--crosslink-ids-in-buffer))))))

(ert-deftest test-crosslink-ids-dedupes ()
  "Duplicate ids under the heading are returned once."
  (with-temp-buffer
    (insert "* Cross References\n"
            "[[id:aaa][A]]\n"
            "[[id:aaa][A again]]\n"
            "[[id:bbb][B]]\n")
    (let ((autoslip-roam-crosslink-heading "Cross References"))
      (should (equal '("aaa" "bbb")
                     (autoslip-roam--crosslink-ids-in-buffer))))))

(ert-deftest test-crosslink-ids-none-when-heading-absent ()
  "If the crosslink heading is not in the buffer, no ids are returned."
  (with-temp-buffer
    (insert "#+title: something\n\n* Parent Note\n[[id:aaa][x]]\n")
    (let ((autoslip-roam-crosslink-heading "Cross References"))
      (should (null (autoslip-roam--crosslink-ids-in-buffer))))))

(ert-deftest test-show-crosslinked-chains-renders-chains ()
  "`show-crosslinked-chains' fills the buffer with one chain per crosslink."
  (let* ((n1     (test-autoslip-roam--create-mock-node
                  "id-1" "1 Root" "/tmp/1.org"))
         (n12    (test-autoslip-roam--create-mock-node
                  "id-12" "1.2 Middle" "/tmp/1-2.org"))
         (n3     (test-autoslip-roam--create-mock-node
                  "id-3" "3 Other root" "/tmp/3.org"))
         (source (test-autoslip-roam--create-mock-node
                  "id-s" "2 Source" "/tmp/2.org"))
         (nodes (list n1 n12 n3 source)))
    (test-autoslip-roam--with-mock-nodes nodes
      (cl-letf (((symbol-function 'autoslip-roam--maybe-sync-db) #'ignore)
                ((symbol-function 'org-roam-node-at-point) (lambda () source))
                ((symbol-function 'org-roam-node-from-id)
                 (lambda (id)
                   (seq-find (lambda (n) (equal id (org-roam-node-id n)))
                             nodes)))
                ((symbol-function 'switch-to-buffer-other-window) #'ignore))
        (with-temp-buffer
          (insert "#+title: 2 Source\n\n* Cross References\n"
                  "[[id:id-12][Middle]]\n"
                  "[[id:id-3][Other root]]\n")
          (unwind-protect
              (progn
                (autoslip-roam-show-crosslinked-chains)
                (with-current-buffer
                    autoslip-roam-crosslinked-chains-buffer-name
                  (let ((text (buffer-string)))
                    (should (string-match-p "Cross-linked Chains" text))
                    (should (string-match-p "1 Root" text))
                    (should (string-match-p "1.2 Middle" text))
                    (should (string-match-p "3 Other root" text)))
                  (should (equal 2 (length autoslip-roam--chain-crosslinks)))))
            (when (get-buffer
                   autoslip-roam-crosslinked-chains-buffer-name)
              (kill-buffer
               autoslip-roam-crosslinked-chains-buffer-name))))))))

;;; ============================================================================
;;; Test Runner Helper
;;; ============================================================================

(defun test-autoslip-roam-run-all ()
  "Run all autoslip-roam tests."
  (interactive)
  (ert-run-tests-interactively "^test-"))

(defun test-autoslip-roam-run-unit ()
  "Run only unit tests (fast)."
  (interactive)
  (ert-run-tests-interactively "^test-\\(parse\\|extract\\|next-letter\\|validate\\|suggest\\|find\\|index\\)"))

(defun test-autoslip-roam-run-integration ()
  "Run only integration tests."
  (interactive)
  (ert-run-tests-interactively "^test-\\(insert\\|bidirectional\\|mode\\)"))

(provide 'test-autoslip-roam)

;;; test-autoslip-roam.el ends here
