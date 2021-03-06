;; automrk.lisp

;; Libraries import:

(ql:quickload :cl-fad)
(ql:quickload :rutils)
(cl:in-package :rtl-user)
(ql:quickload :zip)
(SB-EXT:UNLOCK-PACKAGE 'CL) ; To avoid triggering errors caused by
                            ; package symbol renaming
;; (declaim (sb-ext:muffle-conditions cl:warning)) ; To turn off warnings
; Thanks to https://h4ck3r.net/2010/05/30/disable-style-warnings-on-sbcl/

;; Unit test macros

(defvar *results* nil)

(defvar *test-name* nil)


;; Added to handle detection of endless loop when evaluating test cases

;; Maximum running time (in seconds) allotted to the
;; evaluation of a test case. Once that time expires, the respective
;; thread is terminated, and a fail is associated to the respective
;; test case
(defvar *max-time* 5) 

(defvar *endless-loop* nil)

(defvar *runtime-error* nil)

(defun report-result (result form)
  (let ((res (not (or (eq result 'endless-loop)
		      (typep result 'condition)
		      (not result)))))
    (setf *results* (cons (list res result (car *test-name*) form) *results*))
    ;; (format t "~:[FAIL~;pass~] ...~a: ~a~%" result *test-name* form)
    res))

(defmacro with-gensyms ((&rest names) &body body)
  `(let ,(loop for n in names collect `(,n (gensym)))
     ,@body))

(defmacro combine-results (&body forms)
  (with-gensyms (result)
    `(let ((,result t))
       ,@(loop for f in forms collect `(unless ,f (setf ,result nil)))
       ,result)))

;; Added to handle detection of endless loop when evaluating test cases
(defmacro time-execution  (expr maxtime)
  "Evaluates expr in a separate thread. 
   If expr's execution time reaches maxtime seconds, then kills the thread and
   returns nil. Otherwise returns the result of evaluating expr."
  (let ((thread (gensym))
	(keep-time (gensym))
	(stime (gensym))
	(res (gensym)))
    `(let* ((,res nil)
	    (,thread (sb-thread:make-thread 
		     (lambda () (setf ,res ,expr)))))
       (labels ((,keep-time (,stime)
		  (cond ((and (> (/ (- (get-internal-real-time) ,stime) 
				    internal-time-units-per-second)
				 ,maxtime)
			      (sb-thread:thread-alive-p ,thread))
			 (progn
			   (sb-thread:terminate-thread ,thread)
			   (setf *endless-loop* (cons ',expr *endless-loop*))
			   (setf *runtime-error* t)
			   (setf ,res 'ENDLESS-LOOP)))
			 ((sb-thread:thread-alive-p ,thread) (,keep-time ,stime))
			 (t ,res))))
	 (,keep-time (get-internal-real-time))))))


;; Notice that now, before reporting a result, CHECK first times the execution of a test case
(defmacro check (&body forms)
  `(combine-results
     ,@(loop for f in forms collect
	     `(report-result (time-execution
			      (handler-case ,f
				(error (condition)
				  (setf *runtime-error* t)
				  condition))
			      ,*max-time*) ',f))))

#|
(defmacro check (&body forms)
  `(combine-results
     ,@(loop for f in forms collect `(report-result ,f ',f))))
|#

(defmacro deftest (name parameters &body body)
  `(defun ,name ,parameters
     (let ((*test-name* (append *test-name* (list ',name))))
       ,@body)))

;; Helper functions

(defun get-current-directory ()
  (let ((dir (uiop:run-program "sort" :input
    (uiop:process-info-output
      (uiop:launch-program "pwd" :output :stream)) :output :string)))
      (setf dir (remove #\newline dir))
      (return-from get-current-directory dir)))

(defun write-to-file (to-write file-name)
  (with-open-file 
  (stream-csv (merge-pathnames
    (concatenate 'string (get-current-directory) file-name) (user-homedir-pathname))
    :direction :output    ;; Write to disk
    :if-exists :append    ;; Append file if exists
    :if-does-not-exist :create)
  (format stream-csv "~a~%" to-write)))

(defun reset-file (file-name)
  (with-open-file 
  (stream-csv (merge-pathnames
    (concatenate 'string (get-current-directory) file-name) (user-homedir-pathname))
    :direction :output    ;; Write to disk
    :if-exists ::supersede    ;; Append file if exists
    :if-does-not-exist :create)
  ;; (format stream-csv "")
  ))

(defun list-to-string (lst)
  (format nil "~{~A~}" lst))
; From https://gist.github.com/tompurl/5174818

(defun split-string (string-to-split delimiter-char)
  (if (equal string-to-split nil)
  (return-from split-string (list ))
  (let ((current-word "") (return-words-list (list)))
    (loop for c across string-to-split do 
  (if (equal c delimiter-char)
    (progn
      (push (reverse current-word) return-words-list)
      ;; (print (reverse current-file))
      (setf current-word ""))
    (setf current-word (concatenate 'string (list-to-string (list c)) current-word))))
    (push (reverse current-word) return-words-list)
    (return-from split-string (reverse return-words-list)))))

(defun check-directory-exists (directory-name)
  (let* 
    ((dir-list-string (uiop:run-program "sort" :input
      (uiop:process-info-output
        (uiop:launch-program "ls" :output :stream)) :output :string))
     (dir-list (split-string dir-list-string #\newline)))
  (position directory-name dir-list :test #'equal)))

(defun get-current-date-time ()
  (multiple-value-bind
	(second minute hour date month year day-of-week dst-p tz)
	(get-decoded-time)
    (format nil "~2,'0d:~2,'0d:~2,'0d of ~a of ~d/~2,'0d/~d (GMT~@d) ~d"
	      hour minute second
	      (nth day-of-week '("Monday" "Tuesday" "Wednesday"
               "Thursday" "Friday" "Saturday"
               "Sunday"))
	      month date year (- tz) dst-p)))
; From http://cl-cookbook.sourceforge.net/dates_and_times.html with a slight modification.

(defun print-hash-table (hash-table)
  (loop for v being each hash-values of hash-table using (hash-key k)
      do (format t "~a ==> ~a~%" k v)))

(defparameter *mark-assignments-description* 
"mark-assignments (submissions-dir is-zipped grades-export-dir test-cases-dir weights)
-----------------------------------------------------------------------------
Description:  Goes through each student file, checks if it's a lisp file and has the requirements, 
              marks the file, and returns how many files were encountered.

Inputs:       1) submissions-dir [string]: The directory for the submissions of the students. Can be either a zip file or a regular folder.
              2) is-zipped [t/nil]: The boolean that informs the auto-marker that the submissions-dir is a zip or a regular folder. t for zip, nil for reular.
              3) grades-export-dir [string]: The grades export file of the students from D2L. Should be of a csv file format.
              4) test-cases-dir [string]: The test cases file. This will be used to test the submission files of the students for the current assignment.
              5) weights [list]: a list of pairs (<deftest-name> <weight>), where: <deftest-name> is the name of the test function defined in the unit test, and <weight> is a number from [0, 100] representing the weight of that function in the calculation of the total mark. Note: the sum of weight values has to be equal to 100.

Outputs:      [Integer] The number of files that were traversed.

Side-effects: 1) log.csv which is the log file that explains what has happened in the submissions as the auto-marker was traversing through it.
              2) report.csv which is the same as the grades-export-dir file but with the grades updated respectively. 
                 The grades will not be updated for students who did not submit a file or students who have a similar first and last name to other students.
              3) A Feedback folder that will hold the feedback files for students who did not get a full grade.
              4) A zipped version of the Feedback folder.
-----------------------------------------------------------------------------
Usage Example: Suppose you have downloaded from D2L the zipped file of the students' submissions alongside the grades export spreadsheet(csv) file and suppose
               that their directories are as follows: \"~/CPS305-Labs-correcting/submissions.zip\" and \"~/CPS305-Labs-correcting/grades-export.csv\". 
               Then to use the tool, make sure that the automrk.lisp file and the test case file (say \"~/CPS305-Labs-correcting/test-cases.lisp\") are in the same 
               directory and then type the following in slime:

               CL-USER> (load \"automrk.lisp\") ; Loading the auto-marker into the enviroment
               CL-USER> (mark-assignments \"~/CPS305-Labs-correcting/submissions.zip\" t 
                          \"~/CPS305-Labs-correcting/grades-export.csv\" \"~/CPS305-Labs-correcting/test-cases.lisp\")

               If you notice, \"~/CPS305-Labs-correcting\" was being typed in every argument. 
               This is not necessary as lisp will know which directory you mean by just typing the file name.
")

(defparameter *mark-std-solution-description*
"mark-std-solution (student-solution test-cases-dir &optional weights)
---------------------------------------------------
Description:  Loads the student-solution file, loads the test cases, runs
              the test cases, and returns the percentage of correct results over total results

Inputs:       1) student-solution [string]: The directory for the solution of the student.
              2) test-cases-dir [string]: The directory for the test cases file. This will be used to test the solution of the students for the current assignment.
              3) weights [list]: a list of pairs (<deftest-name> <weight>), where: <deftest-name> is the name of the test function defined in the unit test, and <weight> is a number from [0, 100] representing the weight of that function in the calculation of the total mark. Note: the sum of weight values has to be equal to 100

Outputs:      [list] A list of the following:
              1) [string] The grade of the student.
              2) [string] A comment that describes if there was a runtime error while loading the student submission or not
              3) [string] An edited descripting of what happened during runtime (from exceptions to conditions to whatever) that will have no #\\newline and #\\,characters
              4) [list] A readable version of the results of marking the students submission.
              5) [string] The unedited version of 3) description of what happened during runtime.

Side-effects: This function utilizes the global variable *results* while running. In the beginning by reseting it to nil, and at the end by updating it with the current
              student's submission results.
---------------------------------------------------
Usage Example: Say there was a student that you want to mark their submissions independantly from the other students. You can simply take their lisp submission file, say
               \"~/mysol.lisp\", and put it in the same folder as the \"automrk.lisp\" and the test cases lisp file \"test-cases.lisp\". Afterwards, you do as follows:

               CL-USER> (load \"automrk.lisp\") ; Loading the auto-marker into the enviroment
               CL-USER> (mark-std-solution \"mysol.lisp\" \"test-cases.lisp\") ; Calling the function to mysol.lisp
               CL-USER> (\"100.0\" \"OK\" \"No runtime errors\"
                        ((\"Pass\" TEST-DEPOSIT (EQUAL (DEPOSIT 20) 130))
                         (\"Pass\" TEST-DEPOSIT (EQUAL (DEPOSIT 10) 110))
                         (\"Pass\" TEST-DEPOSIT (NOT (DEPOSIT 10001)))
                         (\"Pass\" TEST-WITHDRAW (EQUAL (WITHDRAW 60) 10))
                         (\"Pass\" TEST-WITHDRAW (NOT (WITHDRAW 80)))
                         (\"Pass\" TEST-WITHDRAW (NOT (WITHDRAW 10001)))
                         (\"Pass\" TEST-WITHDRAW (EQUAL (WITHDRAW 20) 70))
                         (\"Pass\" TEST-WITHDRAW (EQUAL (WITHDRAW 10) 90)))
                        \"No runtime errors\")

Notes:         It is possible for the terminal to print other things according to the test cases,
               but in general, what will be returned from this function is something as seen above.
")

(defparameter *get-student-name-description* 
"get-student-name (pathname-string)
---------------------------------------------------
Description:  Parses the pathname of a student submission directory and
              return the first and last name  of the student as a string

Inputs:       pathname-string [string]: The string version of the directory for the solution of the student.

Outputs:      [string] the full name of the student in the format \"First-name Last-name\".

Side-effects: N/A
---------------------------------------------------
Usage Example: Say that one directory for a student in the submission folder (after being unzipped) is as follows: \"486192-137409 - Alex Adams - Nov 5, 2019 102 AM\",
               then, by calling this function, you will get the string \"Alex Adams\" returned like this:

               CL-USER> (load \"automrk.lisp\") ; Loading the auto-marker into the enviroment
               CL-USER> (get-student-name \"~/submissions/486192-137409 - Alex Adams - Nov 5, 2019 102 AM/\")
               CL-USER> Alex Adams
")

(defparameter *get-student-date-time-description* 
"get-student-date-time (pathname-string)
---------------------------------------------------
Description:  Parses the pathname of a student submission directory and
              return the date and time of submission as a list

Inputs:       pathname-string [string]: The string version of the directory for the solution of the student.

Outputs:      [list] A list of the following:
              1) [string] The date of submission of the student in the format \"Month-name dd yyyy\"
              2) [string] The hour of submission of the student in the format \"hour-minutes [PM/AM]\"

Side-effects: N/A
---------------------------------------------------
Usage Example: Say that one directory for a student in the submission folder (after being unzipped) is as follows: \"486192-137409 - Alex Adams - Nov 5, 2019 102 AM\",
               then, by calling this function, you will get the list (\"Nov 5 2019\" \"102 AM\") returned like this:

               CL-USER> (load \"automrk.lisp\") ; Loading the auto-marker into the enviroment
               CL-USER> (get-student-date-time \"~/submissions/486192-137409 - Alex Adams - Nov 5, 2019 102 AM/\")
               CL-USER> (\"Nov 5 2019\" \"102 AM\")
")

(defparameter *AUTO-MARKER-help-description* 
"AUTO-MARKER-help (func-name)
---------------------------------------------------
Description:  Provides explanation on how to use some of the functions involved with the auto-marker

Inputs:       func-name [string or symbol]: The string or symbolic representation of a function name.

Outputs:      nil

Side-effects: Will write on the terminal the complete explantation of the function placed in the argument.
---------------------------------------------------
Usage Example: Say that you want to know how to use the \"mark-std-solution\" function and want to learn more about it, then you do the following inside slime

               CL-USER> (load \"automrk.lisp\") ; Loading the auto-marker into the enviroment
               CL-USER> (AUTO-MARKER-help 'mark-std-solution) ; or (AUTO-MARKER-help \"mark-std-solution\")
               mark-std-solution (student-solution test-cases-dir)
               ---------------------------------------------------
               Description:  Loads the student-solution file ...
               ...

               CL-USER> nil
")

(defun AUTO-MARKER-help (&optional func-name)
  "Provides explanation on how to use some of the functions involved with the auto-marker."
  (let ((func-string (string-downcase (string func-name))))
    (cond 
      ((equal func-string "mark-assignments") (format t "~a" *mark-assignments-description*))
      ((equal func-string "mark-std-solution") (format t "~a" *mark-std-solution-description*))
      ((equal func-string "get-student-name") (format t "~a" *get-student-name-description*))
      ((equal func-string "get-student-date-time") (format t "~a" *get-student-date-time-description*))
      ((equal func-string "auto-marker-help") (format t "~a" *AUTO-MARKER-help-description*))
    (t (format t "You've placed wrong input. Usage of the help function is as follows:~%~a" *AUTO-MARKER-help-description*)))))


(defun get-num-correct-cases (results)
  "Gives the number of cases that returned T"
  (let ((counter 0))
    (loop for result in results do
      (if (first result)
      (incf counter)
      ;; (format t "> AUTO-MARKER: Student made a mistake~%")
      ))
    counter))

(defun get-total-cases (results)
  "Gives the number of cases"
  (length results))

;; Auto marker functions

(defun change-results-readable (results)
  (loop for result in results do
    (if (first result)
    (setf (first result) "Pass")
    (setf (first result) "Fail")))
  results)

(defun calc-mark (ws res)
  "Calculates student mark based on the results (res) from running the test 
cases and on the weight associated to each function. If ws is nil then
the mark is calculated as the # of passes divided by the total # of cases.
- ws is a list of pairs (<function-name> <weight>) Note: sum of weights must be 100
- res is the list stored in the global variable *results*"
  (labels ((get-avg (fn res accumPass accumT)
	     (dolist (x res (if (zerop accumT)
				(error "Test function ~S not defined in unit test" fn)
				(/ accumPass accumT)))
	       (when (equal fn (caddr x))
		 (if (car x)
		     (progn (incf accumPass)
			    (incf accumT))
		     (incf accumT))))))
    (if (null ws)
	(loop for r in res
	      when (car r)
		sum 1 into c
	      finally (return (* (/ c (length res)) 100)))
	(loop for w in ws 
	      sum (* (cadr w) (get-avg (car w) res 0 0))))))

(defun mark-std-solution (student-solution test-cases-dir &optional (ws nil))
  "Loads the student-solution file, loads the test cases, runs
  the test cases, and returns the percentage of correct results over total results"
  (let ((description "No runtime errors"))
  (progn
    (setf *results* nil)
    (setf *runtime-error* nil)
    (setf *endless-loop* nil)
    (load student-solution)
    (load test-cases-dir)
    (list (format nil "~f" (calc-mark ws *results*)) 
	  (if *runtime-error*
	      (:= description "Runtime error. ") "OK")
	  (if *endless-loop*
	      (:= description (concatenate 'string
				      description
				      (format nil "Endless loop when evaluating the following assertion(s):~%~{- ~A~%~}" (reverse *endless-loop*)))))
	  (change-results-readable *results*)
	  description)))) ;; Return percentage of grade.

(defun get-student-name (pathname-string)
  "Parses the pathname of a student submission directory and
  return the first and last name  of the student as a string"
  (handler-case 
    (let* ((pathname-list (split-string pathname-string #\/))
	         (std-dir-string (nth (- (length pathname-list) 2) pathname-list))
	         (std-dir-list (split-string std-dir-string #\-))
           (std-full-name (nth 2 std-dir-list))
           (std-full-name (subseq std-full-name 1 (- (length std-full-name) 1))))
      std-full-name)
    (t (e)
      (format t "~%> AUTO-MARKER: Cannot get student name due to ~a~%" e)
      nil)))

(defun get-student-date-time (pathname-string)
  "Parses the pathname of a student submission directory and
  return the date and time of submission as a list"
  (handler-case
    (let* ((pathname-list (split-string pathname-string #\/))
	         (std-dir-string (nth (- (length pathname-list) 2) pathname-list))
	         (std-dir-list (split-string std-dir-string #\-))
           (std-date-and-time  (first (last std-dir-list)))
           (std-date-and-time-list (split-string std-date-and-time #\space))
           (std-date 
            (concatenate 'string (second std-date-and-time-list) " " 
                                 (third std-date-and-time-list) " " 
                                 (fourth std-date-and-time-list)))
           (std-time (fifth std-date-and-time-list)))
      (list (remove #\, std-date) (concatenate 'string std-time " " (first (last std-date-and-time-list)))))
    (t (e)
      (format t "~%> AUTO-MARKER: Cannot get date and time due to ~a~%" e)
      nil)))

(defun get-student-code (pathname-string)
  "Parses the pathname of a student submission directory and
  return the code number of the student as a string"
  (handler-case
    (let* ((pathname-list (split-string pathname-string #\/))
	         (std-dir-string (nth (- (length pathname-list) 2) pathname-list))
           (std-code-number (first (split-string std-dir-string #\space))))
          (format nil "~a" std-code-number))
    (t (e)
      (format t "~%> AUTO-MARKER: Cannot get code number due to ~a~%" e)
      nil)))

(defun make-d2l-list (d2l-csv-pathname)
  (let* ((d2l-string (uiop:read-file-string (merge-pathnames D2L-csv-pathname (user-homedir-pathname))))
         (d2l-list (split-string d2l-string #\newline))
         (d2l-list (remove (first (last d2l-list)) d2l-list)))
    (progn
      (loop for line in d2l-list do
        (setf (nth (position line d2l-list) d2l-list) (split-string line #\,)))
      d2l-list)))

(defun make-d2l-hash-table (d2l-list) ;; Keys will have structure "LastName-FirstName" with spaces replaced with -.
  "Will make a hash table given a d2l-list.
  Will return the hash table and a list of the names which act as the keys."
  (let ((d2l-hash-table (make-hash-table)) (d2l-unused-names nil) (d2l-duplicated-names nil) (duplicate-tracker 0))
    (loop for entry in d2l-list do
      (let ((name-key-string (substitute #\- #\space (concatenate 'string (third entry) " " (second entry)))))
        (cond 
          ((position name-key-string d2l-unused-names :test #'equal)
            (progn
              (push name-key-string d2l-duplicated-names)
              (push name-key-string d2l-duplicated-names)
              (let ((to-remove-key (gethash (read-from-string name-key-string) d2l-hash-table)))
                (remhash (read-from-string name-key-string) d2l-hash-table)
                (:= d2l-unused-names (remove name-key-string d2l-unused-names :test #'equal))
                (setf (gethash (read-from-string (concatenate 'string name-key-string "-" (write-to-string duplicate-tracker))) d2l-hash-table) to-remove-key)
                (incf duplicate-tracker)
                (setf (gethash (read-from-string (concatenate 'string name-key-string "-" (write-to-string duplicate-tracker))) d2l-hash-table) entry)
                (incf duplicate-tracker))))
           ((position name-key-string d2l-duplicated-names :test #'equal)
            (progn
              (push name-key-string d2l-duplicated-names)
              (setf (gethash (read-from-string (concatenate 'string name-key-string "-" (write-to-string duplicate-tracker))) d2l-hash-table) entry)
              (incf duplicate-tracker)
              ))
          (t (progn 
            (push name-key-string d2l-unused-names)
            (setf (gethash (read-from-string name-key-string) d2l-hash-table) entry))))
          ;; (format t "tracker = ~a~%" duplicate-tracker)
          ))
    (:= d2l-unused-names (remove (first (last d2l-unused-names)) d2l-unused-names))
    ;; (format t "~a~%" d2l-unused-names)
    ;; (format t "------------------------------------------------~%")
    ;; (format t "~a~%" d2l-duplicated-names)
    ;; (format t "------------------------------------------------~%")
    ;; (print-hash-table d2l-hash-table)
    (list d2l-hash-table d2l-unused-names d2l-duplicated-names)))

(defun update-d2l-hash-grade (d2l-hash-table std-name-hash-key grade)
  "Updates the grade for the student if "
  (setf (nth 3 (gethash (read-from-string std-name-hash-key) d2l-hash-table)) grade))

(defun export-hash-table (hash-table)
  (let ((to-export-string ""))
    (loop for value being each hash-values of hash-table using (hash-key key) do
      (loop for item in value do
        (if (equal item (first (last value)))
        (:= to-export-string (concatenate 'string to-export-string (format nil "~a~%" item)))
        (:= to-export-string (concatenate 'string to-export-string (format nil "~a," item))))))
    (:= to-export-string (subseq to-export-string 0 (- (length to-export-string) 1)))
    to-export-string))

(defun get-feedback (std-name comment description results)
  (format nil
"- Student name: ~a

- Auto-Mark comment: ~a

- Auto-Mark description:
~a

- Test cases results:
~a" std-name  comment description results))

(defun unzip-folder (zip-file-dir)
  "Unzips the zip file in a new folder in the same directory it is in and returns the directory of the unzipped folder"
  (let* ((file-name (first (last (split-string zip-file-dir #\/))))
         (file-name (subseq file-name 0 (- (length file-name) 4)))
         (folder-dir (concatenate 'string (get-current-directory) "/" file-name "/")))
    (if (check-directory-exists file-name)
	(zip:unzip zip-file-dir folder-dir :if-exists :overwrite)
	(zip:unzip zip-file-dir folder-dir))
    folder-dir))

(defun zip-folder (folder-dir)
  "Zips the folder in a new folder in the same directory it is in and returns the directory of the zipped file.
  Make sure there is not / at the end of file-dir"
  (let*
    ((zipped-file (concatenate 'string folder-dir ".zip"))
     (zipped-file-name (first (last (split-string zipped-file #\/))))
     (to-zip (concatenate 'string folder-dir "/")))
    (if (check-directory-exists zipped-file-name)
	(zip:zip zipped-file to-zip :if-exists :overwrite)
	(zip:zip zipped-file to-zip))
    zipped-file))

(defun form-date-time (l)
  "Formats a date-time l, given in the format (<month day [year]> <time period>)
where <month day [year]>,  is a string in which the month is represented by three characters,
day and (optional) year are denote the day of the month and year, respectively, e.g., \"Nov 26 1966\",
<time period> is a string in which denoting the time and period, e.g., \"400 PM\", returning
a list (month day time period) where month and period are symbols and day, time numbers. E.g.
(form-date-time '(\"Nov 26 1999\" \"345 PM\")) returns '(NOV 26 345 PM)"
  (let ((date (car l))
	(time (cadr l)))
    (multiple-value-bind (month p1) (read-from-string date)
      (multiple-value-bind (tp p2) (read-from-string time)
	(let ((day (read-from-string (subseq date p1)))
	      (time tp) ;(if (<= tp 12) (* tp 100) tp))
	      (period (read-from-string (subseq time p2))))
	  (list month day time period))))))

  
(defun month->number (name)
  (case name
    (Jan 1)
    (Feb 2)
    (Mar 3)
    (Apr 4)
    (May 5)
    (Jun 6)
    (Jul 7)
    (Aug 8)
    (Sep 9)
    (Oct 10)
    (Nov 11)
    (Dec 12)))

(defun month->seconds (m)
  (* (month->number m) 30 24 60 60))

(defun day->sec (d)
  (* d 24 60 60))

(defun date->seconds (date)
  (+ (month->seconds (car date)) (day->sec (cadr date))))

(defun time-ampm->time-24hrs (time)
  (let ((h (car time))
	(p (cadr time)))
    (if (or (eq p 'am) 
	    (and (eq p 'pm) (>= h 1200) (<= h 1259)))
	h
	(+ h 1200))))
	  
(defun >time (tp1 tp2)
  (let ((t1 (time-ampm->time-24hrs tp1))
	(t2 (time-ampm->time-24hrs tp2)))
    (> t1 t2)))

(defun >date (dt1 dt2)
  "True if datetime d1 is greater than d2. Both are in 
the format (Nov 5 102 AM)"
  (let* ((date1 (list (car dt1) (cadr dt1)))
	 (time1 (cddr dt1))
	 (date2 (list (car dt2) (cadr dt2)))
	 (time2 (cddr dt2))
	 (datesec1 (date->seconds date1))
	 (datesec2 (date->seconds date2)))
    (or (> datesec1 datesec2)
	(and (= datesec1 datesec2)
	     (>time time1 time2)))))
	 
(defun check-dt (dt)
  (let ((m (car dt))
	(d (cadr dt))
	(td (if (<= (caddr dt) 12) (* (caddr dt) 100) (caddr dt)))
	(p (cadddr dt)))
    (list m d td p)))

(defun mark-assignments (submissions-dir is-zipped grades-export-dir test-cases-dir due-date-time &optional (weights nil))
  "Goes through each student file, checks if it's a lisp file and has the requirements, 
  marks the file, and returns how many files were encountered."
  (let ((submissions-choice nil))
    (if is-zipped
	(:= submissions-choice (unzip-folder submissions-dir))
	(:= submissions-choice submissions-dir))
    (reset-file "/report.csv")
    (reset-file "/log.csv")
    (ensure-directories-exist (concatenate 'string (get-current-directory) "/Feedback-folder/"))
    (write-to-file (format nil "Date,Time,Full Name,Grade,Comment,Description") "/log.csv")
    (let* ((a-counter 0)
	   (d2l-hash-table-maker (make-d2l-hash-table (make-d2l-list grades-export-dir)))
           (d2l-hash-table (first d2l-hash-table-maker))
	   (d2l-unused-names (second d2l-hash-table-maker))
	   (d2l-duplicated-names (third d2l-hash-table-maker)))
      (loop for duplicated-name in d2l-duplicated-names do
        (let ((std-name (substitute #\space #\- duplicated-name)))
          (write-to-file (format nil "~a,~a,~a,~f,~a,~a"
            "N/A" "N/A"
            std-name
            "N/A" "Duplicated_Name" "Student name is mentioned more than once") "/log.csv")))
      (fad:walk-directory submissions-choice
        (lambda (pathname)
          (let ((type (pathname-type pathname)))
            (if (string-equal type "lisp")
		(progn
		  (format t "~%> AUTO-MARKER: now in ~a~%" pathname)
		  (let* ((std-name (get-student-name (namestring pathname)))
			 (std-name-hash-key (substitute #\- #\space std-name))
			 (std-submission-date-time (get-student-date-time (namestring pathname)))
			 (formated-std-subm-dt (form-date-time std-submission-date-time))
			 (valid-std-due-dt (check-dt due-date-time))
			 (std-solution-list (if (>date  formated-std-subm-dt valid-std-due-dt)
						(list "0"
						      "OK"
						      (format nil "Late submission. Assignment due on: ~a Submitted on: ~a~%" due-date-time std-submission-date-time)
						      nil
						      (format nil "Late submission. Assignment due on: ~a Submitted on: ~a~%" due-date-time std-submission-date-time))
						(mark-std-solution pathname test-cases-dir weights)))
			 (std-code-number (get-student-code (namestring pathname))))
		    (if (position std-name-hash-key d2l-unused-names :test #'equal)
			(progn
			  (write-to-file (format nil "~a,~a,~a,~f,~a,~a" 
						 (first std-submission-date-time) (second std-submission-date-time)
						 std-name
						 (first std-solution-list) (second std-solution-list) (third std-solution-list)) "/log.csv")
			  (if (< (read-from-string (first std-solution-list)) 100)
			      (let ((feedback-dir (concatenate 'string "/Feedback-folder/" std-code-number " - " std-name-hash-key "-Feedback.txt")))
				(reset-file feedback-dir)
				(write-to-file (get-feedback std-name (second std-solution-list) (fifth std-solution-list) (fourth std-solution-list)) feedback-dir))
			      (format t "~%> AUTO-MARKER: Student ~a got a full grade~%"std-name))
			  (update-d2l-hash-grade d2l-hash-table std-name-hash-key (first std-solution-list))
			  (:= d2l-unused-names (remove std-name-hash-key d2l-unused-names :test #'equal)))
			(format t "~%> AUTO-MARKER: Student ~a has submitted a file, but there is an issue with the name~%" std-name)))
		  (incf a-counter))
		(let* ((std-name (get-student-name (namestring pathname)))
                       (std-name-hash-key (substitute #\- #\space std-name)))
		  (if (and (position std-name-hash-key d2l-unused-names :test #'equal) (not (equal type nil))) ;; !! DS_Store error !!
		      (let* ((std-submission-date-time (get-student-date-time (namestring pathname)))
			     (std-name (get-student-name (namestring pathname)))
			     (std-name-hash-key (substitute #\- #\space std-name)))
			(progn 
			  (write-to-file (format nil "~a,~a,~a,~f,~a,~a" 
						 (first std-submission-date-time) (second std-submission-date-time)
						 std-name
						 "0" "Wrong_Type" (format nil "Student has submitted a file with type .~a instead of .lisp" type)) "/log.csv")
			  (update-d2l-hash-grade d2l-hash-table std-name-hash-key 0)
			  (:= d2l-unused-names (remove std-name-hash-key d2l-unused-names :test #'equal)))
			(format t "~%> AUTO-MARKER: Invalid submission type .~a for ~a~%~%" type std-name))
		      (format t "~%> AUTO-MARKER: Invalid type .~a in ~a~%~%" type pathname)))))))
      (loop for unused-name in d2l-unused-names do
        (let ((std-name (substitute #\space #\- unused-name)))
          (write-to-file (format nil "~a,~a,~a,~f,~a,~a"
            "N/A" "N/A"
            std-name
            "N/A" "No_File" "Student has not submitted a file") "/log.csv")))
      ;; (format t "~%----------------------------------------------------------------------------~%")
      (format t "~%> AUTO-MARKER Report:~%")
      ;; (print-hash-table d2l-hash-table)
      ;; (print d2l-unused-names)
      (print (export-hash-table d2l-hash-table))
      ;; (format t "~%----------------------------------------------------------------------------~%")
      (write-to-file (export-hash-table d2l-hash-table) "/report.csv")
      (let ((feedback-folder-dir (concatenate 'string (get-current-directory) "/Feedback-folder")))
        (zip-folder feedback-folder-dir))
      ;; (write-to-file (format nil "Auto tool is used at: ~a" (get-current-date-time)) "/log.csv")
      (format t "~%~%> AUTO-MARKER: Marking of ~a complete~%All is good...~%" grades-export-dir)
      a-counter)))
