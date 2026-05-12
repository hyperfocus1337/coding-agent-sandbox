;; Configure MELPA
(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)

;; Install packages if not already installed
(dolist (pkg '(magit evil evil-collection))
  (unless (package-installed-p pkg)
    (unless package-archive-contents
      (package-refresh-contents))
    (package-install pkg)))

;; Evil (vim mode)
(setq evil-want-integration t
      evil-want-keybinding nil   ;; required by evil-collection
      evil-want-C-u-scroll t     ;; reclaim C-u for vim-style half-page up
      evil-undo-system 'undo-redo)
(require 'evil)
(evil-mode 1)

;; Vim bindings for Magit, dired, help, info, eshell, etc.
(require 'evil-collection)
(evil-collection-init)

;; Conveniently open Magit
(global-set-key (kbd "C-x g") 'magit-status)

;; Local file edits: revert file buffers fast (default magit-auto-revert-mode)
(setq auto-revert-interval 2)

;; Refresh magit status after saving a file inside the repo
(add-hook 'after-save-hook #'magit-after-save-refresh-status)

;; Refresh visible magit status buffers when Emacs regains focus
;; (catches commits / checkouts done in a terminal)
(defun my/magit-refresh-visible-status ()
  (dolist (win (window-list nil 'no-minibuf))
    (with-current-buffer (window-buffer win)
      (when (derived-mode-p 'magit-status-mode)
        (magit-refresh)))))

(add-function :after after-focus-change-function
              (lambda ()
                (when (frame-focus-state)
                  (my/magit-refresh-visible-status))))

;; Periodic background fetch for visible status buffers. Magit's process
;; sentinel auto-refreshes the buffer when the async fetch completes.
(defvar my/magit-auto-fetch-interval 300)
(defvar my/magit-auto-fetch-timer nil)

(defun my/magit-auto-fetch ()
  (dolist (win (window-list nil 'no-minibuf))
    (with-current-buffer (window-buffer win)
      (when (and (derived-mode-p 'magit-status-mode)
                 (magit-toplevel))
        (let ((magit-process-popup-time -1))
          (magit-fetch-all-no-prune))))))

(when (timerp my/magit-auto-fetch-timer)
  (cancel-timer my/magit-auto-fetch-timer))
(setq my/magit-auto-fetch-timer
      (run-with-timer my/magit-auto-fetch-interval
                      my/magit-auto-fetch-interval
                      #'my/magit-auto-fetch))