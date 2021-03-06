;;; org-annotate.el --- Inline-note link syntax for Org  -*- lexical-binding: t; -*-

;; Copyright (C) 2015  Eric Abrahamsen, Matti Minkkinen

;; Author: Eric Abrahamsen <eric@ericabrahamsen.net>, Matti Minkkinen <matti.minkkinen@iki.fi>

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Provides a new link type for Org that allows you to create
;; annotations on arbitrary chunks of text.  The link prefix is
;; "note:".

;; Add notes with `org-annotate-add-note'.  Following the link will
;; display the text of the note in a pop-up buffer.  The buffer is in
;; special-mode, hit "q" to dismiss it.

;; Call `org-annotate-display-notes' to see all notes in a buffer.
;; Press "?" in this buffer to see more options.

;; Customize how notes are exported in different backends by setting
;; the `org-annotate-[backend]-export-function' options, where
;; "backend" is a valid backend identifier.  Each option should point
;; to a function that accepts two arguments, the path and description
;; strings of the link, and returns a single formatted string for
;; insertion in the exported text.  Some default functions are
;; provided for HTML, LaTeX and ODT, see the `org-annotate-export-*'
;; functions.

;; Todo:

;; 1. Is it possible to have multi-line filled tabular list items?
;; Long notes are not very useful if you can't see the whole thing.

;; 2. Maybe a minor mode for ease of manipulating notes?

;;; With thanks to John Kitchin for getting the ball rolling, and
;;; contributing code:
;;; http://kitchingroup.cheme.cmu.edu/blog/2015/04/24/Commenting-in-org-files/

;;; Code:

(require 'org)
(require 'cl-lib)
(require 'dash)
(require 'tabulated-list)

;;;###autoload
(with-eval-after-load 'org
  (org-add-link-type
   "note"
   #'org-annotate-display-note
   #'org-annotate-export-note))

(defgroup org-annotate nil
  "Annotation link type for Org."
  :tag "Org Annotations"
  :group 'org)

(defcustom org-annotate-display-buffer "*Org Annotation*"
  "Name of the buffer for temporary display of note text."
  :group 'org-annotate
  :type 'string)

(defcustom org-annotate-list-buffer-prefix "*Org Annotation List: "
  "Common prefix for buffers displaying notes in an Org
buffer/subtree."
  :group 'org-annotate
  :type 'string)

(defcustom org-annotate-list-table-buffer "*Org Annotations Table*"
  "Name of buffer for temporary \"export\" of note list
buffers to Org table format."
  :group 'org-annotate
  :type 'string)

(defcustom org-annotate-html-export-function
  #'org-annotate-export-html-tooltip
  "The HTML export style for Org notes, as a symbol. Currently
only supports tooltip."
  :group 'org-annotate
  :type 'function)

(defcustom org-annotate-latex-export-function
  #'org-annotate-export-latex-marginpar
  "The LaTeX export style for Org notes, as a symbol. Currently
supports marginpar, todonote, and footnote."
  :group 'org-annotate
  :type 'function)

(defcustom org-annotate-odt-export-function
  #'org-annotate-export-odt-comment
  "The ODT export style for Org notes, as a symbol.  Currently
only supports comment."
  :group 'org-annotate
  :type 'function)

(defun org-annotate-export-html-tooltip (path desc)
  (format "<font color=\"red\"><abbr title=\"%s\" color=\"red\">COMMENT</abbr></font> %s" path (or desc "")))

(defun org-annotate-export-latex-todonote (path desc)
  (format "%s\\todo{%s}" (or desc "") path))

(defun org-annotate-export-latex-marginpar (path desc)
  (format "%s\\marginpar{%s}" (or desc "") path))

(defun org-annotate-export-latex-footnote (path desc)
  (format "%s\\footnote{%s}" (or desc "") path))

(defun org-annotate-export-latex-hl (path desc)
  (if (not (equal path ""))
      (format "\\hl{%s}\\todo{%s}" (or desc "") path)
    (format "\\hl{%s}" desc)))

(defun org-annotate-export-odt-comment (path desc)
  ;;; This doesn't currently work.
  (format "%s<office:annotation><dc:creator>%s</dc:creator><dc:date>%s</dc:date><text:p>%s</text:p></office:annotation>"
	  desc "I made this!"
	  (format-time-string "%FT%T%z" (current-time))
	  path))

;;;###autoload
(defun org-annotate-export-note (path desc format)
  (let ((export-func
	 (symbol-value
	  (intern-soft (format "org-annotate-%s-export-function" format)))))
    (if (and export-func
	     (fboundp export-func))
	(funcall export-func path desc)
      ;; If there's no function to handle the note, just delete it.
      desc)))

;;;###autoload
(defun org-annotate-display-note (linkstring)
  (when linkstring
    (with-current-buffer
	(get-buffer-create org-annotate-display-buffer)
      (let ((inhibit-read-only t))
	(erase-buffer)
	(insert linkstring)))
    (display-buffer-below-selected
     (get-buffer-create org-annotate-display-buffer)
     '(nil (window-height . fit-window-to-buffer)))
    (select-window (get-buffer-window org-annotate-display-buffer) t)
    (special-mode)
    (local-set-key (kbd "w") #'org-annotate-display-copy)))

(defun org-annotate-display-copy ()
  "Used within the special-mode buffers popped up using
`org-annotate-display-note', to copy the text of the note to the
kill ring.  Bound to \"w\" in those buffers."
  (interactive)
  (copy-region-as-kill
   (point-min)
   (save-excursion
     (goto-char (point-max))
     (skip-chars-backward " \n\t")
     (point))))

;;;###autoload
(defun org-annotate-add-note ()
  (interactive)
  (if (use-region-p)
      (let ((selected-text
	     (buffer-substring (region-beginning) (region-end))))
        (setf (buffer-substring (region-beginning) (region-end))
              (format "[[note:%s][%s]]"
                      (read-string "Note: ") selected-text)))
    (insert (format "[[note:%s]]" (read-string "Note: ")))))

;;;###autoload
(defun org-annotate-add-hashtag ()
  (interactive)
  (let ((hashtags
	 (mapconcat (lambda (x) (concat "#" x))
		    (completing-read-multiple "Hashtag: " (org-annotate-collect-hashtags)) ",")))
    (if (use-region-p)
	(let ((selected-text
	       (buffer-substring (region-beginning) (region-end))))
	  (setf (buffer-substring (region-beginning) (region-end))
		(format "[[note:%s][%s]]"
			hashtags selected-text)))
      (insert (format "[[note:%s]]" hashtags)))))

;; The purpose of making this buffer-local is defeated by the fact
;; that we only have one *Org Annotations List* buffer!
(defvar-local org-annotate-notes-source nil
  "Buffer/marker pair pointing to the source of notes for a
  given note-list buffer.")

;;;###autoload
(defun org-annotate-display-notes (arg)
  "Display all notes in the current buffer (or, with a prefix
arg, in the current subtree) in a tabulated list form."
  (interactive "P")
  (let* ((source-buf (current-buffer))
	 (marker (when arg
		   (save-excursion
		     (org-back-to-heading t)
		     (point-marker))))
	 (list-buf (get-buffer-create
		    (concat org-annotate-list-buffer-prefix
			    (buffer-name source-buf)
			    (if marker
				(concat "-"
					(number-to-string
					 (marker-position marker)))
			      "") "*"))))
    (switch-to-buffer-other-window list-buf)
    (unless (eq major-mode 'org-annotate-list-mode)
      (org-annotate-list-mode)
      (setq org-annotate-notes-source (cons source-buf marker)))
    (org-annotate-refresh-list)))

;;;###autoload
(defun org-annotate-display-notes-for-hashtag (&optional arg)
  "Display all notes for given hashtags in the current buffer in
a tabulated list form. Multiple comma-separated hashtags may be
given."
  (interactive "P")
  (let* ((hashtag (completing-read-multiple "Hashtag: " (org-annotate-collect-hashtags)))
	 (source-buf (current-buffer))
	 (marker)
	 (list-buf (get-buffer-create
		    (concat org-annotate-list-buffer-prefix
			    (buffer-name source-buf)
			    (if marker
				(concat "-"
					(number-to-string
					 (marker-position marker)))
			      "") "*"))))
    (switch-to-buffer-other-window list-buf)
    (unless (eq major-mode 'org-annotate-list-mode)
      (org-annotate-list-mode)
      (setq org-annotate-notes-source (cons source-buf marker)))
    (if arg
	(org-annotate-refresh-list-for-hashtag hashtag t)
      (org-annotate-refresh-list-for-hashtag hashtag))))

(defun org-annotate-collect-links ()
  "Do the work of finding all the notes in the current buffer
or subtree."
  (when org-annotate-notes-source
    (with-current-buffer (car org-annotate-notes-source)
      (save-restriction
	(widen)
	(let* ((marker (cdr org-annotate-notes-source))
	       (beg (or marker (point-min)))
	       (end (if marker
			(save-excursion
			  (goto-char marker)
			  (outline-next-heading)
			  (point))
		      (point-max)))
	       links)
	  (goto-char beg)
	  (while (re-search-forward org-bracket-link-regexp end t)
	    (let ((path (match-string-no-properties 1))
		  (text (match-string-no-properties 3))
		  start)
	      (when (string-match-p "\\`note:" path)
		(setq path
		      (org-link-unescape
		       (replace-regexp-in-string
			"\n+" " "
			(replace-regexp-in-string "\\`note:" "" path))))
		(setq text (if text
			       (org-link-unescape
				(replace-regexp-in-string "\n+" " " text))
			     "[no text]"))
		;; "start" (ie point at the beginning of the link), is
		;; used as the list item id in the tabular view, for
		;; finding specific notes.
		(setq start
		      (save-excursion
			(goto-char
			 (org-element-property :begin (org-element-context)))
			(point-marker)))
		;; The format required by tabular list mode.
		(push (list start (vector text path)) links))))
	  (when links
	    (reverse links)))))))

(defun org-annotate-collect-hashtags ()
  "Find all hashtags present in the current buffer."
  (save-restriction
    (widen)
    (save-excursion
      (let ((hashtag-list))
	(goto-char (point-min))
	(while (re-search-forward org-bracket-link-regexp (point-max) t) ; go through all links
	  (let ((path (match-string-no-properties 1))
		(text (match-string-no-properties 3)))
	    (when (string-match-p "\\`note:" path) ; we have a note link
	      ;; collect all hashtags from path
	      (while (string-match "#\\([^ ,%]+\\)" path)
		(push (match-string-no-properties 1 path) hashtag-list)
		(setq path
		      (replace-regexp-in-string (match-string-no-properties 1 path) "" path))))))
	(delete-dups hashtag-list)))))

(defun org-annotate-collect-links-for-hashtag (hashtag &optional arg)
  "Find all notes in the current buffer for the given hashtag.
Subtree searching not implemented yet. With prefix argument, also
include the org mode tags in the search."
  (when org-annotate-notes-source
    (with-current-buffer (car org-annotate-notes-source)
      (save-restriction
	(widen)
	(let* ((marker (cdr org-annotate-notes-source))
	       (beg (or marker (point-min)))
	       (end (if marker
			(save-excursion
			  (goto-char marker)
			  (outline-next-heading)
			  (point))
		      (point-max)))
	       links)
	  (goto-char beg)
	  (while (re-search-forward org-bracket-link-regexp end t)
	    (let ((path (match-string-no-properties 1))
		  (text (match-string-no-properties 3))
		  start)
	      (when arg
		(let* ((alltags (org-no-properties (org-entry-get (point) "ALLTAGS")))
		       (tags (if alltags (split-string alltags ":" t)
			       'nil))
		       (tagstring (concat " #" (mapconcat 'identity tags ",#") " ")))
		  (setq path
			(concat path tagstring))))
	      (when (and (string-match-p "\\`note:" path)
			 ;; all hashtags given in search must be in
			 ;; the path string
			 (-all? (lambda (x) (string-match-p (concat "#" x) path)) hashtag))
		(setq path
		      (org-link-unescape
		       (replace-regexp-in-string "\\`note:" "" path)))
		(setq text (if text
			       (org-link-unescape
				(replace-regexp-in-string "\n+" " " text))
			     "[no text]"))
		(setq start
		      (save-excursion
			(goto-char
			 (org-element-property :begin (org-element-context)))
			(point-marker)))
		(push (list start (vector text path)) links))))
	  (when links
	    (reverse links)))))))

(defun org-annotate-refresh-list ()
  (let ((links (org-annotate-collect-links))
	(max-width 0))
    (if links
	(progn
	  (dolist (l links)
	    (setq max-width
		  (max max-width
		       (string-width (aref (cadr l) 0)))))
	  (setq tabulated-list-entries links
		tabulated-list-format
		(vector `("Text" ,(min max-width 40) t) '("Note" 40 t)))
	  (tabulated-list-init-header)
	  (tabulated-list-print))
      (message "No notes found")
      nil)))

(defun org-annotate-refresh-list-for-hashtag (hashtag &optional arg)
  (let ((links (if arg
		   (org-annotate-collect-links-for-hashtag hashtag t)
		 (org-annotate-collect-links-for-hashtag hashtag)))
	(max-width 0))
    (if links
	(progn
	  (dolist (h links)
	    (setq max-width
		  (max max-width
		       (string-width (aref (cadr h) 0)))))
	  (setq tabulated-list-entries links
		tabulated-list-format
		(vector `("Text" ,(min max-width 60) t) '("Note" 20 t)))
	  (tabulated-list-init-header)
	  (tabulated-list-print))
      (message "No notes found for hashtag")
      nil)))

(defvar org-annotate-list-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map tabulated-list-mode-map)
    (define-key map (kbd "o") #'org-annotate-list-display)
    (define-key map (kbd "O") #'org-annotate-list-pop-to)
    (define-key map (kbd "d") #'org-annotate-list-delete)
    (define-key map (kbd "t") #'org-annotate-list-to-table)
    map)
  "Local keymap for Org annotations list buffers.")

(define-derived-mode org-annotate-list-mode
    tabulated-list-mode "Org Annotations"
  "Mode for viewing Org notes as a tabular list.

\\<org-annotate-list-mode-map>
\\{org-annotate-menu-mode-map}"
  (setq tabulated-list-sort-key nil)
  (add-hook 'tabulated-list-revert-hook
	    #'org-annotate-refresh-list nil t))

(defun org-annotate-list-pop-to ()
  (interactive)
  (let ((dest-marker (tabulated-list-get-id)))
    (switch-to-buffer-other-window (marker-buffer dest-marker))
    (goto-char dest-marker)))

(defun org-annotate-list-display ()
  (interactive)
  (let ((dest-marker (tabulated-list-get-id)))
    (display-buffer (marker-buffer dest-marker))
    (set-window-point
     (get-buffer-window (marker-buffer dest-marker))
     dest-marker)))

(defun org-annotate-list-delete ()
  (interactive)
  (let ((dest-marker (tabulated-list-get-id)))
    (display-buffer (marker-buffer dest-marker))
    (save-window-excursion
      (org-annotate-list-pop-to)
      (org-annotate-delete-note))
    (unless (org-annotate-refresh-list)
      (quit-window))))

(defun org-annotate-delete-note ()
  "Delete the note at point."
  (interactive)
  (let* ((elm (org-element-context))
	 (note-begin (org-element-property :begin elm))
	 (note-end (org-element-property :end elm))
	 (space-at-end (save-excursion
			 (goto-char note-end)
			 (looking-back " " (- (point) 2)))))

    (unless (string= (org-element-property :type elm) "note")
      (error "Not on a note"))

    (setf (buffer-substring note-begin note-end)
	  (cond
	   ;; The link has a description. Replace link with description
	   ((org-element-property :contents-begin elm)
	    (concat (buffer-substring
		     (org-element-property :contents-begin elm)
		     (org-element-property :contents-end elm))
		    (if space-at-end " " "")))
	   ;; No description. just delete the note
	   (t
	    "")))))

(defun org-annotate-list-to-table ()
  (interactive)
  (let ((entries
	 (mapcar
	  (lambda (e)
	    (list (aref (cadr e) 0) (aref (cadr e) 1)))
	  tabulated-list-entries))
	(source org-annotate-notes-source))
    (switch-to-buffer-other-window org-annotate-list-table-buffer)
    (erase-buffer)
    (insert "* Notes from " (buffer-name (car source)) "\n\n")
    (dolist (e entries)
      (insert (car e) "\t" (cadr e) "\n"))
    (org-mode)
    (org-table-convert-region
     (save-excursion
       (org-back-to-heading t)
       (forward-line 2)
       (point))
     (point) "\t")
    (org-reveal)))

;; * Colorizing note links
(defvar org-annotate-foreground "red"
  "Font color for notes.")

(defvar org-annotate-background "yellow"
  "Background color for notes.")

(defvar org-annotate-re
  "\\(\\[\\[\\)?note:\\([^]]\\)*\\]?\\[?\\([^]]\\)*\\(\\]\\]\\)"
  "Regex for note links. I am not sure how robust this is. It works so far.")

(defface org-annotate-face
  `((t (:inherit org-link
        :weight bold
        :background ,org-annotate-background
        :foreground ,org-annotate-foreground)))
  "Face for note links in org-mode.")

(defface org-annotate-overlay-face
  '((t (:foreground "MediumSeaGreen")))
  "Face for annotation overlays.")

(defface org-annotate-text-face
  '((t (:inherit default
        :underline t)))
  "Face for inline text of note links in org-mode.")

(defface org-annotate-bracket-face
  '((t (:inherit font-lock-comment-face)))
  "Face for visible brackets of note links in org mode")

(defvar org-annotate-font-lock-keywords
  '(("\\[\\(\\[\\)\\(note:\\)\\([^]]+\\)\\(\\]\\)\\]"
     (1 '(face org-annotate-bracket-face invisible nil) prepend)
     (2 '(face bold invisible nil) prepend)
     (3 '(face org-annotate-face invisible nil) prepend)
     (4 '(face org-annotate-bracket-face invisible nil) prepend))
    ("\\[\\(\\[\\)\\(note:\\)\\([^]]*\\)\\(\\]\\)\\[\\([^]]+\\)\\]\\]"
     (1 '(face org-annotate-bracket-face invisible nil) prepend)
     (2 '(face default invisible t) prepend)
     (3 '(face org-annotate-face invisible nil) prepend)
     (4 '(face org-annotate-bracket-face invisible nil) prepend)
     (5 'org-annotate-text-face prepend)))
  "Keywords for fontifying org-annotate notes")

(defun org-annotate-activate-colored-links ()
  (add-hook 'org-font-lock-set-keywords-hook #'org-annotate-colorize-links))

(defun org-annotate-deactivate-colored-links ()
  (remove-hook 'org-font-lock-set-keywords-hook #'org-annotate-colorize-links)
  (when (derived-mode-p 'org-mode)
    (org-mode)))

;;activate by default
(org-annotate-activate-colored-links)

(defun org-annotate-colorize-links ()
  (dolist (el org-annotate-font-lock-keywords)
    (add-to-list 'org-font-lock-extra-keywords el t)))

(defun org-annotate-make-overlays ()
  (interactive)
  "Make overlays to display annotations."
  (save-excursion
    (remove-overlays)
    (goto-char (point-min))
    (while (re-search-forward org-bracket-link-regexp (point-max) t)
      (let ((path (match-string-no-properties 1))
	    (text (match-string-no-properties 3))
	    (overlay (make-overlay (match-beginning 0) (match-end 0))))
	(when (and (string-match-p "\\`note:" path)
		   (not (equal () text)))
	  (overlay-put overlay 'before-string
		       (propertize
			(concat " " (replace-regexp-in-string "\\`note:" "" path) " ")
			'face 'org-annotate-overlay-face)))))))

;; * Org-mode menu
(defun org-annotate-org-menu ()
  "Add org-annotate menu to the Org menu."

  (easy-menu-change
   '("Org") "Annotations"
   '( ["Insert note" org-annotate-add-note]
      ["Delete note" org-annotate-delete-note]
      ["List notes" org-annotate-display-notes]
      "--"
      )
   "Show/Hide")

  (easy-menu-change '("Org") "--" nil "Show/Hide"))

(add-hook 'org-mode-hook 'org-annotate-org-menu)

(provide 'org-annotate)
;;; org-annotate.el ends here
