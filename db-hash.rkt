#lang racket/base

(require db
         racket/bool
         racket/contract
         racket/fasl
         racket/hash
         sql)

(provide
  (contract-out
    [make-db-hash (->* (connection?)
                       (#:table-name string?
                        #:src-hash (or/c false? hash?)
                        #:serializer (-> any/c bytes?)
                        #:deserializer (-> bytes? any/c))
                       (and/c hash? (not/c immutable?)))]))

;; Private helpers

(define (hash-from-db db-conn table-name deserializer)
  (make-hash
    (map
      (lambda (row) (cons (deserializer (vector-ref row 0))
                          (deserializer (vector-ref row 1))))
      (query-rows db-conn
        (format "SELECT key, value FROM ~a" table-name)))))

(define (make-impersonator db-conn table-name serializer target-hash)
  (impersonate-hash
    target-hash
    ;; ref-proc (no-op)
    (lambda (hash key) (values key (lambda (hash key val) val)))
    ;; set-proc
    (lambda (hash key val)
      (query-exec db-conn
        (format
          "INSERT INTO ~a (key, value) VALUES ($2, $3) ON CONFLICT (key) DO UPDATE SET value=$3"
          table-name)
        (serializer key) (serializer val))
      (values key val))
    ;; remove-proc
    (lambda (hash key)
      (query-exec db-conn
        (format "DELETE FROM ~a WHERE key = $2" table-name)
        (serializer key))
      key)
    ;; key-proc (no-op)
    (lambda (hash key) key)
    ;; clear-proc (optional)
    (lambda (hash)
      (query-exec db-conn
        (format "DELETE FROM ~a" table-name)))))

;; Public

(define (make-db-hash db-conn #:table-name   [table-name "hashtable"]
                              #:src-hash     [src-hash #f]
                              #:serializer   [serializer s-exp->fasl]
                              #:deserializer [deserializer fasl->s-exp])
  ;; mutable hash impersonator backed by db storage
  ;; (we de/serialize both keys and values)

  (define db-type (dbsystem-name (connection-dbsystem db-conn)))

  ;; we want to properly quote table-name according to the current db style
  (set! table-name
    (parameterize ((current-sql-dialect db-type))
      (sql-ast->string (ident-qq (Ident:AST ,(make-ident-ast table-name))))))

  (query-exec db-conn
    (format
      "CREATE TABLE IF NOT EXISTS ~a (key text NOT NULL, value text NOT NULL, PRIMARY KEY (key))"
      table-name))

  (define storage-hash
    (make-impersonator db-conn
                       table-name
                       serializer
                       (hash-from-db db-conn table-name deserializer)))

  (when src-hash
    (hash-clear! storage-hash)
    (hash-union! storage-hash src-hash))
  
  storage-hash)
