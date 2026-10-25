;;; aot-warm-modes.el -*- lexical-binding: t; -*-
;; Exhaustively force-load (and thus native-compile) every major mode Doom can
;; auto-select, plus every registered LSP client, in a disposable --batch
;; process. Invoked once at the end of `install-doom.sh' (after
;; `doom sync --aot --rebuild') so the deferred, runtime-only code paths are
;; also covered by ahead-of-time native compilation.
;;
;; Generic by construction - nothing language-specific is hardcoded:
;;   * major modes are discovered from the same alists `set-auto-mode'
;;     consults (auto-mode/interpreter/magic + tree-sitter remaps), and scanned
;;     to a fixpoint because loading one package can register more modes;
;;   * LSP clients come from lsp-mode's own `lsp-client-packages' list.
;;
;; Why this must run under --batch and never in the interactive session: some
;; tree-sitter modes pop a modal "install grammar?" prompt (e.g.
;; elixir-ts-mode) which blocks forever in a GUI; under --batch
;; `noninteractive' is t, so such prompts return/answer instead.
;;
;; Invoke as:
;;   emacs --batch --init-directory <doom-emacs-dir> -l aot-warm-modes.el

(load (expand-file-name "early-init.el" user-emacs-directory))
(doom-initialize nil noninteractive)
(ignore-errors (doom--startup-vars nil))

;; Under --batch the generated profile init omits interactive loaddefs (they
;; are wrapped in `static-unless noninteractive'): restore every enabled
;; package's autoload cookies so third-party modes resolve. Loaded one file at
;; a time so one bad package (auctex's tex-site under --batch) can't abort the
;; rest.
(let ((n 0))
  (dolist (d load-path)
    (when (and (stringp d)
               (string-match-p (regexp-quote "straight/build") d))
      (dolist (f (ignore-errors (directory-files d t "-autoloads\\.el\\'")))
        (when (load f 'noerror) (cl-incf n)))))
  (princ (format "AOT restored %d package autoload files\n" n)))

(defvar aot-warmed nil)
(defvar aot-errors nil)
(defvar aot-total-start (float-time))

(defun aot--candidates ()
  "All major modes reachable via `set-auto-mode' inputs plus ts remaps."
  (let (modes)
    (dolist (alist '(auto-mode-alist interpreter-mode-alist magic-mode-alist))
      (when (boundp alist)
        (dolist (entry (symbol-value alist))
          (when-let* ((fn (and (consp entry) (cdr entry))))
            (when (and (symbolp fn) (fboundp fn))
              (push fn modes))))))
    (dolist (var '(major-mode-remap-alist major-mode-remap-defaults))
      (when (boundp var)
        (dolist (cell (symbol-value var))
          (when-let* ((fn (cdr cell)))
            (when (and (symbolp fn) (fboundp fn))
              (push fn modes))))))
    (delete-dups modes)))

(defun aot--warm-one (mode)
  (condition-case e
      (with-temp-buffer
        (let ((inhibit-message t)
              (noninteractive t))
          (funcall mode)))
    (error (push (cons mode (error-message-string e)) aot-errors))))

(let ((round 0)
      (pending (aot--candidates)))
  (while pending
    (cl-incf round)
    (let ((added 0))
      (dolist (mode pending)
        (unless (memq mode aot-warmed)
          (cl-incf added)
          (push mode aot-warmed)
          (aot--warm-one mode)))
      ;; Fixpoint: loading packages may have registered more modes.
      (setq pending (cl-set-difference (aot--candidates) aot-warmed))
      (princ (format "AOT round %d: +%d modes, %d remain\n"
                     round added (length pending))))))

;; LSP clients are a separate category: lsp-mode autoloads none of them - it
;; requires them in one bundle the first time a real LSP buffer opens, so mere
;; major-mode activation never touches them. Pull the same list lsp itself
;; would. Safe under --batch: requiring a client only defines it; no server
;; process is started.
(defvar aot-lsp-clients 0)
(when (and (require 'lsp-mode nil t) (fboundp 'lsp--require-packages))
  (lsp--require-packages)
  (setq aot-lsp-clients (and (boundp 'lsp-client-packages)
                             (length lsp-client-packages))))
(princ (format "AOT lsp-clients required: %d\n" aot-lsp-clients))

(defun aot--comp-workers ()
  "Async native-comp subprocesses still running."
  (seq-filter
   (lambda (p)
     (let ((cmd (mapconcat (lambda (x) (format "%s" x))
                           (or (process-command p) nil) " ")))
       (string-match-p "comp-async" cmd)))
   (process-list)))

(defun aot--loaded-source-files ()
  "Distinct user-package source files loaded so far (via `load-history').
Only files under straight (user-installed); Emacs' own lisp ships prebuilt.
Match the bare `.local/straight' segment rather than an absolute path:
load-history keys can be recorded with an abbreviated $HOME (`~/...')."
  (let ((files))
    (dolist (entry load-history)
      (when-let* ((f (car entry)))
        (when (string-match-p (regexp-quote ".local/straight") f)
          (push f files))))
    (delete-dups files)))

(let* ((sources (aot--loaded-source-files))
       (n 0) (failed 0))
  (princ (format "AOT native-compiling %d loaded files...\n" (length sources)))
  (dolist (f sources)
    (cl-incf n)
    (condition-case e
        (native-compile f)
      (error (cl-incf failed)
             (princ (format "AOT-COMP-ERR %s :: %s\n" f e)))))
  (let ((deadline (+ (float-time) 600)))
    (while (and (aot--comp-workers) (< (float-time) deadline))
      (sleep-for 1)))
  (princ (format "AOT warmed=%d modes, lsp-clients=%d, files=%d (compile-failed=%d), errors=%d, comp-workers-left=%d, in %.1fs\n"
                 (length aot-warmed) aot-lsp-clients n failed
                 (length aot-errors) (length (aot--comp-workers))
                 (- (float-time) aot-total-start))))
(dolist (e (nreverse aot-errors))
  (princ (format "AOT-ERR %s :: %s\n" (car e) (cdr e))))

(kill-emacs 0)
