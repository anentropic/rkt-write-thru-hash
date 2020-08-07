#lang racket/base

(require
  db
  disposable
  fixture
  fixture/rackunit
  racket/function
  racket/serialize
  rackunit
  rackunit/text-ui
  sql
  "main.rkt")

(define POSTGRES-PASSWORD (getenv "POSTGRES_PASSWORD"))
(define POSTGRES-USER (getenv "POSTGRES_USER"))
(define POSTGRES-DB (getenv "POSTGRES_DB"))
(define POSTGRES-HOST (getenv "POSTGRES_HOST"))
(define SQLITE-DB-PATH (string->path (getenv "SQLITE_DB_PATH")))

;; Fixtures

(define-fixture sqlite-connection
  (disposable
    (lambda ()
      (sqlite3-connect #:database SQLITE-DB-PATH
                       #:mode 'create))
    (lambda (db-conn)
      (disconnect db-conn)
      (when
        (file-exists? SQLITE-DB-PATH)
        (delete-file SQLITE-DB-PATH)))))

(define (drop-tables db-conn)
  (map
    (lambda (table-name)
      (set! table-name
        (parameterize ((current-sql-dialect (dbsystem-name (connection-dbsystem db-conn))))
          (sql-ast->string (ident-qq (Ident:AST ,(make-ident-ast table-name))))))
      (query-exec db-conn
        (format "DROP TABLE IF EXISTS ~a" table-name)))
    (list-tables db-conn)))

(define-fixture postgres-connection
  (disposable
    (lambda ()
      (define db-conn
        (postgresql-connect #:user POSTGRES-USER
                            #:password POSTGRES-PASSWORD
                            #:database POSTGRES-DB
                            #:server POSTGRES-HOST))
      (drop-tables db-conn)
      db-conn)
    (lambda (db-conn)
      (drop-tables db-conn)
      (disconnect db-conn))))


;; Data-structures

; - keys and values must be `serializable?`
; - key at least must be #:transparent otherwise equivalent structs
;   will not compare `equal?`
(serializable-struct key-struct (subject-code id) #:transparent)
(serializable-struct doc-struct (author title content) #:transparent)

;; Test suites

(define db-test-suites
  (for/list ([db-type (list 'sqlite 'postgres)]
             [db-conn-fixture (list sqlite-connection
                                    postgres-connection)])
    (define suite-name (format "make-db-hash: ~a" db-type))
    (test-suite suite-name
      (test-case/fixture "basic operations"
        #:fixture db-conn-fixture
        (define db-conn (fixture-value db-conn-fixture))
        (define myhash (make-db-hash db-conn))
        (check-true (table-exists? db-conn DEFAULT-TABLE-NAME))
        (hash-set! myhash 'a 1)
        (hash-set! myhash 'b 2)
        (hash-set! myhash 'c 3)
        (hash-remove! myhash 'b)
        (check-equal? (hash-ref myhash 'a) 1)
        (check-equal? (hash-ref myhash 'c) 3)
        (define expected (make-hash (list (cons 'a 1) (cons 'c 3))))
        (check-equal? myhash expected)
        ; reload from db into a new identifier...
        (define myhash2 (make-db-hash db-conn))
        (check-equal? myhash2 expected)
        ; clear original hash...
        (hash-clear! myhash)
        ; reload from db into another new identifier...
        (define myhash3 (make-db-hash db-conn))
        (check-equal? myhash3 (make-hash)))
      (test-case/fixture "complex serializable keys and values"
        #:fixture db-conn-fixture
        (define db-conn (fixture-value db-conn-fixture))
        (define myhash (make-db-hash db-conn))
        (define key (key-struct (list 123 456 789) "abc123"))
        (define doc (doc-struct (list "Jim" "Bob") "Title A" "blah blah blah"))
        (hash-set! myhash key doc)
        (check-equal? (hash-ref myhash key) doc)
        (define expected (make-hash (list (cons key doc))))
        (check-equal? myhash expected)
        ; reload from db into a new identifier...
        (define myhash2 (make-db-hash db-conn))
        (check-equal? myhash2 expected))
      (test-case/fixture "custom table-name"
        #:fixture db-conn-fixture
        (define db-conn (fixture-value db-conn-fixture))
        (define custom-table-name "hopefully it is quoted properly")
        (define myhash (make-db-hash db-conn #:table-name custom-table-name))
        (check-true (table-exists? db-conn custom-table-name))
        (hash-set! myhash 'a 1)
        (check-equal? (hash-ref myhash 'a) 1)
        (define expected (make-hash (list (cons 'a 1))))
        (check-equal? myhash expected))
      (test-case/fixture "use initial src-hash"
        #:fixture db-conn-fixture
        (define db-conn (fixture-value db-conn-fixture))
        (define initial-hash (make-hash (list (cons 'abc 123) (cons 'def 456))))
        (define myhash (make-db-hash db-conn #:src-hash initial-hash))
        (check-true (table-exists? db-conn DEFAULT-TABLE-NAME))
        (check-equal? myhash initial-hash)
        (hash-set! myhash 'ghi 789)
        (define expected
          (make-hash (list (cons 'abc 123) (cons 'def 456) (cons 'ghi 789))))
        (check-equal? myhash expected)
        ; reload from db into a new identifier...
        (define myhash2 (make-db-hash db-conn))
        (check-equal? myhash2 expected)
        ; init db with a new src-hash (replacing existing data)...
        (define myhash3 (make-db-hash db-conn #:src-hash (hash 'jkl 101)))
        (check-equal? myhash3 (make-hash (list (cons 'jkl 101))))))))

;; Runner

(define all-tests (make-test-suite "db-test-suites" db-test-suites))

(run-tests all-tests)
