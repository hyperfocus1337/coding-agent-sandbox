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