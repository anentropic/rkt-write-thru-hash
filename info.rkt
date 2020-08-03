#lang info

(define version "0.1")
(define name "write-thru-hash")
(define collection "write-thru-hash")
(define deps '("base"
               "db"
               "sql"
               "racket/fasl"
               "racket/hash"))
(define pkg-desc "Hash impersonators backed by persistent storage.")
(define pkg-authors '(anentropic))
