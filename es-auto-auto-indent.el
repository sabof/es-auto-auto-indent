;;; es-auto-auto-indent.el --- Indents code as you type
;;; Version: 0.1
;;; Author: sabof
;;; URL: https://github.com/sabof/es-auto-auto-indent
;;; Package-Requires: ((es-lib "0.1"))

;;; Commentary:

;; The project is hosted at https://github.com/sabof/es-auto-auto-indent
;; The latest version, and all the relevant information can be found there.

;;; License:

;; This file is NOT part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2, or (at
;; your option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program ; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Code:

(require 'es-lib)

(defvar es-aai-indent-function 'es-aai-indent-line-maybe
  "Indentation function to use call for automatic indentation.")
(defvar es-aai-indentable-line-p-function (es-constantly t)
  "For mode-specifc cusomizations.")
(defvar es-aai-after-change-indentation t
  "Whether to reindent after every change.
Useful when you want to keep the keymap and cursor repositioning.")
(defvar es-aai-indent-limit 30
  "Maximum number of lines for after-change indentation.")
(defvar es-aai-indented-yank-limit 4000
  "Maximum number of character to indent for `es-aai-indented-yank'")
(defvar es-aai-dont-indent-commands
  '(delete-horizontal-space
    quoted-insert
    backward-paragraph
    kill-region
    self-insert-command)
  "Commands after which not to indent.")
(defvar es-aai-mode-hook nil)

(es-define-buffer-local-vars
 es-aai--change-flag nil)

(defun es-aai-indent-line-maybe ()
  "\(indent-according-to-mode\) when `es-aai-indentable-line-p-function' returns non-nil.
All indentation happends through this function."
  (when (and es-aai-mode
             (not (memq indent-line-function
                        '(insert-tab indent-relative)))
             (funcall es-aai-indentable-line-p-function))
    (ignore-errors
      (indent-according-to-mode))))

(defun es-aai-indent-forward ()
  "Indent current line, and \(1- `es-aai-indent-limit'\) lines afterwards."
  (save-excursion
    (loop repeat es-aai-indent-limit do
          (es-aai-indent-line-maybe)
          (forward-line))))

(defun es-aai-widened-linum (&optional pos)
  (save-restriction
    (widen)
    (line-number-at-pos pos)))

(defun* es-aai--indent-region (start end)
  "Indent region lines where `es-aai-indentable-line-p-function' returns non-nil."
  (save-excursion
    (let ((end-line (line-number-at-pos end)))
      (goto-char start)
      (while (<= (line-number-at-pos) end-line)
        (es-aai-indent-line-maybe)
        (when (plusp (forward-line))
          (return-from es-aai--indent-region))))))

(defun es-aai-indent-defun ()
  "Indent current defun, if it is smaller than `es-aai-indent-limit'.
Otherwise call `es-aai-indent-forward'."
  (let (init-pos
        end-pos
        line-end-distance)
    (condition-case nil
        (save-excursion
          (end-of-defun)
          (beginning-of-defun)
          (setq init-pos (point))
          (end-of-defun)
          (when (> (1+ (- (line-number-at-pos)
                          (line-number-at-pos init-pos)))
                   es-aai-indent-limit)
            (error "defun too long"))
          (setq end-pos (point))
          (es-aai--indent-region init-pos end-pos))
      (error (es-aai-indent-forward)))))

(defun es-aai-indented-yank (&optional dont-indent)
  (interactive)
  (flet ((message (&rest ignore)))
    (when (region-active-p)
      (delete-region (point) (mark))
      (deactivate-mark))
    (let ((starting-point (point))
          end-distance
          line)
      (yank)
      (setq end-distance (- (line-end-position) (point))
            line (es-aai-widened-linum))
      (unless (or dont-indent
                  (> (- (point) starting-point)
                     es-aai-indented-yank-limit))
        (es-aai--indent-region starting-point (point)))
      ;; Necessary for web-mode. Possibly others
      ;; (when (and (bound-and-true-p font-lock-mode)
      ;;            (memq major-mode '(web-mode)))
      ;;   (font-lock-fontify-region starting-point (point)))
      (goto-line line)
      (goto-char (max (es-indentation-end-pos)
                      (- (line-end-position) end-distance)))
      (when (derived-mode-p 'comint-mode)
        (let ((point (point)))
          (skip-chars-backward " \t\n" starting-point)
          (delete-region (point) point)))
      (set-marker (mark-marker) starting-point (current-buffer)))))

(defun es-aai-mouse-yank (event &optional dont-indent)
  (interactive "e")
  (if (region-active-p)
      (let ((reg-beg (region-beginning))
            (reg-end (region-end)))
        (mouse-set-point event)
        (when (and (<= reg-beg (point))
                   (<= (point) reg-end))
          (delete-region reg-beg reg-end)
          (goto-char reg-beg)))
      (progn
        (mouse-set-point event)
        (deactivate-mark)))
  (es-aai-indented-yank dont-indent))

(defun es-aai-mouse-yank-dont-indent (event)
  (interactive "e")
  (es-aai-mouse-yank event t))

(defun es-aai-delete-char (&optional from-backspace)
  "Like `delete-char', but deletes indentation, if point is at it, or before it."
  (interactive)
  (if (region-active-p)
      (delete-region (point) (mark))
      (if (>= (point) (es-visible-end-of-line))
          (progn
            (delete-region (point) (1+ (line-end-position)))
            (when (and (es-fixup-whitespace)
                       (not from-backspace))
              (backward-char)))
          (delete-char 1))
      (es-aai-indent-line-maybe)))

(defun es-aai-backspace ()
  "Like `backward-delete-char', but removes the resulting gap when point is at EOL."
  (interactive)
  (cond ( (region-active-p)
          (delete-region (point) (mark)))
        ( (es-point-between-pairs-p)
          (delete-char 1)
          (delete-char -1))
        ( (<= (current-column)
              (current-indentation))
          (forward-line -1)
          (goto-char (line-end-position))
          (es-aai-delete-char t))
        ( (bound-and-true-p paredit-mode)
          (paredit-backward-delete))
        ( t (backward-delete-char 1))))

(defun es-aai-open-line ()
  "Open line, and indent the following."
  (interactive)
  (save-excursion
    (newline))
  (save-excursion
    (forward-char)
    (es-aai-indent-line-maybe))
  (es-aai-indent-line-maybe))

(defun* es-aai-newline-and-indent ()
  ;; This function won't run when cua--region-map is active
  (interactive)
  ;; For c-like languages
  (when (and (not (region-active-p))
             (equal (char-before) ?{ )
             (equal (char-after) ?} ))
    (newline)
    (save-excursion
      (newline))
    (es-aai-indent-line-maybe)
    (save-excursion
      (forward-char)
      (es-aai-indent-line-maybe))
    (return-from es-aai-newline-and-indent))
  (when (region-active-p)
    (delete-region (point) (mark))
    (deactivate-mark))
  (newline)
  (es-aai-indent-line-maybe)
  (when (memq major-mode '(nxml-mode web-mode))
    (save-excursion
      (forward-line -1)
      (es-aai-indent-line-maybe))))

(defun es-aai-correct-position-this ()
  "Go back to indentation if point is before indentation."
  (let ((indentation-beginning (es-indentation-end-pos)))
    (when (< (point) indentation-beginning)
      (goto-char indentation-beginning))))

(defun es-aai-before-change-function (&rest ignore)
  "Change tracking."
  (when es-aai-mode
    (setq es-aai--change-flag t)))

(defun* es-aai-post-command-hook ()
  "Correct the cursor, and possibly indent."
  (when (or (not es-aai-mode)
            cua--rectangle)
    (return-from es-aai-post-command-hook))
  (let* (( last-input-structural
           (member last-input-event
                   (mapcar 'string-to-char
                           (list "(" ")" "[" "]" "{" "}" "," ";" " "))))
         ( first-keystroke
           (and (eq this-command 'self-insert-command)
                (or last-input-structural
                    (not (eq last-command 'self-insert-command))))))
    ;; Correct position
    (when (or (not (region-active-p))
              deactivate-mark
              ;; (= (region-beginning)
              ;;    (region-end))
              )
      (when (and (es-neither (bound-and-true-p cua--rectangle)
                             (bound-and-true-p multiple-cursors-mode))
                 (> (es-indentation-end-pos) (point)))
        (cond ( (memq this-command '(backward-char left-char))
                (forward-line -1)
                (goto-char (line-end-position)))
              ( (memq this-command
                      '(forward-char right-char
                        previous-line next-line))
                (back-to-indentation))))
      ;; It won't indent if corrected
      (when (and es-aai-after-change-indentation
                 es-aai--change-flag
                 (buffer-modified-p)
                 (or first-keystroke
                     (not (memq this-command
                                (append '(save-buffer
                                          undo
                                          undo-tree-undo
                                          undo-tree-redo)
                                        es-aai-dont-indent-commands)))))
        (funcall es-aai-indent-function)
        (es-aai-correct-position-this)))
    (setq es-aai--change-flag nil)))

(defun es-aai--major-mode-setup ()
  "Optimizations for speicfic modes"
  (when (memq major-mode
              '(lisp-interaction-mode
                common-lisp-mode
                emacs-lisp-mode))
    (set (make-local-variable 'es-aai-indent-function)
         'es-aai-indent-defun)))

(defun es-aai--minor-mode-setup ()
  "Change interacting minor modes."
  (eval-after-load 'multiple-cursors-core
    '(pushnew 'es-aai-mode mc/unsupported-minor-modes))
  (eval-after-load 'paredit
    '(es-define-keys es-auto-auto-indent-mode-map
      [remap paredit-forward-delete] 'es-aai-delete-char
      [remap paredit-backward-delete] 'es-aai-backspace))
  (eval-after-load 'cua-base
    '(define-key cua--region-keymap [remap delete-char]
      (lambda ()
        (interactive)
        (if es-aai-mode
            (es-aai-delete-char)
            (cua-delete-region)))))
  (eval-after-load 'eldoc
    '(eldoc-add-command 'es-aai-indented-yank)))

(defun es-aai--init ()
  (run-hooks 'es-aai-mode-hook)
  (add-hook 'post-command-hook 'es-aai-post-command-hook t t)
  (pushnew 'es-aai-before-change-function before-change-functions)
  (when cua-mode
    (es-define-keys es-auto-auto-indent-mode-map
      (kbd "C-v") 'es-aai-indented-yank))
  (es-define-keys es-auto-auto-indent-mode-map
    [mouse-2] 'es-aai-mouse-yank
    [remap yank] 'es-aai-indented-yank
    [remap cua-paste] 'es-aai-indented-yank
    [remap newline] 'es-aai-newline-and-indent
    [remap open-line] 'es-aai-open-line
    [remap delete-char] 'es-aai-delete-char
    [remap forward-delete] 'es-aai-delete-char
    [remap backward-delete-char-untabify] 'es-aai-backspace
    [remap autopair-backspace] 'es-aai-backspace
    [remap backward-delete-char] 'es-aai-backspace
    [remap delete-backward-char] 'es-aai-backspace)
  (es-aai--minor-mode-setup)
  (es-aai--major-mode-setup))

;;;###autoload
(define-minor-mode es-auto-auto-indent-mode
    "Automatic automatic indentation.
Works pretty well for lisp out of the box.
Other modes might need some tweaking to set up:
If you trust the mode's automatic indentation completely, you can add to it's
init hook:

\(set \(make-local-variable 'es-aai-indent-function\)
     'es-aai-indent-defun\)

or

\(set \(make-local-variable 'es-aai-indent-function\)
     'es-aai-indent-forward\)

depending on whether the language has small and clearly
identifiable functions, that `beginning-of-defun' and
`end-of-defun' can find.

If on the other hand you don't trust the mode at all, but like
the cursor correction and delete-char behaviour,

you can add

\(set \(make-local-variable
      'es-aai-after-change-indentation\) nil\)

if the mode indents well in all but a few cases, you can change the
`es-aai-indentable-line-p-function'. This is what I have in my php mode setup:

\(set \(make-local-variable
      'es-aai-indentable-line-p-function\)
     \(lambda \(\)
       \(not \(or \(es-line-matches-p \"EOD\"\)
                \(es-line-matches-p \"EOT\"\)\)\)\)\)"
  nil " aai" (make-sparse-keymap)
  (if es-aai-mode
      (es-aai--init)))

(defalias 'es-aai-mode 'es-auto-auto-indent-mode)
(defvaralias 'es-aai-mode 'es-auto-auto-indent-mode)

(provide 'es-auto-auto-indent)
;;; es-auto-auto-indent.el ends here
