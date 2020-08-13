#lang racket/base

(require
  db
  net/base64
  racket/bool
  racket/contract
  racket/fasl
  racket/hash
  racket/serialize
  sql)

(define serializable-hash/c
  (hash/c serializable? serializable?))

(provide
  (contract-out
    [make-db-hash (->* (connection?)
                       (#:table-name string?
                        #:src-hash (or/c false? serializable-hash/c)
                        #:serializer (-> serializable? string?)
                        #:deserializer (-> string? serializable?))
                       (and/c serializable-hash/c (not/c immutable?)))])
  DEFAULT-TABLE-NAME
  DEFAULT-SERIALIZER
  DEFAULT-DESERIALIZER)

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
    (lambda (hash key)
      (values key
              (lambda (hash key val) val)))
    ;; set-proc
    ; TODO: what if the hash-table rejects the set op after we store in db?
    ; (I don't think that can happen)
    (lambda (hash key val)
      (query-exec db-conn
        (format
          "INSERT INTO ~a (key, value) VALUES ($1, $2) ON CONFLICT (key) DO UPDATE SET value=$2"
          table-name)
        (serializer key) (serializer val))
      (values key val))
    ;; remove-proc
    (lambda (hash key)
      (query-exec db-conn
        (format "DELETE FROM ~a WHERE key = $1" table-name)
        (serializer key))
      key)
    ;; key-proc (no-op)
    (lambda (hash key) key)
    ;; clear-proc (optional)
    (lambda (hash)
      (query-exec db-conn
        (format "DELETE FROM ~a" table-name)))
    ;; equal-key-proc (optional, no-op)
    ; TODO: is there a risk of keys which compare unequal having the same
    ; db key after fasl serialization?
    (lambda (hash key) key)))

;; Public

(define DEFAULT-TABLE-NAME "hashtable")

(define DEFAULT-SERIALIZER
  (lambda (value)
    (bytes->string/latin-1 (base64-encode (s-exp->fasl (serialize value))))))

(define DEFAULT-DESERIALIZER
  (lambda (value)
    (deserialize (fasl->s-exp (base64-decode (string->bytes/latin-1 value))))))

(define (make-db-hash db-conn #:table-name   [table-name DEFAULT-TABLE-NAME]
                              #:src-hash     [src-hash #f]
                              #:serializer   [serializer DEFAULT-SERIALIZER]
                              #:deserializer [deserializer DEFAULT-DESERIALIZER])
  ;; mutable hash impersonator backed by db storage
  ;; (we de/serialize both keys and values)

  ;; we want to properly quote table-name according to the current db style
  (define db-type (dbsystem-name (connection-dbsystem db-conn)))
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

  ;; TODO: we could possibly introspect the contract of src-hash
  ; > (value-contract make-theory)
  ; (-> (and/c hash? (not/c immutable?)))
  ; > (contract-projection (value-contract make-theory))
  ; #<procedure:...ow-val-first.rkt:1692:5>

  (when src-hash
    (hash-clear! storage-hash)
    (hash-union! storage-hash src-hash))
  
  storage-hash)
