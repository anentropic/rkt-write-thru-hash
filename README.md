# write-thru-hash
Racket (mutable) [hash-table impersonators](https://docs.racket-lang.org/reference/chaperones.html#%28def._%28%28quote._~23~25kernel%29._impersonate-hash%29%29), backed by persistent storage.

The hash-table will then behave like a write-thru cache, any updates to the hash are persisted to the db and any lookups come directly from the hash-table itself.

### Installation

To install:
```
raco pkg install https://github.com/anentropic/rkt-write-thru-hash.git
```

...or to install without having `sql` dependency bring in the whole world:
```
raco pkg install --binary --no-docs sql
raco pkg install https://github.com/anentropic/rkt-write-thru-hash.git
```
(I guess this will not be necessary if I get around to uploading `write-thru-hash` to the package manager)

### Requirements

`make-db-hash` uses the `INSERT ... ON CONFLICT UPDATE` SQL statement to do an 'upsert' operation.

This means the following dbs are supported:
* SQLite > 3.24 (...a lot of systems have an older version pre-installed)
* Postgres > 9.5
* any other db which supports this upsert syntax, via an ODBC connection

MySQL would be possible but it uses a different upsert syntax, so is not supported for now.

### Usage

Currently this lib provides one function: `make-db-hash`.

Its signature looks like:
```racket
(define (make-db-hash db-conn #:table-name   [table-name "hashtable"]
                              #:src-hash     [src-hash #f]
                              #:serializer   [serializer s-exp->fasl]
                              #:deserializer [deserializer fasl->s-exp])
    ...)
```

The one required arg is a database conenction from the Racket `db` lib.

The first time you connect to a db, the storage table `<table-name>` will be created.

If the table already exists then any existing data in it will be pre-loaded into the resulting hash.

Instead, if an existing hash-table is supplied as `src-hash`, the db storage will be cleared and re-initialised with data from `src-hash`.

Keys and values are both serialized before writing to the db and deserialized when read initially.

So a basic usage example would look like:

```racket
(require db write-thru-hash)

(define db-conn (sqlite3-connect #:database "./db.sqlite"
                                 #:mode 'create))

(define myhash (make-db-hash db-conn))

(hash-set! myhash 'a 1)
(hash-set! myhash 'b 2)
(hash-set! myhash 'c 3)
(hash-remove! myhash 'c)
```

If you now close your `racket` session and open a new one:
```racket
(require db write-thru-hash)

(define db-conn (sqlite3-connect #:database "./db.sqlite"
                                 #:mode 'create))

(define myhash (make-db-hash db-conn))

(writeln myhash)
; #hash((a . 1) (b . 2))
```
...we can see the data was persisted to the db and reloaded into `myhash` when connecting it to the same db+table.

NOTE: Currently this is a one-way sync (hash->db) only. This means that if you instantiate multiple hash-tables from the same db+table, changes you make in any hash will be persisted to the db but won't be reflected in the contents of the other hashes for lookups.

I have no immediate plans to fix this, it's recommended just to have a 1-1 relation between hash-table and db+table.


