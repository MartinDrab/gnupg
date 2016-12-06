#!/usr/bin/env gpgscm

;; Copyright (C) 2016 g10 Code GmbH
;;
;; This file is part of GnuPG.
;;
;; GnuPG is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3 of the License, or
;; (at your option) any later version.
;;
;; GnuPG is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; if not, see <http://www.gnu.org/licenses/>.

(load (with-path "defs.scm"))
(setup-environment)

;; Redefine GPG without --always-trust and a fixed time.
(define GPG `(,(tool 'gpg) --no-permission-warning
	      --faked-system-time=1480943782))
(define GNUPGHOME (getenv "GNUPGHOME"))
(if (string=? "" GNUPGHOME)
    (error "GNUPGHOME not set"))

(catch (skip "Tofu not supported")
       (call-check `(,@GPG --trust-model=tofu --list-config)))

(define KEYS '("1C005AF3" "BE04EB2B" "B662E42F"))

;; Import the test keys.
(for-each (lambda (keyid)
            (call-check `(,@GPG --import
                                ,(in-srcdir "tofu/conflicting/"
                                            (string-append keyid ".gpg"))))
	    (catch (error "Missing key" keyid)
		   (call-check `(,@GPG --list-keys ,keyid))))
	  KEYS)

;; Get tofu policy for KEYID.  Any remaining arguments are simply
;; passed to GPG.
;;
;; This function only supports keys with a single user id.
(define (getpolicy keyid . args)
  (let ((policy
	 (list-ref (assoc "tfs" (gpg-with-colons
				 `(--trust-model=tofu --with-tofu-info
				   ,@args
				   --list-keys ,keyid))) 5)))
    (unless (member policy '("auto" "good" "unknown" "bad" "ask"))
	    (error "Bad policy:" policy))
    policy))

;; Check that KEYID's tofu policy matches EXPECTED-POLICY.  Any
;; remaining arguments are simply passed to GPG.
;;
;; This function only supports keys with a single user id.
(define (checkpolicy keyid expected-policy . args)
  (let ((policy (apply getpolicy `(,keyid ,@args))))
    (unless (string=? policy expected-policy)
	    (error keyid ": Expected policy to be" expected-policy
		   "but got" policy))))

;; Get the trust level for KEYID.  Any remaining arguments are simply
;; passed to GPG.
;;
;; This function only supports keys with a single user id.
(define (gettrust keyid . args)
  (let ((trust
	 (list-ref (assoc "pub" (gpg-with-colons
				 `(--trust-model=tofu
				   ,@args
				   --list-keys ,keyid))) 1)))
    (unless (and (= 1 (string-length trust))
		 (member (string-ref trust 0) (string->list "oidreqnmfuws-")))
	    (error "Bad trust value:" trust))
    trust))

;; Check that KEYID's trust level matches EXPECTED-TRUST.  Any
;; remaining arguments are simply passed to GPG.
;;
;; This function only supports keys with a single user id.
(define (checktrust keyid expected-trust . args)
  (let ((trust (apply gettrust `(,keyid ,@args))))
    (unless (string=? trust expected-trust)
	    (error keyid ": Expected trust to be" expected-trust
		   "but got" trust))))

;; Set key KEYID's policy to POLICY.  Any remaining arguments are
;; passed as options to gpg.
(define (setpolicy keyid policy . args)
  (call-check `(,@GPG --trust-model=tofu ,@args
		      --tofu-policy ,policy ,keyid)))

(info "Checking tofu policies and trust...")

;; Carefully remove the TOFU db.
(catch '() (unlink (string-append GNUPGHOME "/tofu.db")))

;; Verify a message.  There should be no conflict and the trust
;; policy should be set to auto.
(call-check `(,@GPG --trust-model=tofu
		    --verify ,(in-srcdir "tofu/conflicting/1C005AF3-1.txt")))

(checkpolicy "1C005AF3" "auto")
;; Check default trust.
(checktrust "1C005AF3" "m")

;; Trust should be derived lazily.  Thus, if the policy is set to
;; auto and we change --tofu-default-policy, then the trust should
;; change as well.  Try it.
(checktrust "1C005AF3" "f" '--tofu-default-policy=good)
(checktrust "1C005AF3" "-" '--tofu-default-policy=unknown)
(checktrust "1C005AF3" "n" '--tofu-default-policy=bad)

;; Change the policy to something other than auto and make sure the
;; policy and the trust are correct.
(for-each-p
 "Setting a fixed policy..."
 (lambda (policy)
   (let ((expected-trust
	  (cond
	   ((string=? "good" policy) "f")
	   ((string=? "unknown" policy) "-")
	   (else "n"))))
     (setpolicy "1C005AF3" policy)

     ;; Since we have a fixed policy, the trust level shouldn't
     ;; change if we change the default policy.
     (for-each-p
      ""
      (lambda (default-policy)
	(checkpolicy "1C005AF3" policy
		     '--tofu-default-policy default-policy)
	(checktrust "1C005AF3" expected-trust
		    '--tofu-default-policy default-policy))
      '("auto" "good" "unknown" "bad" "ask"))))
 '("good" "unknown" "bad"))

;; At the end, 1C005AF3's policy should be bad.
(checkpolicy "1C005AF3" "bad")

;; 1C005AF3 and BE04EB2B conflict.  A policy setting of "auto"
;; (BE04EB2B's state) will result in an effective policy of ask.  But,
;; a policy setting of "bad" will result in an effective policy of
;; bad.
(setpolicy "BE04EB2B" "auto")
(checkpolicy "BE04EB2B" "ask")
(checkpolicy "1C005AF3" "bad")

;; 1C005AF3, B662E42F, and BE04EB2B conflict.  We change BE04EB2B's
;; policy to auto and leave 1C005AF3's policy at bad.  This conflict
;; should cause BE04EB2B's effective policy to be ask (since it is
;; auto), but not affect 1C005AF3's policy.
(setpolicy "BE04EB2B" "auto")
(checkpolicy "BE04EB2B" "ask")
(call-check `(,@GPG --trust-model=tofu
		    --verify ,(in-srcdir "tofu/conflicting/B662E42F-1.txt")))
(checkpolicy "BE04EB2B" "ask")
(checkpolicy "1C005AF3" "bad")
(checkpolicy "B662E42F" "ask")

;; Check that the stats are emitted correctly.

(display "Checking TOFU stats...\n")

(define (check-counts keyid expected-sigs expected-encs . args)
  (let*
      ((tfs (assoc "tfs"
                   (gpg-with-colons
                    `(--trust-model=tofu --with-tofu-info
                                         ,@args --list-keys ,keyid))))
       (sigs (string->number (list-ref tfs 3)))
       (encs (string->number (list-ref tfs 4))))
    (unless (= sigs expected-sigs)
            (error keyid ": # signatures (" sigs ") does not match expected"
                   "# signatures (" expected-sigs ").\n"))
    (unless (= encs expected-encs)
            (error keyid ": # encryptions (" encs ") does not match expected"
                   "# encryptions (" expected-encs ").\n"))
    ))

;; Carefully remove the TOFU db.
(catch '() (unlink (string-append GNUPGHOME "/tofu.db")))

(check-counts "1C005AF3" 0 0)
(check-counts "BE04EB2B" 0 0)
(check-counts "B662E42F" 0 0)

;; Verify a message.  The signature count should increase by 1.
(call-check `(,@GPG --trust-model=tofu
		    --verify ,(in-srcdir "tofu/conflicting/1C005AF3-1.txt")))
(check-counts "1C005AF3" 1 0)

;; Verify the same message.  The signature count should remain the
;; same.
(call-check `(,@GPG --trust-model=tofu
		    --verify ,(in-srcdir "tofu/conflicting/1C005AF3-1.txt")))
(check-counts "1C005AF3" 1 0)

;; Verify another message.
(call-check `(,@GPG --trust-model=tofu
		    --verify ,(in-srcdir "tofu/conflicting/1C005AF3-2.txt")))
(check-counts "1C005AF3" 2 0)

;; Verify another message.
(call-check `(,@GPG --trust-model=tofu
		    --verify ,(in-srcdir "tofu/conflicting/1C005AF3-3.txt")))
(check-counts "1C005AF3" 3 0)

;; Verify a message from a different sender.  The signature count
;; should increase by 1 for that key.
(call-check `(,@GPG --trust-model=tofu
		    --verify ,(in-srcdir "tofu/conflicting/BE04EB2B-1.txt")))
(check-counts "1C005AF3" 3 0)
(check-counts "BE04EB2B" 1 0)
(check-counts "B662E42F" 0 0)


;; Check that we detect the following attack:
;;
;; Alice and Bob each have a key and cross sign them.  Bob then adds a
;; new user id, "Alice".  TOFU should now detect a conflict, because
;; Alice only signed Bob's "Bob" user id.

(display "Checking cross sigs...\n")
(define GPG `(,(tool 'gpg) --no-permission-warning
	      --faked-system-time=1476304861))

;; Carefully remove the TOFU db.
(catch '() (unlink (string-append GNUPGHOME "/tofu.db")))

(define DIR "tofu/cross-sigs")
;; The test keys.
(define KEYA "1938C3A0E4674B6C217AC0B987DB2814EC38277E")
(define KEYB "DC463A16E42F03240D76E8BA8B48C6BD871C2247")
(define KEYIDA (substring KEYA (- (string-length KEYA) 8)))
(define KEYIDB (substring KEYB (- (string-length KEYB) 8)))

(define (verify-messages)
  (for-each
   (lambda (key)
     (for-each
      (lambda (i)
        (let ((fn (in-srcdir DIR (string-append key "-" i ".txt"))))
          (call-check `(,@GPG --trust-model=tofu --verify ,fn))))
      (list "1" "2")))
   (list KEYIDA KEYIDB)))

;; Import the public keys.
(display "    > Two keys. ")
(call-check `(,@GPG --import ,(in-srcdir DIR (string-append KEYIDA "-1.gpg"))))
(call-check `(,@GPG --import ,(in-srcdir DIR (string-append KEYIDB "-1.gpg"))))
;; Make sure the tofu engine registers the keys.
(verify-messages)
(display "<\n")

;; Since there is no conflict, the policy should be auto.
(checkpolicy KEYA "auto")
(checkpolicy KEYB "auto")

;; Import the cross sigs.
(display "    > Adding cross signatures. ")
(call-check `(,@GPG --import ,(in-srcdir DIR (string-append KEYIDA "-2.gpg"))))
(call-check `(,@GPG --import ,(in-srcdir DIR (string-append KEYIDB "-2.gpg"))))
(verify-messages)
(display "<\n")

;; There is still no conflict, so the policy shouldn't have changed.
(checkpolicy KEYA "auto")
(checkpolicy KEYB "auto")

;; Import the conflicting user id.
(display "    > Adding conflicting user id. ")
(call-check `(,@GPG --import ,(in-srcdir DIR (string-append KEYIDB "-3.gpg"))))
(verify-messages)
(display "<\n")

(checkpolicy KEYA "ask")
(checkpolicy KEYB "ask")

;; Import Alice's signature on the conflicting user id.  Since there
;; is now a cross signature, we should revert to the default policy.
(display "    > Adding cross signature on user id. ")
(call-check `(,@GPG --import ,(in-srcdir DIR (string-append KEYIDB "-4.gpg"))))
(verify-messages)
(display "<\n")

(checkpolicy KEYA "auto")
(checkpolicy KEYB "auto")

;; Remove the keys.
(call-check `(,@GPG --delete-key ,KEYA))
(call-check `(,@GPG --delete-key ,KEYB))


;; Check that we detect the following attack:
;;
;; Alice has an ultimately trusted key and she signs Bob's key.  Then
;; Bob adds a new user id, "Alice".  TOFU should now detect a
;; conflict, because Alice only signed Bob's "Bob" user id.
;;
;;
;; The Alice key:
;;   pub   rsa2048 2016-10-11 [SC]
;;         1938C3A0E4674B6C217AC0B987DB2814EC38277E
;;   uid           [ultimate] Spy Cow <spy@cow.com>
;;   sub   rsa2048 2016-10-11 [E]
;;
;; The Bob key:
;;
;;   pub   rsa2048 2016-10-11 [SC]
;;         DC463A16E42F03240D76E8BA8B48C6BD871C2247
;;   uid           [  full  ] Spy R. Cow <spy@cow.com>
;;   uid           [  full  ] Spy R. Cow <spy@cow.de>
;;   sub   rsa2048 2016-10-11 [E]

(display "Checking UTK sigs...\n")
(define GPG `(,(tool 'gpg) --no-permission-warning
	      --faked-system-time=1476304861))

;; Carefully remove the TOFU db.
(catch '() (unlink (string-append GNUPGHOME "/tofu.db")))

(define DIR "tofu/cross-sigs")
;; The test keys.
(define KEYA "1938C3A0E4674B6C217AC0B987DB2814EC38277E")
(define KEYB "DC463A16E42F03240D76E8BA8B48C6BD871C2247")
(define KEYIDA (substring KEYA (- (string-length KEYA) 8)))
(define KEYIDB (substring KEYB (- (string-length KEYB) 8)))

(define (verify-messages)
  (for-each
   (lambda (key)
     (for-each
      (lambda (i)
        (let ((fn (in-srcdir DIR (string-append key "-" i ".txt"))))
          (call-check `(,@GPG --trust-model=tofu --verify ,fn))))
      (list "1" "2")))
   (list KEYIDA KEYIDB)))

;; Import the public keys.
(display "    > Two keys. ")
(call-check `(,@GPG --import ,(in-srcdir DIR (string-append KEYIDA "-1.gpg"))))
(call-check `(,@GPG --import ,(in-srcdir DIR (string-append KEYIDB "-1.gpg"))))
(display "<\n")

(checkpolicy KEYA "auto")
(checkpolicy KEYB "auto")

;; Import the cross sigs.
(display "    > Adding cross signatures. ")
(call-check `(,@GPG --import ,(in-srcdir DIR (string-append KEYIDA "-2.gpg"))))
(call-check `(,@GPG --import ,(in-srcdir DIR (string-append KEYIDB "-2.gpg"))))
(display "<\n")

(checkpolicy KEYA "auto")
(checkpolicy KEYB "auto")

;; Make KEYA ultimately trusted.
(display (string-append "    > Marking " KEYA " as ultimately trusted. "))
(pipe:do
 (pipe:echo (string-append KEYA ":6:\n"))
 (pipe:gpg `(--import-ownertrust)))
(display "<\n")

;; An ultimately trusted key's policy is good.
(checkpolicy KEYA "good")
;; A key signed by a UTK for which there is no policy gets the default
;; policy of good.
(checkpolicy KEYB "good")

;; Import the conflicting user id.
(display "    > Adding conflicting user id. ")
(call-check `(,@GPG --import ,(in-srcdir DIR (string-append KEYIDB "-3.gpg"))))
(verify-messages)
(display "<\n")

(checkpolicy KEYA "good")
(checkpolicy KEYB "ask")

;; Import Alice's signature on the conflicting user id.
(display "    > Adding cross signature on user id. ")
(call-check `(,@GPG --import ,(in-srcdir DIR (string-append KEYIDB "-4.gpg"))))
(verify-messages)
(display "<\n")

(checkpolicy KEYA "good")
(checkpolicy KEYB "good")

;; Remove the keys.
(call-check `(,@GPG --delete-key ,KEYA))
(call-check `(,@GPG --delete-key ,KEYB))
