;; Configure MELPA
(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
(package-initialize)

;; Install Magit if not already installed
(unless (package-installed-p 'magit)
  (package-refresh-contents)
  (package-install 'magit))

;; Conveniently open Magit
(global-set-key (kbd "C-x g") 'magit-status)
