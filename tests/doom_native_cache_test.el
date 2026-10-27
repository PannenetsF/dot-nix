;;; doom_native_cache_test.el --- Bootstrap cache regression tests -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(require 'comp)

(defconst doom-cache-test-dir (file-name-directory load-file-name))

(defvar doom-cache-test-form
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name "../install-doom.sh" (file-name-directory load-file-name)))
    (goto-char (point-min))
    (search-forward "emacs --batch -Q --eval '")
    (read (current-buffer))))

(ert-deftest doom-cache-compiles-only-missing-or-outdated-artifacts ()
  (dolist (state '(missing current outdated system-current no-source no-native))
    (let* ((root (make-temp-file "doom-cache-test-" t))
           (source (expand-file-name "cl-macs.el" root))
           (cache (expand-file-name "user/" root))
           (system-cache (expand-file-name "system/" root))
           (native-comp-eln-load-path (list cache system-cache))
           (name "cl-macs-test.eln")
           (artifact (expand-file-name
                      name (expand-file-name comp-native-version-dir
                                             (if (eq state 'system-current)
                                                 system-cache cache))))
           compiled)
      (unwind-protect
          (progn
            (with-temp-file source (insert ";;; test\n"))
            (when (memq state '(current outdated system-current))
              (make-directory (file-name-directory artifact) t)
              (with-temp-file artifact (insert "fixture"))
              (set-file-times artifact (time-subtract (current-time) 60))
              (set-file-times source (time-subtract (current-time)
                                                   (if (eq state 'outdated) 30 90))))
            (cl-letf (((symbol-function 'native-comp-available-p)
                       (lambda () (not (eq state 'no-native))))
                      ((symbol-function 'locate-library)
                       (lambda (&rest _) (unless (eq state 'no-source) source)))
                      ((symbol-function 'comp-el-to-eln-filename)
                       (lambda (_) (expand-file-name name cache)))
                      ((symbol-function 'native-compile)
                       (lambda (file) (push file compiled))))
              (eval doom-cache-test-form t))
            (should (equal compiled (when (memq state '(missing outdated))
                                      (list source)))))
        (delete-directory root t)))))

(ert-deftest doom-cache-repair-precedes-existing-install-lock ()
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name "../install-doom.sh"
                       doom-cache-test-dir))
    (goto-char (point-min))
    (should (search-forward "emacs --batch -Q --eval" nil t))
    (should (search-forward "if [ -f \"$DOOM_LOCK\" ]; then" nil t))))
