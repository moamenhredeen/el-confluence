
;;; econfluence.el --- Edit Confluence wiki pages in Emacs  -*- lexical-binding: t; -*-

;; Copyright (C) 2023 Moamen Hraden


;; Author: Marek Rudnicki   <mrkrd@posteo.de>
;; Author: Moamen Hraden    <moamenhredeen@gmail.com>
;; Version: 3
;; URL: https://github.com/moamenhredeen/el-confluence.git
;; Package-Requires:
;; - request


;;; Commentary:

;; This package provides a major mode to pull Confluence wiki pages
;; via REST API, edit them as XML files, and push changes back to the
;; server.


;;; Code:


(require 'request)


(defcustom econfluence-api-url nil "URL to the Confluence API.")



(define-derived-mode econfluence-mode nxml-mode "econfluence"
  "econfluence is a major mode for editing and publishing Confluence pages."

  (setq-local econfluence--id nil)
  (setq-local econfluence--version-number nil)
  (setq-local econfluence--title nil)
  (setq-local econfluence--space-key nil)

  (define-key econfluence-mode-map (kbd "C-c C-c") 'econfluence-push)
  (define-key econfluence-mode-map (kbd "C-c C-p") 'econfluence-pretty-print-buffer)
  (define-key econfluence-mode-map (kbd "C-c C-k") 'econfluence-kill-buffer)
  )


(defun econfluence-pull-id (id)
  (interactive "sPage ID: ")
  (let* ((buf-name (econfluence--buffer-name id))
         (prompt (format "Buffer %s already exists, overwrite?" buf-name))
         (buf (get-buffer buf-name)))
    (if buf
        (when (yes-or-no-p prompt)
          (progn
            (kill-buffer buf)
            (econfluence--request-id id)))
      (econfluence--request-id id))))


;; (econfluence-pull-id "1704722479")



(defun econfluence-pull-url (url)
  (interactive "sPage URL: ")
  (let* ((parsed-url (url-generic-parse-url url))
         (filename (url-filename parsed-url))
         (_ (string-match (rx "/wiki/spaces/" (one-or-more alnum) "/pages/" (group (one-or-more digit)) "/" (zero-or-more any))
                        filename))
         (id (match-string 1 filename))
         (_ (setf (url-filename parsed-url) "/wiki/rest/api/content/"))
         (api-url (url-recreate-url parsed-url)))
  (econfluence-pull-id id)))



(defun econfluence--request-id (id)
  (let ((url (concat (file-name-as-directory econfluence-api-url) id "?expand=body.storage,space,version")))
    (request url
      :auth "basic"
      :parser 'json-read
      :sync t
      :success (cl-function
                (lambda (&key data &allow-other-keys)
                  (when data
                    (econfluence--setup-current-buffer data))))
      :error (cl-function
              (lambda (&rest args &key error-thrown &allow-other-keys)
                (message "Got error: %S" error-thrown)))
      )))


(defun econfluence--buffer-name (id)
  (format "*econfluence*%s*" id))


(defun econfluence--setup-current-buffer (data)
  (let-alist data
    (switch-to-buffer (econfluence--buffer-name .id))
    (econfluence-mode)
    (econfluence--setup-local-vars data)
    (insert "<confluence>")
    (insert .body.storage.value)
    (insert "\n</confluence>\n")
    (econfluence--set-schema)
    (goto-char (point-min))
    ;; (sgml-pretty-print (point-min) (point-max))
    )
  )

(defun econfluence--setup-local-vars (data)
  (let-alist data
    (setq econfluence--id .id)
    (setq econfluence--version-number (1+ .version.number))
    (setq econfluence--space-key .space.key)
    (econfluence-set-title .title)
    ))


(defun econfluence-set-title (title)
  (interactive (list (read-string "New Title: " econfluence--title)))
  (setq econfluence--title title)
  (setq header-line-format (format "%s [%s]" econfluence--title econfluence--version-number))
  )


(defun econfluence--set-schema ()
  (let ((dir (file-name-directory (locate-library "econfluence"))))
    (rng-set-schema-file (concat dir "confluence.rnc"))))


(defun econfluence-push ()
  (interactive)
  (let ((url (concat (file-name-as-directory econfluence-api-url) econfluence--id))
        (text (buffer-substring-no-properties (point-min) (point-max))))
    (request url
      :auth "basic"
      :type "PUT"
      :sync t
      :data (json-encode `((id . ,econfluence--id)
                           (type . "page")
                           (title . ,econfluence--title)
                           (space (key . ,econfluence--space-key))
                           (body (storage (value . ,text)
                                          (representation . "storage")))
                           (version (number . ,econfluence--version-number))
                           ))
      :headers '(("Content-Type" . "application/json"))
      :parser 'json-read
      :success (cl-function
                (lambda (&key data &allow-other-keys)
                  (econfluence--setup-local-vars data)
                  (message "Version %s pushed." (let-alist data .version.number))))
      :error (cl-function
              (lambda (&key data &allow-other-keys)
                (let-alist data
                  (message "ERROR %s: %s" .statusCode .message))))
      )))


(defun econfluence-pretty-print-buffer ()
  (interactive)
  (call-process-region
   (point-min)
   (point-max)
   "tidy"
   t                                    ; delete
   t                                    ; destination
   t                                    ; display
   "--input-xml" "yes"
   "--output-xml" "yes"
   "--indent" "yes"
   "--quiet" "yes"
   "--wrap" "0"))


(defun econfluence-kill-buffer ()
  (interactive)
  (when (y-or-n-p "Kill buffer? ")
    (kill-buffer))
  )


(provide 'econfluence)

