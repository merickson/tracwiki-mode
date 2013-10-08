;;; tracwiki-mode.el --- Emacs Major mode for working with Trac

;; Copyright (C) 2013 Matthew Erickson <peawee@peawee.net>

;; Author: Matthew Erickson <peawee@peawee.net>
;; Maintainer: Matthew Erickson <peawee@peawee.net>
;; Created: March 13, 2013
;; Version: 0.1
;; Package-Requires: ((xml-rpc "1.6.8"))
;; Keywords: Trac, wiki, tickets

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; tracwiki-mode is a major mode for editing Trac-formatted text files
;; in GNU Emacs. tracwiki-mode is free software, licensed under the
;; GNU GPL.
;;
;; Much of the syntax highlight is based on markdown-mode.el's handling
;; of it, and much of the Trac integration based on the original
;; trac-wiki by Shun-ichi GOTO:
;; http://trac-hacks.org/wiki/EmacsWikiEditScript

(require 'xml-rpc)

;;; Constants
(defconst tracwiki-mode-version "0.1"
  "Tracwiki mode version number")

;;; Customizable Variables
(defgroup tracwiki nil
  "Major mode for editing text files and tickets from a Trac wiki."
  :prefix "tracwiki-"
  :group  'wp
  :link   '(url-link "http://peawee.net"))

(defcustom tracwiki-xmlrpc-url nil
  "Set to the Trac xmlrpc login URL. For example:
  http://site.com/trac/login/xmlrpc"
  :group 'tracwiki
  :type 'string)

(defcustom tracwiki-uri-types
  '("acap" "cid" "data" "dav" "fax" "file" "ftp" "gopher" "http" "https"
    "imap" "ldap" "mailto" "mid" "modem" "news" "nfs" "nntp" "pop" "prospero"
    "rtsp" "service" "sip" "tel" "telnet" "tip" "urn" "vemmi" "wais")
  "Link types for syntax highlighting of URIs."
  :group 'tracwiki
  :type 'list)

(defcustom tracwiki-projects
  '(("trac-hacks"
     :endpoint "http://trac-hacks.org/login/xmlrpc"))
  "*List of project definitions.
The value is an alist of the project name and information plist.
For example:
'((\"meadow\"
     :endpoint \"http://www.meadowy.org/meadow/login/xmlrpc\"
     :login-name \"bob\")
    (\"local-test\"
     :endpoint \"http://localhost/project/test/xmlrpc\"
     :login-name \"bob\"
     :name \"Billy Bob\")))")

(defcustom tracwiki-hide-system-pages t
  "If non-nil, do not list system pages on completion.
System pages are defined by `tracwiki-system-pages' as a regexp.
Although these pages are not listed, you can visit them by
specifying a page name explicitly.")

(defcustom tracwiki-hidden-pages nil
  "*List of regexps to be hidden on completion of a page name.
System pages are always hidden if `tracwiki-hide-system-pages' is
non-nil.")

(defcustom tracwiki-search-default-filters '("wiki")
  "*List of search filter name(s) to use as the default.
Available filter names are:
   wiki      : Search in all wiki pages.
   ticket    : Search the description and comments of all tickets.
   changeset : Search the commit log of all changesets.")

(defcustom tracwiki-max-history 100
  "*Maximum number of wiki page revisions to fetch.
See `trac-wiki-history'.")

(defcustom tracwiki-history-count 10
  "*Normal number of wiki page revisions to fetch.
See `trac-wiki-history'.")

(defcustom tracwiki-use-keepalive
  (and (boundp 'url-http-real-basic-auth-storage)
       url-http-attempt-keepalives)
  "*If non-nil, use keep-alive option for http connection.
This value should be nil for old url library such as the one
on debian sarge stable .")

(defcustom tracwiki-update-page-name-cache-on-visit t
  "*If non-nil, update the page name cache on ever `trac-wiki-edit' call.
Collecting page names might be expensive for some environments and uses.
By setting this variable to nil, the page name cache is updated only when
invoking the `tracwiki' command or doing completion with the prefix in the
page edit buffer.")

;;;
;;; Internal variables
;;;
(defvar tracwiki-macro-name-cache nil
  "Alist of endpoint and macro name list.")

(defvar tracwiki-page-name-cache nil
  "Alist of endpoint and page name list.")

(defvar trac-rpc-endpoint nil)
(make-variable-buffer-local 'trac-rpc-endpoint)

(defvar tracwiki-project-info nil)
(make-variable-buffer-local 'tracwiki-project-info)

(defvar tracwiki-page-info nil)
(make-variable-buffer-local 'tracwiki-page-info)

(defvar tracwiki-search-keyword-hist nil)
(defvar tracwiki-search-filter-hist nil)

(defvar tracwiki-search-filter-cache nil
  "Alist of end-point and list of filter names supported in site.
This value is made automaticaly on first search access.")

(defconst tracwiki-system-pages
  '("CamelCase" "InterMapTxt" "InterTrac" "InterWiki"
    "RecentChanges" "TitleIndex"
    "TracAccessibility" "TracAdmin" "TracBackup" "TracBrowser"
    "TracCgi" "TracChangeset" "TracEnvironment" "TracFastCgi"
    "TracGuide" "TracHacks" "TracImport" "TracIni"
    "TracInstall" "TracInstallPlatforms" "TracInterfaceCustomization"
    "TracLinks" "TracLogging" "TracModPython" "TracMultipleProjects"
    "TracNotification" "TracPermissions" "TracPlugins" "TracQuery"
    "TracReports" "TracRevisionLog" "TracRoadmap" "TracRss"
    "TracSearch" "TracStandalone" "TracSupport" "TracSyntaxColoring"
    "TracTickets" "TracTicketsCustomFields" "TracTimeline"
    "TracUnicode" "TracUpgrade" "TracWiki" "WikiDeletePage"
    "WikiFormatting" "WikiHtml" "WikiMacros" "WikiNewPage"
    "WikiPageNames" "WikiProcessors" "WikiRestructuredText"
    "WikiRestructuredTextLinks"
    ;; appeared in 0.11
    "TracWorkflow" "PageTemplates")
  "List of page names provided by trac as default.
These files are hidden on completion since not edited usualy.
These can be listed setting by variable
`tracwiki-hide-system-pages' as nil.
Two pages WikiStart and SandBox is not in this list because
user may need or want to edit them.")

;; history holder
(defvar tracwiki-project-history nil)
(defvar tracwiki-url-history nil)
(defvar tracwiki-page-history nil)
(defvar tracwiki-comment-history nil)

(if (not (fboundp 'buffer-local-value))
    (defun buffer-local-value (sym buf)
      (if (not (buffer-live-p buf))
	  nil
	(with-current-buffer buf
	  (if (boundp sym)
	      (symbol-value sym)
	    nil)))))


;;; 
;;; Font Lock
;;;
(require 'font-lock)

(defvar tracwiki-italic-face 'tracwiki-italic-face
  "Face name to use for italics")
(defvar tracwiki-comment-face 'tracwiki-comment-face
  "Face name to use for Trac wiki comments.")
(defvar tracwiki-bold-face 'tracwiki-bold-face
  "Face name to use for bolded text")
(defvar tracwiki-bolditalic-face 'tracwiki-bolditalic-face
  "Face name to use for bold and italic text.")
(defvar tracwiki-underline-face 'tracwiki-underline-face
  "Face name to use for underlined text.")
(defvar tracwiki-strikethrough-face 'tracwiki-strikethrough-face
  "Face name to use for strikethrough text.")
(defvar tracwiki-definition-face 'tracwiki-definition-face
  "Face name to use for definition list keywords.")
(defvar tracwiki-superscript-face 'tracwiki-superscript-face
  "Face name to use for superscripted text.")
(defvar tracwiki-subscript-face 'tracwiki-subscript-face
  "Face name to use for subscripted text.")
(defvar tracwiki-header-face 'tracwiki-header-face
  "Face name to use for headers")
(defvar tracwiki-blockquote-face 'tracwiki-blockquote-face
  "Face name to use for blockquotes")
(defvar tracwiki-camelcase-face 'tracwiki-camelcase-face
  "Face name to use for CamelCase")
(defvar tracwiki-link-face 'tracwiki-link-face
  "Face name to use for links")

(defgroup tracwiki-faces nil
  "Faces used in Tracwiki mode"
  :group 'tracwiki
  :group 'faces)

(defface tracwiki-italic-face
  '((t (:inherit font-lock-variable-name-face :slant italic)))
  "Face for italic text."
  :group 'tracwiki-faces)

(defface tracwiki-comment-face
  '((t (:inherit font-lock-comment-face)))
  "Face for TracWiki comments."
  :group 'tracwiki-faces)

(defface tracwiki-bold-face
  '((t (:inherit font-lock-variable-name-face :weight bold)))
  "Face for bold text."
  :group 'tracwiki-faces)

(defface tracwiki-bolditalic-face
  '((t (:inherit tracwiki-bold-face :slant italic)))
  "Face for bold italic text."
  :group 'tracwiki-faces)

(defface tracwiki-underline-face
  '((t (:inherit underline)))
  "Face for underlined text."
  :group 'tracwiki-faces)

(defface tracwiki-strikethrough-face
  '((t (:inherit font-lock-variable-name-face :strike-through t)))
  "Face for strikethrough text."
  :group 'tracwiki-faces)

(defface tracwiki-definition-face
  '((t (:inherit font-lock-keyword-face :weight bold)))
  "Face for definition list keywords."
  :group 'tracwiki-faces)

(defface tracwiki-superscript-face
  '((t (:inherit default :height 0.8)))
  "Face for superscripting."
  :group 'tracwiki-faces)

(defface tracwiki-subscript-face
  '((t (:inherit underline :height 0.8)))
  "Face for subscripted text."
  :group 'tracwiki-faces)

(defface tracwiki-header-face
  '((t (:inherit font-lock-function-name-face :weight bold)))
  "Base face for headers."
  :group 'tracwiki-faces)

(defface tracwiki-link-face
  '((t (:inherit font-lock-type-face)))
  "Base face for [[link]] links"
  :group 'tracwiki-faces)

(defface tracwiki-camelcase-face
  '((t (:inherit font-lock-type-face)))
  "Base face for CamelCase links"
  :group 'tracwiki-faces)

(defface tracwiki-blockquote-face
  '((t (:inherit font-lock-builtin-face)))
  "Face for list item markers."
  :group 'tracwiki-faces)

(defconst tracwiki-regex-nowiki
  "`.*?`"
  "Regular expression matching Trac monospaced, unformatted text.")

(defconst tracwiki-regex-underline
  "__.*?__"
  "Regular expression matching Trac underlined text.")

(defconst tracwiki-regex-strikethrough
  "~~.*?~~"
  "Regular expression matching Trac strikethrough text.")

(defconst tracwiki-regex-link-link
  "\\[\\[\\w+]]"
  "Regular expression matching Trac double-bracket links.")

(defconst tracwiki-regex-issuelink
  "#[[:digit:]]+"
  "Regular expression matching trac issues")

(defconst tracwiki-regex-camelcase
  "\\([[:upper:]]\\{1\\}[[:lower:]]+/?\\)\\{2,\\}"
  "Regular expression matching Trac CamelCase.")

(defconst tracwiki-regex-uri
  (concat (regexp-opt tracwiki-uri-types) ":[^]\t\n\r<>,;() ]+")
  "Regular expression for matching inline URIs.")

(defconst tracwiki-regex-email
  "<\\(\\(\\sw\\|\\s_\\|\\s.\\)+@\\(\\sw\\|\\s_\\|\\s.\\)+\\)>"
  "Regular expression for matching inline email addresses.")

(defconst tracwiki-regex-link-generic
  (concat "\\(?:" tracwiki-regex-link-link
          "\\|" tracwiki-regex-camelcase
          "\\|" tracwiki-regex-issuelink
          "\\|" tracwiki-regex-uri
          "\\|" tracwiki-regex-email "\\)")
  "Regular expression for matching any recognized link.")

(defconst tracwiki-regex-superscript
  "\\^.*?\\^"
  "Regular expression matching Trac superscripted text.")

(defconst tracwiki-regex-subscript
  ",,.*?,,"
  "Regular expression matching Trac subscripted text.")

(defconst tracwiki-regex-bolditalic
  "'\\{5\\}.*?'\\{5\\}"
  "Regular expression matching Trac bolded + italic font")

(defconst tracwiki-regex-bold
  "'\\{3\\}.*?'\\{3\\}"
  "Regular expression matching Trac bolded font")

(defconst tracwiki-regex-italic
  "'\\{2\\}.*?'\\{2\\}"
  "Regular expression matching Trac italics")

(defconst tracwiki-regex-header
  "^[ \t]*=[ \t]*.*"
  "Regular expression matching Trac headers")

(defconst tracwiki-regex-definition
  "^[ \t]*.*?:\\{2\\}"
  "Regular expression matching Trac definition lists")

(defconst tracwiki-regex-blockquote
  "^[ \t]*>[ \t]*.*"
  "Regular expression matching Trac blockquotes")

(defun tracwiki-match-code-blocks (last)
  "Match code blocks from point to LAST."
  (let (open lang body close all)
    (cond ((and (eq major-mode 'tracwiki-mode)
                (search-forward-regexp "^\\({{{\\)\\(\\w+\\)?$" last t))
           (beginning-of-line)
           (setq open (list (match-beginning 1) (match-end 1))
                 lang (list (match-beginning 2) (match-end 2)))
           (forward-line)
           (setq body (list (point)))
           (cond ((search-forward-regexp "^}}}$" last t)
                  (setq body (reverse (cons (1- (match-beginning 0)) body))
                        close (list (match-beginning 0) (match-end 0))
                        all (list (car open) (match-end 0)))
                  (set-match-data (append all open lang body close))
                  t)
                 (t nil)))
          (t nil))))

(defun tracwiki-match-comment-blocks (last)
  "Match comment blocks from point to LAST."
  (let (open lang body close all)
    (cond ((and (eq major-mode 'tracwiki-mode)
                (search-forward-regexp "^\\({{{#!comment\\)\\(\\w+\\)?$" last t))
           (beginning-of-line)
           (setq open (list (match-beginning 1) (match-end 1))
                 lang (list (match-beginning 2) (match-end 2)))
           (forward-line)
           (setq body (list (point)))
           (cond ((search-forward-regexp "^}}}$" last t)
                  (setq body (reverse (cons (1- (match-beginning 0)) body))
                        close (list (match-beginning 0) (match-end 0))
                        all (list (car open) (match-end 0)))
                  (set-match-data (append all open lang body close))
                  t)
                 (t nil)))
          (t nil))))

(defconst tracwiki-mode-font-lock-keywords
  (list
   (cons 'tracwiki-match-comment-blocks 'tracwiki-comment-face)
   (cons 'tracwiki-match-code-blocks 'tracwiki-blockquote-face)
   (cons tracwiki-regex-nowiki 'tracwiki-blockquote-face)
   (cons tracwiki-regex-blockquote 'tracwiki-blockquote-face)
   (cons tracwiki-regex-link-generic 'tracwiki-link-face)
   (cons tracwiki-regex-email 'tracwiki-link-face)
   (cons tracwiki-regex-header 'tracwiki-header-face)
   (cons tracwiki-regex-definition 'tracwiki-definition-face)
   (cons tracwiki-regex-bolditalic 'tracwiki-bolditalic-face)
   (cons tracwiki-regex-strikethrough 'tracwiki-strikethrough-face)
   (cons tracwiki-regex-bold 'tracwiki-bold-face)
   (cons tracwiki-regex-italic 'tracwiki-italic-face)
   (cons tracwiki-regex-underline 'tracwiki-underline-face)
   (cons tracwiki-regex-superscript 'tracwiki-superscript-face)
   (cons tracwiki-regex-subscript 'tracwiki-subscript-face))
  "Font lock keywords used by TracWiki mode.")

(defun tracwiki-font-lock-extend-region ()
  "Extend the search region to include an entire block of text.
This helps improve font locking for block constructs such as pre blocks."
  ;; Avoid compiler warnings about these global variables from font-lock.el.
  ;; See the documentation for variable `font-lock-extend-region-functions'.
  (eval-when-compile (defvar font-lock-beg) (defvar font-lock-end))
  (save-excursion
    (goto-char font-lock-beg)
    (let ((found (or (re-search-backward "\n\n" nil t) (point-min))))
      (goto-char font-lock-end)
      (when (re-search-forward "\n\n" nil t)
        (beginning-of-line)
        (setq font-lock-end (point)))
      (setq font-lock-beg found))))

;;;
;;; Mode definition
;;;###autoload
(define-derived-mode tracwiki-mode text-mode "TracWiki"
  "Mode for Trac wiki text and tickets"
  ; Font locking. Ensure that case-fold is disabled!
  (set (make-local-variable 'font-lock-keywords-case-fold-search)
       nil)
  (set (make-local-variable 'font-lock-defaults) 
       '(tracwiki-mode-font-lock-keywords))

  ; Multiline font lock
  (add-hook 'font-lock-extend-region-functions
            'tracwiki-font-lock-extend-region))

(provide 'tracwiki-mode)
;;; tracwiki-mode.el ends here
