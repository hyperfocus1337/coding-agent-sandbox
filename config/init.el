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

;; Auto-refresh: pick up local commits fast via auto-revert
(setq auto-revert-interval 2)

;; Periodically fetch + refresh any open magit status buffers (every 5 min)
(defvar my/magit-auto-fetch-interval 300
  "Seconds between background fetches for open magit status buffers.")

(defun my/magit-auto-fetch ()
  "Fetch and refresh each visible magit-status-mode buffer."
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (and (derived-mode-p 'magit-status-mode)
                 (magit-toplevel))
        (let ((magit-process-popup-time -1))
          (magit-fetch-all-no-prune))
        (magit-refresh)))))

(run-with-timer my/magit-auto-fetch-interval
                my/magit-auto-fetch-interval
                #'my/magit-auto-fetch)